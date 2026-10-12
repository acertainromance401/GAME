#!/bin/bash
set -euo pipefail

workspace_root=$(cd "$(dirname "$0")/.." && pwd)
output_directory="$workspace_root/PromotionVideos"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/rival-instagram.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$output_directory"
title_directory="$temporary_directory/titles"
xcrun swift "$workspace_root/scripts/render_instagram_titles.swift" "$title_directory"

render_clip() {
    local number="$1" source="$2" start="$3" duration="$4"
    local framing="$5" caption="$6" speed="${7:-1}"
    ffmpeg -hide_banner -loglevel error -y \
        -ss "$start" -i "$workspace_root/$source" \
        -loop 1 -framerate 30 -i "$title_directory/$caption" \
        -filter_complex \
        "[0:v]$framing,setpts=$speed*(PTS-STARTPTS),fps=30,settb=1/30,setpts=N/(30*TB),setsar=1[scene];[scene][1:v]overlay=0:0:shortest=1[composite];[composite]scale=in_range=auto:out_range=tv,format=yuv420p,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709[video]" \
        -map '[video]' -an -t "$duration" \
        -c:v libx264 -preset fast -crf 17 -pix_fmt yuv420p \
        -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
        -r 30 -fps_mode cfr -video_track_timescale 90000 \
        "$temporary_directory/clip-$number.mp4"
    printf "file '%s/clip-%s.mp4'\n" "$temporary_directory" "$number" >> "$temporary_directory/clips.txt"
    printf 'Rendered Instagram scene %s\n' "$number"
}

capture_path='PromotionAssets/Captures/2026-10-12'
fight_framing='crop=1216:2160:1312:0,scale=1080:1920:flags=lanczos'
story_framing='crop=iw:ih-70:0:70,scale=1080:-2:flags=lanczos,pad=1080:1920:0:(oh-ih)/2:black'

render_clip 01 "$capture_path/counter-4k60.mp4" 0 3 "$fight_framing" 01-hook.png 2
render_clip 02 'ScreenRecording_10-12-2026 03-36-42_1.MOV' 2.8 2.5 "$story_framing" 02-rivals.png
render_clip 03 "$capture_path/exchange-4k60.mp4" 0.2 3 "$fight_framing" 03-exchange.png
render_clip 04 'ScreenRecording_10-12-2026 03-36-42_1.MOV' 7.9 2.5 "$story_framing" 04-coach.png
render_clip 05 "$capture_path/exchange-4k60.mp4" 3 3 "$fight_framing" 05-counter.png
render_clip 06 'ScreenRecording_10-12-2026 4.MOV' 3.5 2.5 "$story_framing" 06-story.png
render_clip 07 'ScreenRecording_10-12-2026 5.MOV' 1.9 3 "$story_framing" 07-champion.png
render_clip 08 'ScreenRecording_10-12-2026 5.MOV' 1.9 4.5 "$story_framing" 08-end.png

ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 \
    -i "$temporary_directory/clips.txt" -c copy "$temporary_directory/picture.mp4"

ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i 'anoisesrc=color=brown:sample_rate=48000:duration=0.16:amplitude=0.45:seed=34' \
    -af 'highpass=f=80,lowpass=f=1500,afade=t=in:d=0.008,afade=t=out:st=0.025:d=0.135' \
    "$temporary_directory/impact.wav"
bash "$workspace_root/scripts/mix_promotion_audio.sh" \
    "$temporary_directory/impact.wav" "$temporary_directory/music.wav" 1133

ffmpeg -hide_banner -loglevel error -y \
    -i "$temporary_directory/picture.mp4" -i "$temporary_directory/music.wav" \
    -map 0:v -map 1:a -t 24 -c:v copy -c:a aac -b:a 256k -ar 48000 -ac 2 \
    -movflags +faststart -metadata title='RIVAL - He missed. I did not. - Update Preview' \
    "$output_directory/RIVAL-Instagram-Counter-24s-9x16.mp4"

ffmpeg -hide_banner -loglevel error -y \
    -i "$output_directory/RIVAL-Instagram-Counter-24s-9x16.mp4" \
    -map 0:v -map 0:a -c:v copy -c:a libmp3lame -b:a 192k -ar 44100 -ac 2 \
    -movflags +faststart "$output_directory/RIVAL-Instagram-Counter-24s-web.mp4"

ffmpeg -hide_banner -loglevel error -y \
    -ss 0.566667 -i "$workspace_root/$capture_path/counter-4k60.mp4" \
    -i "$title_directory/cover-overlay.png" \
    -filter_complex '[0:v]scale=1080:608:flags=lanczos,pad=1080:1920:0:820:black[scene];[scene][1:v]overlay=0:0[cover]' \
    -map '[cover]' -frames:v 1 -update 1 \
    "$output_directory/RIVAL-Instagram-Counter-cover.png"

printf 'Finished: portrait reel and cover in %s\n' "$output_directory"