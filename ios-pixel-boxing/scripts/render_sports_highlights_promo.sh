#!/bin/bash
set -euo pipefail

workspace_root=$(cd "$(dirname "$0")/.." && pwd)
output_directory="$workspace_root/PromotionVideos"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/rival-promo.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$output_directory"

title_directory="$temporary_directory/titles"
xcrun swift "$workspace_root/scripts/render_promotion_titles.swift" "$title_directory"

render_clip() {
    local number="$1"
    local source="$2"
    local start="$3"
    local duration="$4"
    local framing="$5"
    local caption="$6"
    local sound_level="$7"
    ffmpeg -hide_banner -loglevel error -y \
        -ss "$start" -i "$workspace_root/$source" \
        -loop 1 -framerate 30 -i "$title_directory/$caption" \
        -filter_complex \
        "[0:v]$framing,fps=30,setsar=1,format=yuv420p[scene];[scene][1:v]overlay=0:0:shortest=1[video];[0:a]aresample=48000,asetpts=PTS-STARTPTS,highpass=f=70,volume=$sound_level,afade=t=in:d=0.035,afade=t=out:st=$(awk -v duration="$duration" 'BEGIN {print duration-0.05}'):d=0.05[audio]" \
        -map '[video]' -map '[audio]' -t "$duration" \
        -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
        -c:a aac -b:a 192k -ar 48000 -ac 2 \
        "$temporary_directory/clip-$number.mp4"
    printf "file '%s/clip-%s.mp4'\n" "$temporary_directory" "$number" >> "$temporary_directory/clips.txt"
    printf 'Rendered scene %s\n' "$number"
}

fight_framing='transpose=2,crop=1250:704:700:170,scale=1920:1080'
story_framing='scale=1920:-2,pad=1920:1080:0:166:black'
ending_framing='crop=1100:730:540:125,scale=1280:850,pad=1920:1080:640:150:black'

render_clip 01 'ScreenRecording_09-14-2026 17-42-13_1.MP4' 18 3 "$fight_framing" 01-hook.png 0.75
render_clip 02 'ScreenRecording_10-12-2026 03-36-42_1.MOV' 2.8 2.5 "$story_framing" 02-rival.png 0.25
render_clip 03 'ScreenRecording_09-14-2026 17-46-41_1.MP4' 21.4 3 "$fight_framing" 03-dodge.png 0.75
render_clip 04 'ScreenRecording_10-12-2026 03-36-42_1.MOV' 7.9 2.5 "$story_framing" 04-coach.png 0.25
render_clip 05 'ScreenRecording_09-14-2026 17-46-41_1.MP4' 17.5 3 "$fight_framing" 05-counter.png 0.75
render_clip 06 'ScreenRecording_10-12-2026 4.MOV' 3.5 2.5 "$story_framing" 06-story.png 0.25
render_clip 07 'ScreenRecording_10-12-2026 5.MOV' 1.9 3 "$story_framing" 07-champion.png 0.35
render_clip 08 'ScreenRecording_10-12-2026 5.MOV' 1.9 4.5 "$ending_framing" 08-end.png 0.25

ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 \
    -i "$temporary_directory/clips.txt" -c copy "$temporary_directory/picture.mp4"

ffmpeg -hide_banner -loglevel error -y \
    -i "$temporary_directory/picture.mp4" \
    -i "$workspace_root/PromotionAssets/Audio/mixkit-sports-highlights-51.mp3" \
    -filter_complex \
    '[1:a]atrim=duration=24,asetpts=PTS-STARTPTS,aresample=48000,volume=0.50,afade=t=in:d=0.18,afade=t=out:st=22.8:d=1.2[music];[0:a][music]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=9,aresample=48000[audio]' \
    -map 0:v -map '[audio]' -t 24 \
    -c:v copy -c:a aac -b:a 256k -ar 48000 -ac 2 \
    -movflags +faststart \
    -metadata title='RIVAL - Sports Highlights - Story and Combat' \
    "$output_directory/RIVAL-SportsHighlights-24s-1080p.mp4"

printf 'Finished: %s/RIVAL-SportsHighlights-24s-1080p.mp4\n' "$output_directory"