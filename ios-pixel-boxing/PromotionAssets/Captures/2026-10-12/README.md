# Current Combat Capture

Captured on 2026-10-12 from a newly built Debug RIVAL simulator app.

## Assets

- [counter-4k60.mp4](counter-4k60.mp4): 8 seconds, 480 frames, 3840 x 2160 at 60 fps.
- [exchange-4k60.mp4](exchange-4k60.mp4): 6 seconds, 360 frames, 3840 x 2160 at 60 fps.
- [capture.json](capture.json): actual engine counter count and impact frame.

The counter report recorded one perfect counter at frame 34, approximately
0.567 seconds into the source. The enemy cross starts at frame 0, the player
ducks at frame 3, and the player's legal jab starts at frame 11 after the engine
confirms a perfect dodge. Damage and contact are determined by normal combat
rules; no hit result or counter grade is forced.

## Method

The environment-gated DEBUG exporter in
[PixelBoxingApp.swift](../../../PixelBoxingIOS/PixelBoxingApp.swift) creates a fresh
GameController with persistence and feedback disabled. It advances the current
SceneKit scene and combat engine at fixed 1/60-second intervals, then uses
SCNRenderer to save native 4K PNG frames with multisampling. The final source
clips were encoded from those frames. They contain silent audio tracks for
editing compatibility, not recorded game sound.

The isolated simulator is RIVAL Promo Capture, iPhone 17 Pro Max, iOS 26.1,
device ID AF440925-EC31-42B7-A31C-F499DC96A29B. Real player saves, story progression,
equipment, and ranking data are not loaded or written by the exporter.

For reproduction, build/install the current Debug app on that simulator, then:

```bash
SIMCTL_CHILD_RIVAL_PROMO_CAPTURE=1 xcrun simctl launch \
  --terminate-running-process --console-pty \
  AF440925-EC31-42B7-A31C-F499DC96A29B \
  com.acertainromance401.pixelboxing -pixelBoxingLanguage en
```

The exporter writes Documents/PromotionCapture inside the simulator app data
container, logs progress, and exits after capture. It fails if no real perfect
counter occurs. Adding SIMCTL_CHILD_RIVAL_PROMO_PROBE=1 runs the same simulation
without writing image frames. The exporter is disabled in Release and in normal
Debug launches without the capture environment variable.

## Presentation Limits

The capture uses normal models, geometry, combat motion, and game lighting, but
no touch HUD or SwiftUI combat signatures. Its additional three-quarter camera
is for this footage only; it is not a change to the game's normal player camera.
Simulation is rendered offline and does not measure real-device frame rate.
