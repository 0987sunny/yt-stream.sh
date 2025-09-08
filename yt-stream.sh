#!/usr/bin/env zsh
set -euo pipefail

# ❌ Prevent root execution
if [[ $EUID -eq 0 ]]; then
  print -P "%F{red}✘ Never run this as root. Use as regular user only.%f" >&2
  exit 1
fi

# 🎨 Minimal header
print -P "%F{208}▶ YT-STREAM: Secure, Buffered, Ephemeral Playback%f\n"

# 📥 Require exactly one argument (URL)
if [[ $# -ne 1 ]]; then
  print -P "%F{red}Usage:%f yt-stream \"<YouTube Video or Playlist URL>\""
  exit 1
fi

URL="$1"

# 🎯 Choose --vo based on environment
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
  MPV_VO="gpu"
else
  MPV_VO="drm"
fi

# 🎛 Common mpv options
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

# 🔍 Detect playlist vs single video
if yt-dlp --flat-playlist -J "$URL" 2>/dev/null | jq -e '.entries? | length > 0' >/dev/null; then
  # 🎞️ Playlist detected
  while true; do
    print -P "%F{yellow}🎞  Playlist detected. Loading video list...%f"
    SELECTION=$(yt-dlp --flat-playlist -J "$URL" \
      | jq -r '.entries[] | "\(.title) ::: \(.id)"' \
      | sed '$a❌ Exit ::: exit' \
      | fzf --prompt="🎬 Choose video: ")

    [[ -z "$SELECTION" ]] && continue

    TITLE="${SELECTION%% ::: *}"
    ID="${SELECTION##*::: }"

    [[ "$ID" == "exit" ]] && break

    VIDEO_URL="https://youtube.com/watch?v=$ID"
    mpv "${MPV_OPTS[@]}" "$VIDEO_URL"
  done

else
  # 🎥 Single video
  print -P "%F{yellow}🎥 Video detected. Starting stream...%f"
  mpv "${MPV_OPTS[@]}" "$URL"
fi
