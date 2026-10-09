#!/bin/bash
set -euo pipefail
sessionbar_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$sessionbar_root"
command -v ffmpeg >/dev/null || { echo 'ffmpeg is required to render demo videos' >&2; exit 1; }
python3 scripts/prepare-demo.py
./scripts/swift.sh build --package-path .build/demo-preview
sessionbar_renderer="$sessionbar_root/.build/demo-preview/.build/debug/Preview"
mkdir -p Assets/demo
for sessionbar_language in ko en; do
    sessionbar_frames="$sessionbar_root/.build/demo-frames/$sessionbar_language"
    mkdir -p "$sessionbar_frames"
    "$sessionbar_renderer" "$sessionbar_frames" "$sessionbar_language"
    if [[ "$sessionbar_language" == ko ]]; then sessionbar_suffix=한국어; else sessionbar_suffix=영문; fi
    ffmpeg -hide_banner -loglevel error -y -framerate 12 -i "$sessionbar_frames/%04d.png" \
        -vf 'scale=1200:900' -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart \
        "Assets/demo/000_사용흐름_$sessionbar_suffix.mp4"
    ffmpeg -hide_banner -loglevel error -y -framerate 12 -i "$sessionbar_frames/%04d.png" \
        -filter_complex '[0:v]fps=6,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' \
        "Assets/demo/000_사용흐름_$sessionbar_suffix.gif"
    cp "$sessionbar_frames/0000.png" "Assets/demo/000_사용흐름_$sessionbar_suffix.png"
done
printf 'Demo videos: Assets/demo/\n'
