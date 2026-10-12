#!/bin/bash
set -euo pipefail

workspace_root=$(cd "$(dirname "$0")/.." && pwd)
impact_file="$1"
output_file="$2"
impact_delay="${3:-6633}"

ffmpeg -hide_banner -loglevel error -y \
    -i "$workspace_root/PromotionAssets/Audio/mixkit-sports-highlights-51.mp3" \
    -i "$impact_file" \
    -filter_complex \
    "[0:a]atrim=duration=24,asetpts=PTS-STARTPTS,aresample=48000,volume=0.50,afade=t=in:d=0.18,afade=t=out:st=22.8:d=1.2[music];[1:a]volume=0.45,adelay=$impact_delay:all=1[impact];[music][impact]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=9,aresample=48000[audio]" \
    -map '[audio]' -t 24 -c:a pcm_s16le -ar 48000 -ac 2 "$output_file"