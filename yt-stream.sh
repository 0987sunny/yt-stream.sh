#!/usr/bin/env zsh
set -euo pipefail

# ❌ Prevent execution as root
if [[ $EUID -eq 0 ]]; then
  print -P "%F{red}✘ Never run this as root. Use as regular user only.%f" >&2
  exit 1
fi

# 📥 Require a single argument
if [[ $# -ne 1 ]]; then
  print -P "%F{red}Usage:%f yt-stream \"<YouTube Video or Playlist URL>\""
  exit 1
fi

URL="$1"

# 🔁 Playback state
typeset -g autoplay=off
typeset -g random=off
typeset -g -a played_history
typeset -g last_index=0

# 🎯 Output method
MPV_VO="drm"
[[ -n ${WAYLAND_DISPLAY:-} || -n ${DISPLAY:-} ]] && MPV_VO="gpu"

# 🎛 MPV opts
MPV_OPTS=(
  "--vo=$MPV_VO"
  --ytdl-format="bestvideo[height<=1080]+bestaudio/best"
  --no-config
  --no-resume-playback
  --save-position-on-quit=no
  --cache=yes
  --cache-on-disk=no
  --cache-secs=300
  --demuxer-max-bytes=400MiB
  --demuxer-readahead-secs=120
  --ytdl-raw-options=no-cache-dir=
  --force-window=no
)

# 📋 Load playlist entries
load_playlist() {
  yt-dlp --flat-playlist -J "$URL" 2>/dev/null | \
    jq -r '.entries[] | "\(.title) ::: \(.id)"'
}

# 🔢 Autoplay logic
next_index() {
  if [[ "$random" == "on" ]]; then
    echo $((RANDOM % ${#video_ids[@]}))
  else
    echo $(((last_index + 1) % ${#video_ids[@]}))
  fi
}

prev_index() {
  if [[ "$random" == "on" ]]; then
    echo $((RANDOM % ${#video_ids[@]}))
  else
    echo $(((last_index - 1 + ${#video_ids[@]}) % ${#video_ids[@]}))
  fi
}

# ▶️ Play a video by index
play_video_by_index() {
  local index="$1"
  last_index=$index
  played_history+=($index)
  local id="${video_ids[$index]}"
  local url="https://youtube.com/watch?v=$id"
  mpv "${MPV_OPTS[@]}" "$url" \
    --input-conf=/dev/null \
    --input-ipc-server=/tmp/yt-mpv-sock.$$ \
    --idle=no \
    --force-window=immediate \
    --term-playing-msg="Press Ctrl+Right/Left or Esc" \
    --script-opts="osc=no" || return

  while true; do
    sleep 1
    [[ ! -S /tmp/yt-mpv-sock.$$ ]] && break
  done
}

# 🧠 Menu loop
menu_loop() {
  local entries status_header selection chosen title id
  local playlist_json="$(yt-dlp --flat-playlist -J "$URL" 2>/dev/null)"
  local total_videos=$(jq '.entries | length' <<<"$playlist_json")

  mapfile -t video_ids < <(jq -r '.entries[].id' <<<"$playlist_json")
  mapfile -t video_titles < <(jq -r '.entries[].title' <<<"$playlist_json")

  while true; do
    status_header=$'%F{green}Playlist contains:%f %F{white}'$#video_ids' videos%f\n'
    status_header+=$'%F{magenta}Autoplay:%f %F{white}'$autoplay$'%f\n'
    status_header+=$'%F{blue}Random:%f %F{white}'$random$'%f\n'

    entries=(
      "❌ Exit ::: exit"
      "🔀 Random ::: toggle-random"
      "🔁 Autoplay ::: toggle-autoplay"
    )

    for i in {1..$#video_titles}; do
      entries+=("${video_titles[$i]} ::: ${video_ids[$i-1]}")
    done

    selection=$(print -l -- $entries | \
      fzf --ansi --no-sort --no-multi --exit-0 \
          --expect=ctrl-r,ctrl-a,esc \
          --header="$status_header" \
          --prompt="🎬 Choose video: ")

    chosen=$(sed -n '$p' <<<"$selection")
    key=$(head -n1 <<<"$selection")

    case "$key" in
      ctrl-a) autoplay=$([[ "$autoplay" == "on" ]] && echo "off" || echo "on"); continue ;;
      ctrl-r) random=$([[ "$random" == "on" ]] && echo "off" || echo "on"); continue ;;
      esc|"❌ Exit ::: exit"|exit|"") break ;;
    esac

    title="${chosen%% ::: *}"
    id="${chosen##*::: }"

    case "$id" in
      toggle-random) random=$([[ "$random" == "on" ]] && echo "off" || echo "on") ;;
      toggle-autoplay) autoplay=$([[ "$autoplay" == "on" ]] && echo "off" || echo "on") ;;
      exit|"") break ;;
      *)
        index=-1
        for i in {1..$#video_ids}; do
          [[ "${video_ids[$i]}" == "$id" ]] && index=$((i - 1)) && break
        done
        [[ $index -ge 0 ]] && play_video_by_index "$index"

        while [[ "$autoplay" == "on" ]]; do
          index=$(next_index)
          play_video_by_index "$index"
        done
      ;;
    esac
  done
}

# 🔍 Decide: single video or playlist
if yt-dlp --flat-playlist -J "$URL" 2>/dev/null | jq -e '.entries? | length > 0' >/dev/null; then
  menu_loop
else
  print -P "%F{yellow}🎥 Video detected. Starting stream...%f"
  mpv "${MPV_OPTS[@]}" "$URL"
fi
