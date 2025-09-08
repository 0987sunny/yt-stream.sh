#!/usr/bin/env zsh

# Enforce non-root for security
if [[ $EUID -eq 0 ]]; then
  print -P "%F{red}✖ Do not run yt-stream as root. Run it as a regular user.%f"
  exit 1
fi

autoload -Uz colors; colors
setopt no_nomatch

# --- MPV SETTINGS ---
BUFFER_MB=400
READAHEAD_SEC=60
MPV_ARGS=(--no-config --vo=drm --ytdl-format='bestvideo[height<=1080]+bestaudio/best[height<=1080]'
          --cache=yes --cache-secs=$READAHEAD_SEC --demuxer-max-bytes=$((BUFFER_MB * 1024 * 1024))
          --terminal --keep-open=no --no-terminal-prompt --really-quiet)

# --- CONTROLS ---
autoplay=0
random_mode=0
declare -a play_history=()
play_index=0

# --- VIDEO HANDLING ---
play_video() {
  local index="$1"
  play_history+=($index)
  play_index=$#play_history

  local url="${urls[$index]}"
  local title="${titles[$index]}"
  print -P "%F{blue}▶ Playing:%f $title"

  if [[ $DISPLAY ]]; then
    mpv --vo=gpu "${MPV_ARGS[@]}" "$url"
  else
    mpv "${MPV_ARGS[@]}" "$url"
  fi

  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    if (( autoplay )); then
      if (( random_mode )); then
        play_random
      else
        local next=$(( index + 1 ))
        (( next <= $#urls )) && play_video $next
      fi
    fi
  fi
}

play_random() {
  local pick=$(( (RANDOM % $#urls) + 1 ))
  play_video $pick
}

prev_video() {
  (( play_index > 1 )) && play_video ${play_history[play_index-1]}
}

# --- PLAYLIST LOADING ---
load_playlist() {
  urls=("${(@f)$(yt-dlp --flat-playlist --print "url" "$1")}")
  titles=("${(@f)$(yt-dlp --flat-playlist --print "title" "$1")}")
}

# --- MAIN ---
if [[ -z "$1" ]]; then
  print -P "%F{red}✖ Usage:%f yt-stream \"<youtube-url>\""
  exit 1
fi

url="$1"
if [[ "$url" == *"list="* ]]; then
  load_playlist "$url"

  while true; do
    clear
    print -P "%F{magenta}Autoplay:%f $([[ $autoplay -eq 1 ]] && print -P '%F{green}ON%f' || print -P '%F{red}OFF%f')   %F{magenta}Random:%f $([[ $random_mode -eq 1 ]] && print -P '%F{green}ON%f' || print -P '%F{red}OFF%f')"
    print -P "%F{blue}Choose video:%f"

    choices=("❌ Exit ::: exit" "🔀 Random ::: random" "🎬 Autoplay ::: autoplay")
    for i in {1..$#titles}; do
      choices+=("${titles[$i]} ::: ${urls[$i]}")
    done

    selection=$(printf "%s\n" $choices | fzf --ansi --reverse --no-sort --bind "ctrl-r:execute-silent(echo toggle-random > /tmp/yt-stream-cmd)+reload(sync)" --bind "ctrl-a:execute-silent(echo toggle-autoplay > /tmp/yt-stream-cmd)+reload(sync)" --expect=esc --delimiter=' ::: ' --with-nth=1)

    key=${selection[1]}
    sel=${selection[2]}

    [[ "$key" == "esc" ]] && exit 0

    [[ -z "$sel" ]] && continue

    case "$sel" in
      exit) exit 0 ;;
      autoplay) autoplay=$(( ! autoplay )) ;;
      random) play_random ;;
      *)
        for i in {1..$#urls}; do
          [[ "$urls[$i]" == "$sel" ]] && play_video $i && break
        done
        ;;
    esac
  done
else
  mpv "${MPV_ARGS[@]}" "$url"
fi
