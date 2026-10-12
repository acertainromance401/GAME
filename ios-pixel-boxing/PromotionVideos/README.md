# RIVAL Sports Highlights Promotion

## Counter HQ Revision

- [1080p sharing copy](RIVAL-SportsHighlights-CounterHQ-24s-1080p.mp4)
- [4K master](RIVAL-SportsHighlights-CounterHQ-24s-4K.mp4)

Revised on 2026-10-12 after the user requested a slow-motion counter and direct
simulator capture to improve gameplay image quality. Both versions are 24 seconds,
60 fps, H.264 with stereo AAC at 48 kHz. The sharing copy is approximately 9.5 MB.
The original 30 fps edit is documented below as history; its output is not
retained in the current repository. The script can regenerate it with the
local-only input recordings and officially downloaded music.

All three combat cuts now use fresh, HUD-free 3840 x 2160 scene renders from the
current iOS simulator app rather than enlarged September recordings. The
5.5-8.5 second cut plays a real perfect dodge and counter at half speed. The
verified counter occurs at source frame 34 of the 60 fps capture. Its confirmation
caption and a synthesized editing impact sound start at approximately 6.63
seconds in the advertisement. A capture-only three-quarter camera and a closer
crop make the fighters' contact easier to see. This is staged gameplay footage
using the actual engine, not an ordinary touch-controlled screen recording.

All three supplied story recordings remain included. They are still original
2436 x 1126 recordings scaled into the master; the 4K output does not make those
shots native 4K. The counter close-up uses a 2560 x 1440 crop from native 4K,
which is enlarged in the master and downsampled in the 1080p copy.

The HQ mix uses Sports Highlights and the synthesized impact only, not the
original recordings' game/cutscene audio. The audio-only stage avoids gaps from
the source recording timestamps. Final checks confirmed 1,440 video frames and
24 seconds of decoded stereo PCM: 4,608,000 bytes at 48 kHz and 16 bits. Measured
audio level was approximately -15.9 LUFS with -5.2 dBFS true peak. The counter
sequence and confirmation caption were visually inspected. These checks are not
a complete human listening review or advertising-platform approval.

Reproduce the HQ edit from the workspace root:

```bash
bash scripts/render_sports_highlights_hq.sh
```

See the [capture record](../PromotionAssets/Captures/2026-10-12/README.md) for source
clips and the actual counter report. A DEBUG-only environment-gated exporter was
added to the iOS app for capture; it does not alter combat rules or normal/Release
gameplay and uses no persistent player progress. Capture and editing did not
release the app or submit an advertisement; later publication is recorded below.

## Reddit Publication

At the user's request, the Counter HQ 1080p video was published on 2026-10-12:

- [r/Indiegamedeveloper](https://www.reddit.com/r/Indiegamedeveloper/comments/1x3j448/)
- [r/gametrailers](https://www.reddit.com/r/gametrailers/comments/1x3j678/).

The Indiegamedeveloper post uses Promotion post flair and Developer user flair.

Both posts include the App Store link, developer identity, music credit, and AI
assistance disclosure. Their titles and bodies clearly identify the video as an
upcoming 1.2 preview, not content already available in the publicly listed 1.1
app. The current US price was rechecked as $1.99. Individual permalinks were
reloaded and video playback verified without a removal or approval-pending
notice in the authenticated session. Later moderation and public reach are not
guaranteed. No paid Reddit advertising was purchased.

A third post in r/Promotion was not submitted: its composer remained invalid
after switching to Markdown and re-entering the body. It is not counted as a
published post or saved draft.

### Earlier Community Distribution (2026-10-12)

The existing approximately 47.5-second trailer was also shared as native-video
posts in these communities, distinct from the two Counter HQ posts above:

- [r/KoreanGameDev](https://www.reddit.com/r/KoreanGameDev/comments/1x3g0aa/)
- [r/SoloDevelopment](https://www.reddit.com/r/SoloDevelopment/comments/1x3g25n/)
- [r/gamedevscreens](https://www.reddit.com/r/gamedevscreens/comments/1x3g3c4/)
- [r/IndieGame](https://www.reddit.com/r/IndieGame/comments/1x3gh47/)
- [r/SideProject](https://www.reddit.com/r/SideProject/comments/1x3gkyj/)
- [r/indiegamedevforum](https://www.reddit.com/r/indiegamedevforum/comments/1x3gmti/)

Individual permalinks and native playback were checked in the authenticated
session at publication. Later moderation and unauthenticated visibility were
not verified by this documentation update.

The r/IndieDev standalone post was automatically removed for its comment-karma
requirement and was not reposted. The moderator-permitted
[weekly megathread comment](https://www.reddit.com/r/IndieDev/comments/1wxruop/comment/pfapz42/)
persisted, but its native video stalled, so the existing playable trailer link
was retained. The [r/iosapps October App Shelf comment](https://www.reddit.com/r/iosapps/comments/1wvvq6p/comment/pfatopv/)
also persisted; its native playback was not confirmed at the final check.

A paid-game Trailer Tuesday draft for r/playmygame was saved, not scheduled or
submitted. It must not be counted as a live post. Existing bodies were edited
in place for a promotional tone without deleting or reposting; developer,
current paid-app price and AI-assistance disclosures were retained. Community
rules must be checked again before future publication. No Reddit Ads were bought.

## Instagram Reel

[Published reel](https://www.instagram.com/mardybum.studio/reel/DeXmQ7pPorZ/)
was shared on 2026-10-12 from mardybum.studio.

[Portrait source](RIVAL-Instagram-Counter-24s-9x16.mp4): 1080 x 1920, 24 seconds,
30 fps, H.264 video and AAC-LC music, consistent limited-range BT.709 color.

[Uploaded web-compatible copy](RIVAL-Instagram-Counter-24s-web.mp4): the same
picture with MP3 music inside MP4, because the embedded browser could not
decode the AAC source and initially reported no audio. This copy was detected
as Sound on before sharing.

[Cover](RIVAL-Instagram-Counter-cover.png): RIVAL / ONE MISS. ONE COUNTER.

The portrait edit starts with the half-speed counter, preserves both fighters
in the cropped gameplay shots, and retains the landscape story shots without
cutting off their characters. The final English caption starts "He missed. I
didn't." and "One opening can change the fight." At the user's request it omits
AI assistance, production details, and optional music credit. The internal music
license record is retained. The caption includes the App Store search instruction
and clearly identifies story scenes as an upcoming 1.2 preview. It was saved and
reload-verified on the existing reel without deleting or reposting. Tags are `#BoxingGame`,
`#IndieGame`, `#iOSGaming`, and `#MobileGaming`.

The reel was shared to the Instagram feed/profile with comments enabled and
like/view counts visible. Facebook cross-posting and scheduled posting were
off. No paid boost or additional ad funding was used. The uploader confirmed
"Your reel has been shared," and the published permalink and caption were
verified. Instagram's fetched video rendition was 720 x 1280 at 30 fps for
24 seconds; the separate HE-AAC music track was non-silent and approximately
24 seconds. Both passed FFmpeg decoding. The embedded browser still reported
a playback error, so browser playback itself was not verified. Human listening,
non-follower reach, recommendation eligibility, and algorithmic distribution
are not guaranteed by these checks.

An initial Boost reel inspection did not submit a new ad. The later, explicitly
authorized budget replacement is recorded below; it is not a second public reel.

Reproduce the portrait assets from the workspace root:

```bash
bash scripts/render_instagram_reel.sh
```

## Instagram Paid Promotion (2026-10-12)

The earlier promotion for reel `DdRrWvmPX8k` showed Not delivering, zero spend
and zero reach. After explicit approval it was deleted as an ad only; public
reels were preserved. The cause of non-delivery was not established.

A replacement was submitted once through "Run an ad that won't show on profile"
using the portrait video, a custom cover and English promotional copy with the
upcoming 1.2 disclosure. Destination: <https://apps.apple.com/app/id6799909429>.
Objective: website visits / Learn more, not app-install optimization. Audience:
US men aged 18–65, Advantage+ expansion off, no interests.

The approved budget was KRW 8,400 per day for two days, KRW 16,800 media budget
plus the displayed estimated KRW 1,000 VAT (estimated total KRW 17,800).
No additional funds were added. The final dialog said "Your ad is in review";
ad tools then showed one new Creating ad entry, zero spend and zero reach.
Approval, delivery, final tax/charges, visits and installs remain unverified.

## Repository Assets

Finished promotional videos, covers, capture clips, reports and rendering
scripts are tracked. Raw screen recordings and downloaded Mixkit MP3 files stay
local and are not redistributed in Git. Reproduction requires the original
recordings and downloading the music from its official source, under its own
license. The repository's MIT source license does not relicense that music.

## Original Output

The original 30 fps output is not retained. See the retained
[Counter HQ sharing copy](RIVAL-SportsHighlights-CounterHQ-24s-1080p.mp4) for
the later published revision. The following specifications describe the
original generation record, not a currently preserved file.

- Created on 2026-10-12 for use after the story release, at the user's request.
- 24 seconds of picture; container duration is approximately 24.02 seconds.
- Landscape 1920 x 1080, 30 fps, H.264 video and stereo AAC audio at 48 kHz.
- Approximately 9.05 MB; fast-start metadata for online playback.
- English promotional captions and App Store search/download closing text.
- The original edit involved no upload, advertising purchase, or iOS app changes.

## Cut List

| Time | Scene | Caption |
| --- | --- | --- |
| 0.0-3.0 | Blue outfit fighting exchange | ONE RING. YOUR FIGHT. |
| 3.0-5.5 | Pressure opponent introduction | MEET YOUR RIVALS. |
| 5.5-8.5 | Defensive movement in a fighting exchange | MAKE THEM MISS. |
| 8.5-11.0 | Coach's guidance | FIND YOUR OWN WAY. |
| 11.0-14.0 | Close-range fighting exchange | MAKE IT COUNT. |
| 14.0-16.5 | Young boxer's story scene | MORE THAN A FIGHT. |
| 16.5-19.5 | Champion congratulations | EARN YOUR MOMENT. |
| 19.5-24.0 | Champion close-up with download closing text | RIVAL / BOXING |

The edit uses both September gameplay recordings and all three supplied October
story recordings. Raw sideways gameplay is corrected and cropped toward the
fighters. Story shots preserve the original dialogue; the closing shot is
reframed to leave room for the download message. The footage represents different
recording dates, not a newly captured, single-version gameplay session.

## Audio

Music: Sports Highlights by Ahjay Stelino, downloaded from Mixkit.
See the [music usage record](../PromotionAssets/Audio/README.md) for the source
and license restrictions. This license permits online video advertising but not
in-game background music.

Original game audio is retained, with lower levels in story scenes. Music fades
in for 0.18 seconds and out during the final 1.2 seconds. The finished mix measured
approximately -15.9 LUFS integrated loudness and -5.0 dBFS true peak.

## Reproduce

From the workspace root:

```bash
bash scripts/render_sports_highlights_promo.sh
```

Requires macOS AppKit, an installed Swift toolchain, FFmpeg/ffprobe, and the
original local recordings and downloaded music. The command replaces this
output MP4 but does not modify its sources. Temporary clip and title files are
removed on exit.

The video passed full FFmpeg decode, and representative frames from all eight
scenes were inspected for orientation, framing, and readable titles. This is not
an advertising-platform approval, public upload, or full human listening review.
