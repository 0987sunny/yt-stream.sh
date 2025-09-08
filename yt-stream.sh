#!/usr/bin/env zsh

# ┌──────────────────────────────────────────────────────┐
# │                 yt-stream: FINAL VERSION             │
# └──────────────────────────────────────────────────────┘

setopt no_nomatch
autoload -Uz colors; colors

# Prevent running as root (including via sudo)
if [[ "$EUID" -eq 0 ]]; then
  print -P "%F{red}✖ Do not run this script as root or with sudo.%f"
  exit 1
fi

# Dependencies check
for cmd in yt-dlp mpv fzf; do
  if ! command -v $cmd >/dev/null; then
    print -P "%F{red}Missing dependency: $cmd%f"
    exit 1
  fi
done

# Config
readonly mpv_flags=(
  --no-terminal
  --force-window=no
  --no-config
  --vo=drm
  --cache=yes
  --cache-secs=300
  --demuxer-max-bytes=400MiB
  --demuxer-readahead-secs=10
  --ytdl-format='bestvideo[height<=1080]+bestaudio/best'
)

# State
typeset -ga videos played_history
integer current_index=0 autoplay=0 random=0

# Playlist parsing
playlist_url="$1"
[[ -z "$playlist_url" ]] && { print -P "%F{red}✖ No playlist or video URL provided.%f"; exit 1 }

is_playlist() {
  [[ "$playlist_url" == *"list="* ]]
}

fetch_playlist() {
  videos=("${(@f)$(yt-dlp --flat-playlist --print "%title ::: %id" "$playlist_url" 2>/dev/null)}")
}

play_video() {
  local title="$1"
  local id="$2"
  played_history+=("$id")
  mpv "${mpv_flags[@]}" "https://youtube.com/watch?v=$id"
}

pick_random_index() {
  echo $(( RANDOM % ${#videos[@]} ))
}

prev_video() {
  if (( ${#played_history[@]} > 1 )); then
    played_history[-1]=()
    local prev_id="${played_history[-1]}"
    for idx in {1..${#videos[@]}}; do
      [[ "$videos[idx]" == *"$prev_id" ]] && current_index=$((idx - 1)) && break
    done
    play_video "${videos[$((current_index + 1))]%% ::: *}" "${prev_id}"
  fi
}

next_video() {
  if (( random )); then
    current_index=$(pick_random_index)
  else
    (( current_index = (current_index + 1) % ${#videos[@]} ))
  fi
  local entry="${videos[$((current_index + 1))]}"
  local title="${entry%% ::: *}"
  local id="${entry##*::: }"
  play_video "$title" "$id"
}

menu_loop() {
  while true; do
    local status
    status="\n%F{green}Playlist contains:%f ${#videos} videos"
    status+="\n%F{blue}Autoplay:%f ${(L)${autoplay:+ON}:-OFF}"
    status+="\n%F{magenta}Random:%f ${(L)${random:+ON}:-OFF}"

    local choices=(" Exit ::: exit" "不 Random ::: toggle-random" "車 Autoplay ::: toggle-autoplay")
    choices+=("${(@)videos}")

    local selected="$(
      print -l -- "${choices[@]}" | \
      fzf --ansi \
          --no-sort \
          --info=inline \
          --prompt=$'%F{blue}Choose video:%f ' \
          --header-first \
          --header="$status" \
          --bind 'ctrl-a:toggle-autoplay' \
          --bind 'ctrl-r:toggle-random' \
          --bind 'esc:abort'
    )" || return 0

    local action="${selected##*::: }"
    case "$action" in
      exit)
        return 0
        ;;
      toggle-random)
        (( random ^= 1 ))
        ;;
      toggle-autoplay)
        (( autoplay ^= 1 ))
        ;;
      *)
        current_index=$(( ${choices[(ie)$selected]} - 4 ))
        local title="${videos[$((current_index + 1))]%% ::: *}"
        local id="${videos[$((current_index + 1))]##*::: }"
        played_history+=("$id")

        mpv "${mpv_flags[@]}" \
            --input-conf=/dev/null \
            --input-terminal=yes \
            --term-playing-msg="" \
            --idle=no \
            --force-window=no \
            --script-opts=osc=no \
            --input-ipc-server=/tmp/mpv-socket-$$ \
            --keep-open=yes \
            --no-resume-playback \
            --no-ytdl \
            --script=~/.config/mpv/scripts/yt-stream-hooks.lua \
            "https://youtube.com/watch?v=$id"

        while true; do
          read -sk1 key
          case "$key" in
            $'\e')
              break
              ;;
            '') # Enter does nothing
              ;;
            $'\x1b[C') # Ctrl+Right
              next_video
              ;;
            $'\x1b[D') # Ctrl+Left
              prev_video
              ;;
          esac
          (( autoplay )) || break
        done
        ;;
    esac
  done
}

main() {
  if is_playlist; then
    fetch_playlist || { print -P "%F{red}✖ Failed to fetch playlist.%f"; exit 1 }
    menu_loop
  else
    mpv "${mpv_flags[@]}" "$playlist_url"
  fi
}

main
