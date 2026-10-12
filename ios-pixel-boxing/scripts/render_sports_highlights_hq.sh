#!/bin/bash
set -euo pipefail

workspace_root=$(cd "$(dirname "$0")/.." && pwd)
output_directory="$workspace_root/PromotionVideos"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/rival-hq-promo.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$output_directory"
title_directory="$temporary_directory/titles"
xcrun swift "$workspace_root/scripts/render_promotion_titles.swift" "$title_directory" 2

render_clip() {
    local number="$1" source="$2" start="$3" duration="$4"
    local framing="$5" caption="$6" sound_level="$7" speed="${8:-1}"
    local audio_tempo
    audio_tempo=$(awk -v speed="$speed" 'BEGIN {print 1/speed}')
    ffmpeg -hide_banner -loglevel error -y \
        -ss "$start" -i "$workspace_root/$source" \
        -loop 1 -framerate 60 -i "$title_directory/$caption" \
        -filter_complex \
        "[0:v]$framing,setpts=$speed*(PTS-STARTPTS),fps=60,settb=1/60,setsar=1,format=yuv420p[scene];[scene][1:v]overlay=0:0:shortest=1[video];[0:a]aresample=48000,asetpts=PTS-STARTPTS,atempo=$audio_tempo,highpass=f=70,volume=$sound_level,afade=t=in:d=0.035,afade=t=out:st=$(awk -v duration="$duration" 'BEGIN {print duration-0.05}'):d=0.05[audio]" \
        -map '[video]' -map '[audio]' -t "$duration" \
        -c:v libx264 -preset veryfast -crf 16 -pix_fmt yuv420p \
        -r 60 -fps_mode cfr -video_track_timescale 60000 \
        -c:a aac -b:a 192k -ar 48000 -ac 2 \
        "$temporary_directory/clip-$number.mp4"
    printf "file '%s/clip-%s.mp4'\n" "$temporary_directory" "$number" >> "$temporary_directory/clips.txt"
    printf 'Rendered HQ scene %s\n' "$number"
}

capture_path='PromotionAssets/Captures/2026-10-12'
fight_framing='scale=3840:2160:flags=lanczos'
counter_framing='crop=2560:1440:640:360,scale=3840:2160:flags=lanczos'
story_framing='scale=3840:-2:flags=lanczos,pad=3840:2160:0:332:black'
ending_framing='crop=1100:730:540:125,scale=2560:1700:flags=lanczos,pad=3840:2160:1280:300:black'

render_clip 01 "$capture_path/exchange-4k60.mp4" 0.2 3 "$fight_framing" 01-hook.png 0
render_clip 02 'ScreenRecording_10-12-2026 03-36-42_1.MOV' 2.8 2.5 "$story_framing" 02-rival.png 0.25
render_clip 03 "$capture_path/counter-4k60.mp4" 0 3 "$counter_framing" 03-dodge.png 0 2
render_clip 04 'ScreenRecording_10-12-2026 03-36-42_1.MOV' 7.9 2.5 "$story_framing" 04-coach.png 0.25
render_clip 05 "$capture_path/exchange-4k60.mp4" 3 3 "$fight_framing" 05-counter.png 0
render_clip 06 'ScreenRecording_10-12-2026 4.MOV' 3.5 2.5 "$story_framing" 06-story.png 0.25
render_clip 07 'ScreenRecording_10-12-2026 5.MOV' 1.9 3 "$story_framing" 07-champion.png 0.35
render_clip 08 'ScreenRecording_10-12-2026 5.MOV' 1.9 4.5 "$ending_framing" 08-end.png 0.25

ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 \
    -i "$temporary_directory/clips.txt" -c copy "$temporary_directory/picture.mp4"

ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i 'anoisesrc=color=brown:sample_rate=48000:duration=0.16:amplitude=0.45:seed=34' \
    -af 'highpass=f=80,lowpass=f=1500,afade=t=in:d=0.008,afade=t=out:st=0.025:d=0.135' \
    "$temporary_directory/impact.wav"

ffmpeg -hide_banner -loglevel error -y \
    -i "$temporary_directory/picture.mp4" \
    -loop 1 -framerate 60 -i "$title_directory/09-perfect.png" \
    -filter_complex "[0:v]fps=60,setpts=N/(60*TB)[picture];[picture][1:v]overlay=0:0:enable='between(t,6.633333,8.15)'[video]" \
    -map '[video]' -an -t 24 \
    -c:v libx264 -preset fast -crf 16 -pix_fmt yuv420p \
    -r 60 -fps_mode cfr -video_track_timescale 60000 \
    "$temporary_directory/titled-picture.mp4"

bash "$workspace_root/scripts/mix_promotion_audio.sh" \
    "$temporary_directory/impact.wav" "$temporary_directory/music.wav"

ffmpeg -hide_banner -loglevel error -y \
    -i "$temporary_directory/titled-picture.mp4" -i "$temporary_directory/music.wav" \
    -map 0:v -map 1:a -t 24 -c:v copy \
    -c:a aac -b:a 256k -ar 48000 -ac 2 -movflags +faststart \
    -metadata title='RIVAL - Sports Highlights - Counter HQ' \
    "$output_directory/RIVAL-SportsHighlights-CounterHQ-24s-4K.mp4"

ffmpeg -hide_banner -loglevel error -y \
    -i "$output_directory/RIVAL-SportsHighlights-CounterHQ-24s-4K.mp4" \
    -vf 'scale=1920:1080:flags=lanczos' -c:v libx264 -preset fast -crf 17 \
    -pix_fmt yuv420p -r 60 -fps_mode cfr -c:a copy -movflags +faststart \
    "$output_directory/RIVAL-SportsHighlights-CounterHQ-24s-1080p.mp4"

printf 'Finished: CounterHQ 4K master and 1080p sharing copy\n'