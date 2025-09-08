#!/usr/bin/env zsh

set -euo pipefail

# Dependencies
command -v mpv >/dev/null || { echo "mpv not found"; exit 1; }
command -v yt-dlp >/dev/null || { echo "yt-dlp not found"; exit 1; }
command -v fzf >/dev/null || { echo "fzf not found"; exit 1; }

# Block root execution
[[ $EUID -eq 0 ]] && exit 1

# Check argument
[[ $# -eq 0 ]] && { echo "Usage: yt-stream 'https://youtube.com/...'"; exit 1; }

url="$1"
autoplay=0
random=0
history=()
history_idx=-1

# Detect TTY or GUI terminal
use_gpu() {
  [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && return 0
  return 1
}

mpv_common_flags=(
  --no-config
  --ytdl-format="bestvideo[height<=1080]+bestaudio/best[height<=1080]"
  --cache=yes
  --cache-secs=300
  --demuxer-max-bytes=400MiB
  --demuxer-max-back-bytes=100MiB
  --no-terminal
  --force-window=no
  --keep-open=no
  --really-quiet
)

[[ $(use_gpu) == 0 ]] && vo="gpu" || vo="drm"

# Play one video
play_video() {
  local vid_url="$1"
  history+=("$vid_url")
  history_idx=$(( ${#history[@]} - 1 ))

  mpv "${mpv_common_flags[@]}" --vo=$vo --input-conf=/dev/stdin "$vid_url" <<-EOF
    ESC quit
    CTRL+RIGHT run "${0:A}" --next "$url"
    CTRL+LEFT run "${0:A}" --prev "$url"
EOF
}

# Load playlist
load_playlist() {
  yt-dlp --flat-playlist --print "%(title)s ::: %(url)s" "$url"
}

# Parse playlist entries
pick_video_from_playlist() {
  while true; do
    local status="Autoplay: $([[ $autoplay -eq 1 ]] && echo ON || echo OFF) | Random: $([[ $random -eq 1 ]] && echo ON || echo OFF)"
    local entries=(
      "🔁 Toggle Autoplay"
      "🔀 Toggle Random"
      "❌ Exit"
    )

    local videos=("${(@f)$(load_playlist)}")
    local display_videos=("${videos[@]}" "${entries[@]}")

    local choice="$(printf "%s\n" "${entries[@]}" "${videos[@]}" | fzf --reverse --prompt="Choose video: " --header-lines=3 --header="$status" --bind "ctrl-a:toggle-autoplay,ctrl-r:toggle-random")"

    case "$choice" in
      "❌ Exit") exit 0 ;;
      "🔁 Toggle Autoplay") autoplay=$((1 - autoplay)) ;;
      "🔀 Toggle Random") random=$((1 - random)) ;;
      "") exit 0 ;;
      *)
        if [[ "$choice" =~ ::: ]]; then
          local selected_url="https://youtube.com/watch?$(awk -F' ::: ' '{print $2}' <<< "$choice")"
          play_and_maybe_loop "$selected_url" "${videos[@]}"
        fi
        ;;
    esac
  done
}

# Next/Prev/random playback handler
play_and_maybe_loop() {
  local current="$1"
  shift
  local list=("$@")

  while true; do
    play_video "$current"

    [[ $autoplay -eq 0 ]] && break

    if [[ $random -eq 1 ]]; then
      current="https://youtube.com/watch?$(printf "%s\n" "${list[@]}" | shuf -n1 | awk -F' ::: ' '{print $2}')"
    else
      local i; for i in {1..${#list[@]}}; do
        if [[ "$current" == *"${list[i]}"* ]]; then
          current="https://youtube.com/watch?$(awk -F' ::: ' '{print $2}' <<< "${list[i+1]}")"
          break
        fi
      done
    fi
  done
}

# History-based prev/next (for hotkeys)
if [[ "${1:-}" == "--next" || "${1:-}" == "--prev" ]]; then
  shift
  [[ -z "${2:-}" ]] && exit 0
  list=("${(@f)$(load_playlist)}")
  current_idx=$history_idx

  if [[ "$1" == "--next" ]]; then
    if [[ $random -eq 1 ]]; then
      next_url="https://youtube.com/watch?$(printf "%s\n" "${list[@]}" | shuf -n1 | awk -F' ::: ' '{print $2}')"
    else
      next_idx=$(( current_idx + 1 ))
      [[ $next_idx -ge ${#list[@]} ]] && next_idx=0
      next_url="https://youtube.com/watch?$(awk -F' ::: ' '{print $2}' <<< "${list[next_idx]}")"
    fi
    play_video "$next_url"
  else
    prev_idx=$(( current_idx - 1 ))
    [[ $prev_idx -lt 0 ]] && prev_idx=0
    play_video "${history[$prev_idx]}"
  fi
  exit 0
fi

# Entry point
if [[ "$url" == *"list="* ]]; then
  pick_video_from_playlist
else
  play_video "$url"
fi
