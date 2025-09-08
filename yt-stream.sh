#!/usr/bin/env zsh
set -euo pipefail

# ❌ Deny root
if [[ $EUID -eq 0 ]]; then
  print -P "%F{red}✘ Never run this as root. Use as regular user only.%f" >&2
  exit 1
fi

# 🎨 Header
print -P "%F{208}▶ YT-STREAM: Secure, Buffered, Ephemeral Playback%f\n"

# 📦 Dependencies check (optional, skip if you handle that elsewhere)
for cmd in mpv yt-dlp fzf jq; do
  command -v $cmd >/dev/null || {
    print -P "%F{red}✘ Missing dependency: $cmd%f" >&2
    exit 1
  }
done

# 📥 URL from arg
if [[ $# -ne 1 ]]; then
  print -P "%F{red}Usage:%f yt-stream \"<YouTube Video or Playlist URL>\""
  exit 1
fi

URL="$1"

# 🎯 Set VO based on environment
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
  MPV_VO="gpu"
else
  MPV_VO="drm"
fi

# 📡 Common mpv args
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

# 🔍 Detect if it's a playlist
if yt-dlp --flat-playlist -J "$URL" 2>/dev/null | jq -e '.entries? | length > 0' >/dev/null; then
  # 📃 Playlist detected
  while true; do
    print -P "%F{yellow}🎞  Playlist detected. Loading videos...%f"
    SELECTION=$(yt-dlp --flat-playlist -J "$URL" \
      | jq -r '.entries[] | "\(.title) |\(.id)"' \
      | awk '{print NR " | " $0}' \
      | sed '$a0 | ❌ Exit' \
      | fzf --prompt="🎬 Choose video: ")

    [[ -z "$SELECTION" ]] && continue

    CHOICE_ID=$(cut -d'|' -f2 <<< "$SELECTION" | xargs)
    [[ "$CHOICE_ID" == "❌ Exit" ]] && break

    VIDEO_URL="https://youtube.com/watch?v=$CHOICE_ID"
    mpv "${MPV_OPTS[@]}" "$VIDEO_URL"
  done

else
  # 🎥 Single video
  print -P "%F{yellow}🎥 Video detected. Starting stream...%f"
  mpv "${MPV_OPTS[@]}" "$URL"
fi
