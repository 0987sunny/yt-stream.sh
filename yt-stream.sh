#!/usr/bin/env zsh
# v 1.0
set -euo pipefail

# ❌ Prevent execution as root
if [[ $EUID -eq 0 ]]; then
  print -P "%F{red}✘ Never run this as root. Use as regular user only.%f" >&2
  exit 1
fi

# 📥 Parse CLI args
DRM_CONNECTOR=""
URL=""

for arg in "$@"; do
  if [[ "$arg" == --drm-connector=* ]]; then
    DRM_CONNECTOR="${arg#--drm-connector=}"
  else
    URL="$arg"
  fi
done

if [[ -z "$URL" ]]; then
  print -P "%F{red}Usage:%f yt-stream [--drm-connector=HDMI-A-1] \"<YouTube Video or Playlist URL>\""
  exit 1
fi

# 🎯 Choose output method: TTY or GUI
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
  MPV_VO="gpu"
else
  MPV_VO="drm"
fi

# 🎛 MPV configuration (RAM-only buffer, 1080p max)
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

# ➕ Add connector override if set AND using drm
if [[ "$MPV_VO" == "drm" && -n "$DRM_CONNECTOR" ]]; then
  MPV_OPTS+=("--drm-connector=$DRM_CONNECTOR")
fi

# 🔍 Detect playlist vs single video
if yt-dlp --flat-playlist -J "$URL" 2>/dev/null | jq -e '.entries? | length > 0' >/dev/null; then
  # 🎞️ Playlist detected
  while true; do
    print -P "%F{yellow}🎞  Playlist detected. Loading video list...%f"
    SELECTION=$(yt-dlp --flat-playlist -J "$URL" \
      | jq -r '.entries[] | "\(.title) ::: \(.id)"' \
      | sed '$a❌ Exit ::: exit' \
      | fzf --prompt="🎬 Choose video: " --exit-0)

    # Exit if Esc or nothing selected
    [[ -z "$SELECTION" ]] && break

    TITLE="${SELECTION%% ::: *}"
    ID="${SELECTION##*::: }"

    [[ "$ID" == "exit" ]] && break

    VIDEO_URL="https://youtube.com/watch?v=$ID"
    mpv "${MPV_OPTS[@]}" --input-conf=<(echo "ESC quit") "$VIDEO_URL" || true
  done

else
  # 🎥 Single video
  print -P "%F{yellow}🎥 Video detected. Starting stream...%f"
  mpv "${MPV_OPTS[@]}" --input-conf=<(echo "ESC quit") "$URL"
fi
