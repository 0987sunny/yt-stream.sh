#!/usr/bin/env zsh

autoload -Uz colors && colors
autoload -Uz is-at-least

if [[ $EUID -eq 0 ]]; then
  print -P "%F{red}Do not run as root. Run without sudo.%f"
  exit 1
fi

if [[ -z "$1" ]]; then
  print -P "%F{red}Usage:%f yt-stream \"<YouTube URL>\""
  exit 1
fi

url="$1"
use_drm=0
[[ -z $WAYLAND_DISPLAY && -z $DISPLAY ]] && use_drm=1

mpv_flags=(
  --ytdl-format="bestvideo[height<=1080]+bestaudio/best"
  --cache=yes
  --cache-secs=300
  --demuxer-max-bytes=400MiB
  --demuxer-readahead-secs=30
  --no-terminal
  --force-window=no
  --quiet
  --cookies
  --no-resume-playback
)

(( use_drm )) && mpv_flags+=(--vo=drm --ao=alsa) || mpv_flags+=(--vo=gpu)

print_autoplay_status() {
  print -P "%F{blue}Autoplay:%f $([[ $autoplay -eq 1 ]] && echo ON || echo OFF)"
  print -P "%F{blue}Random:%f $([[ $random_mode -eq 1 ]] && echo ON || echo OFF)"
}

play_video() {
  local index="$1"
  local video_url="${video_urls[$index]}"
  clear
  print -P "%F{cyan}Now playing:%f $video_titles[$index]"
  play_history+=($index)
  play_index=$#play_history
  mpv "${mpv_flags[@]}" "$video_url"
  return $?
}

next_video() {
  if (( random_mode )); then
    play_random
  else
    (( index = play_history[-1] + 1 ))
    (( index > $#video_urls )) && index=1
    play_video $index
  fi
}

previous_video() {
  (( play_index-- ))
  (( play_index < 1 )) && play_index=1
  play_video $play_history[$play_index]
}

play_random() {
  local index=$(( RANDOM % $#video_urls + 1 ))
  play_video $index
}

run_selector() {
  while true; do
    clear
    print -P "%F{green}Playlist contains:%f $#video_urls videos"
    print_autoplay_status
    print ""

    menu_items=(
      "❌ Exit ::: exit"
      "🔀 Random ::: random"
      "📺 Autoplay ::: autoplay"
    )

    for i in {1..$#video_titles}; do
      menu_items+=("$i) $video_titles[$i] ::: $video_urls[$i]")
    done

    choice=$(printf '%s\n' "${menu_items[@]}" |
      fzf --ansi --no-sort --tac \
          --reverse --prompt="Choose video: " \
          --header="Ctrl-A: Toggle autoplay | Ctrl-R: Toggle random | Esc: Exit" \
          --bind='ctrl-a:toggle-autoplay,ctrl-r:toggle-random,esc:abort' \
          --expect=enter --with-nth=1)

    key=$(head -n1 <<< "$choice")
    selection=$(tail -n1 <<< "$choice" | sed 's/ :::.*//')

    case "$selection" in
      "❌ Exit") exit 0 ;;
      "🔀 Random") random_mode=$((1 - random_mode)) ;;
      "📺 Autoplay") autoplay=$((1 - autoplay)) ;;
      *)
        index="${selection%%)*}"
        [[ -n $index && $index -ge 1 && $index -le $#video_urls ]] && {
          play_video $index
          while (( autoplay )); do
            next_video
          done
        }
        ;;
    esac
  done
}

parse_playlist() {
  mapfile -t lines < <(yt-dlp --flat-playlist --print "%(title)s ::: %(url)s" "$url")
  for line in "${lines[@]}"; do
    video_titles+=("${line%% :::*}")
    video_urls+=("https://youtube.com/watch?v=${line##*::: }")
  done
}

parse_video() {
  title=$(yt-dlp --get-title "$url")
  video_titles=("$title")
  video_urls=("$url")
}

# --- INIT ---
autoplay=0
random_mode=0
declare -a play_history=()
play_index=0

# --- START ---
if [[ "$url" == *"playlist?"* ]]; then
  parse_playlist
  run_selector
else
  parse_video
  play_video 1
fi
