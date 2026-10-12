# Story Introduction Authoring

## Current Scope (2026-10-12)

The 1.2(6) app loads 11 authored JSON clips from
[Story resources](../../PixelBoxingIOS/Resources/). Blender files are
editable authoring sources, not shipping character meshes. The app uses its
shared SceneKit fighter and coach rigs for intros, victory scenes and the
championship ending. Combat remains procedural; authored poses do not replace
combat rules or grant rewards.

The scripts in [scripts](../../scripts/) author the pressure, outboxer, counter,
slugger and championship scenes. Commands below are run from the iOS workspace
(`ios-pixel-boxing`), not the parent GAME repository. Generated backups remain
local and are excluded from Git. Re-generation is not performed by document
updates; visual approval and any generation checks apply only to their recorded
versions. [Development cases](../../DEVELOPMENT_ISSUES_AND_SOLUTIONS.md) retain
the limitations and reverted waist-mesh experiment.

## Pressure

`PressureIntro.blend` contains a real editable FK armature, one baked action,
pressure-colored inspection meshes, three cameras, and timeline beat markers.
It is authoring material only, not replacement app geometry. No punches are keyed.
Frames 1-187 at 30fps span 6.2 seconds: six alternating planted steps over 1.8m,
settling, a slight chest/head-position glance, turning to the player, then a compact
high guard held from 5.8s. Select `PressureIntro_Rig` in Pose Mode to edit the root,
chest, pelvis, head, arms, legs, hands, and feet. Each frame has location/quaternion
keys; limb lengths and scales remain fixed. Re-export saved edits as shown below.

## Axes, Units, and Contract

One unit is one meter. SceneKit uses +Y up, +Z fighter forward, +X fighter left.
Blender uses +Z up, -Y fighter forward: `(x, y, z) -> (x, -z, y)`;
export reverses this as `(x, y, z) -> (x, z, -y)`. All angles are radians.

The JSON contract is exactly `{version:1, duration, frames:[{time, root:{x,y,z},
heading, pose}]}`. Pose contains `torsoY`, `torsoYaw`, `torsoPitch`, `torsoLean`,
`hipYaw`, `headBob`, each side's `FootYaw` and `FootPitch`, and each side's
`Shoulder`, `Elbow`, `Glove`, `Hip`, `Knee`, `Foot` vectors. There are no extra
resource metadata fields. Every sample comes from evaluated Blender pose bones.
Arms are inverse-chest coordinates about `torsoY`; hips are inverse-pelvis-yaw
coordinates about `(0,0.86,0)`; knees and feet are facing-local coordinates.
Chest rotation order is `lean(Z) * yaw(Y) * pitch(X)`, matching `torsoOrientation`.

Root is an offset in the final opponent-facing frame, from `(0,0,-1.8)` to zero;
heading ends at zero. The preview's fixed root base height, 0.13m, is not exported.
Neutral foot anchors are 0.14m above that base. World foot plants are compensated
for animated root height exactly once, so root settling does not add foot lift.
The preview floor matches the app boot sole bottom, at 0.1225m.

## Regenerate

From the iOS workspace root, using Blender's bundled Python with no added packages:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python-exit-code 1 --python scripts/create_story_intro.py -- \
  --output-root "$PWD" --overwrite
```

The output root is optional and defaults to the script's repository. Existing
targets are refused without `--overwrite`; with it, originals are copied into
`art/Story/backups/<UTC timestamp>/` before replacement. To export manual edits
without rebuilding or saving over the authored Blender file:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python-exit-code 1 --python scripts/create_story_intro.py -- \
  --export-existing --overwrite
```

Generation checks evaluated limb lengths/scales, planted feet, finite values,
strictly increasing times, both time endpoints, and the final guard before saving.
Failed checks leave existing outputs untouched. Export uses the scene frame range.

## Scope and Limitations

The end pose targets the raw `FightPose.neutral(stride:0, style:.standard)` followed
by `applyGuard(style:.standard, amount:1)`, including its small final lean and the
pre-lean head anchor used when constructing the guard. Fixed segment lengths are
derived from that exact target, inheriting its stylized, asymmetric arm proportions.
It does not reproduce the app's subsequent arm-length/readiness/defense solvers.
The glance uses supported chest rotation and partial head displacement, not an
independent head-yaw channel absent from the JSON contract. Inspection geometry
is deliberately simple. The authoring script does not change Swift or project files.

## App Playback

The app bundles the JSON as a resource. `StoryIntroClip` decodes and interpolates
the sampled poses; `BoxerRig.updateAuthoredPose` renders them without combat pose
solvers. Separate presentation fighters own the introduction, and `CombatEngine`
does not advance while it plays. First encounters use the full 6.2-second track;
seen encounters use a 1.9-second guarded face-off. Skipping restores gameplay
and starts the bell. An active bout resumes without repeating its introduction.
Seen introductions can be replayed from opponent selection without modifying the
active bout or results. App inactivity freezes playback until the screen is active.

The pressure venue is the procedural `MapDressing.pressureGym()` around the
unchanged ring. Other arenas and fight geometry are not replaced. Subtitles have
Korean, English, and Japanese translations; no voice-over is included.

## Outboxer

`OutboxerIntro.blend` contains the separate editable `OutboxerIntro_Rig` and
outboxer action. Frames 1-205 at 30fps span 6.8 seconds. The fighter enters on a
diagonal with three planted steps, makes a short lateral step, acknowledges the
opponent with a glove, and settles into a bladed stance with a low lead hand and
high rear hand. No punches or jumps are keyed. The final root and heading are zero.

`scripts/create_outboxer_intro.py` reuses the pressure author's rig/export helpers
without changing the pressure source or resource. It exports evaluated Blender
pose bones to `PixelBoxingIOS/Resources/story_outboxer_intro.json` using the same
axes and pose contract above. Regenerate from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python-exit-code 1 --python scripts/create_outboxer_intro.py -- \
  --output-root "$PWD" --overwrite
```

The app renders the same procedural outboxer in `MapDressing.regionalHall()`.
Full first-encounter playback, short rematch playback, skip, inactivity freeze,
and introduction replay use the shared story controller. Replaying an intro does
not replace an active checkpoint. Camera movement and localized subtitles remain
app-owned, not Blender-owned. Preview meshes are authoring references only.

## RIVAL After Pressure Victory

`RivalPressureWin.blend` and `story_rival_pressure_win.json` contain an 8.2-second
performance: three glove claps, a hopeful reaction, four small planted practice
steps, and a final nod. The app cuts from ringside to a separate training room at
3.2 seconds. A dedicated RIVAL rig plays the authored pose without advancing or
modifying the finished bout. The result's Continue action offers unseen playback;
completion or skip records viewing separately from the already-saved victory and
appearance unlock. App inactivity freezes playback. Subtitles are localized.

Regenerate with Blender using `scripts/create_rival_pressure_win.py` and the same
`--output-root "$PWD" --overwrite` options as the introduction scripts above.

## RIVAL After Outboxer Victory

`RivalOutboxerWin.blend` and `story_rival_outboxer_win.json` contain an 8.4-second
performance, sampled into 253 evaluated FK frames at 30fps. RIVAL taps a replay
control three times, copies a low lead hand and four small lateral steps, then
lowers his eyes in doubt. The training room, monitor, camera cut and localized
last line are app-owned. The final beat introduces comparison, not hostility.

The monitor uses 24 cached SceneKit snapshots of a separate player rig performing
the existing outboxer introduction movement. This is a staged motion study, not
a recording of the completed bout. No live fighter or combat state is reused.

An unseen scene is offered by Continue after an outboxer victory. Once the opponent
has been cleared, the film button in opponent selection can replay the scene
regardless of viewing history. Replay leaves the active bout and viewing flags
unchanged; completion and skip return to opponent selection.

Regenerate from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python-exit-code 1 --python scripts/create_rival_outboxer_win.py -- \
  --output-root "$PWD" --overwrite
```

The author reuses the classic inspection body and FK helpers without replacing
the pressure scene. Export checks finite values, fixed limb lengths, unit bone
scales, planted support, increasing timestamps and both endpoints before saving.

## Counter and Slugger Bouts

The ordinary story sequence now includes counter (8 rounds) and slugger (10 rounds),
unlocked by preceding victories. Counter uses fixed midrange defense and a delayed,
single recovery punish. Slugger uses slow infighting pressure, short heavy sequences,
and explicit miss/stamina recovery gaps. Neither learns the player's habits.

Counter wears green with silver trim; slugger wears black with gold trim and a
heavier cosmetic build. Their victories unlock the same complete appearances in
the waiting room, without changing the equipped player's fighting style or stats.
Their tournament halls reuse the regional geometry with distinct banners, accents
and lighting. Each opponent now has its own authored entrance, localized venue name,
dialogue timing and camera approach. Neither reuses the pressure entrance track.

## Counter and Slugger Introductions

`CounterIntro.blend` / `story_counter_intro.json` contain 199 evaluated frames over
6.6 seconds. Six measured steps bring the opponent forward, hands rising during
the approach. After stopping he observes the player, makes a small defensive slip,
and holds a compact standard guard. The dialogue starts at 4.95 seconds.

`SluggerIntro.blend` / `story_slugger_intro.json` contain 223 evaluated frames over
7.4 seconds. Six slower, lower-lift steps precede a shoulder release and one glove
touch at 5.54 seconds. He settles into a low, heavy guard, with dialogue from 6.0
seconds. No punches or jumps are authored. The inspection meshes use each opponent's
colors; live geometry remains the existing procedural fighter and cosmetic build.

Both sources have separate editable FK armatures, named actions and beat markers.
Export reads evaluated bones, verifies fixed limb lengths/scales, planted support,
finite values, increasing timestamps, endpoints and the exact final authored guard.
The original pressure and outboxer sources and resources are not modified.

Regenerate both, or add `--chapter counter` / `--chapter slugger` for just one:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python-exit-code 1 --python scripts/create_story_contender_intros.py -- \
  --output-root "$PWD" --overwrite
```

First encounters use the full track. Seen encounters retain the existing 1.9-second
face-off sampled from that opponent's final pose; introduction replay plays the full
track. Skip, inactivity freeze and replay checkpoint protection use the shared flow.
Camera approach and dialogue follow each entrance's beats. No save flags are reset.

## RIVAL After Counter and Slugger Victories

`RivalCounterWin.blend` / `story_rival_counter_win.json` contain 241 evaluated frames
over 8.0 seconds. RIVAL starts with his composed rhythm, stops to study the reference,
lowers his lead hand to imitate the player, then holds without satisfaction.

`RivalSluggerWin.blend` / `story_rival_slugger_win.json` contain 313 evaluated frames
over 10.4 seconds. RIVAL watches the same attack opening, rehearses three short
evade-and-rear-hand interruptions at 2.4, 4.4 and 6.4 seconds, then holds his gaze
on the video. At 8.15 seconds the camera widens to reveal the championship belt
beside him; he never acknowledges it. A compact suspended counter pad sits below
his view of the monitor and reacts only to the three authored counter beats.

The slugger monitor uses 32 cached snapshots of isolated presentation fighters,
generated with the game's existing hook, cross and recovery pose logic. It crops
to a committed player hook and the opponent's interrupting cross, holds the exposed
recovery, and repeats only that short segment every two seconds. This is a staged
combat study, not a recording of the completed bout. Other chapters keep their
existing video tracks. No combat, damage or story progress advances during playback.

Both use the classic fixed FK anatomy. Hand transitions interpolate direction along
an arc and reach radius separately, avoiding the inner unreachable region of the
asymmetric arms. Cameras, stages, captions and inactivity handling remain app-owned.
First-view Continue and victory-unlocked film replay share the existing scene route.

Regenerate both tracks, or add `--chapter counter` / `--chapter slugger` for one:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python-exit-code 1 --python scripts/create_rival_later_wins.py -- \
  --output-root "$PWD" --overwrite
```

## Championship and Ending

The fifth story bout is now a 12-round championship against RIVAL, unlocked by
the preceding four victories. Its championship arena has two spectator tiers,
balconies, a four-sided overhead scoreboard, a long entrance runway and a bright
neutral ring against darker audience lighting. Independent RIVAL access
retains its existing four-victory unlock rule and separate ordinary save records.

`ChampionshipIntro.blend` / `story_championship_intro.json` contain 271 evaluated
frames over 9.0 seconds. A belt display opens the scene; RIVAL watches the actual
player, quietly adjusts his gloves and raises his own compact guard. The localized
line starts at 4.5 seconds. The camera ends on both fighters before the round bell.
Seen encounters use the existing short introduction; replay uses the full track.

`ChampionshipEnding.blend` / `story_championship_ending.json` and the matching
`ChampionshipEndingPlayer.blend` / `story_championship_ending_player.json` contain
571 evaluated frames each over 19.0 seconds. RIVAL sits in the corner, lifts his
face and stands before reciprocating the player's glove at 5.4-6.0 seconds. The
player's non-contact hand stays lowered, clear of the approach. RIVAL gives a
reserved nod, not an immediate full reconciliation. The player receives the belt
at 6.8 seconds. At 8.0 seconds a separate champion rig appears at ring center in
the Final Champion outfit and belt, without changing the player's saved equipment.
Both gloves rise at 9.2-11.12 seconds, hold through 13.7 seconds and lower by
15.47 seconds. The victory camera frames the full champion and arena. At 16.0
seconds the app cuts to the gym with a stopped monitor and RIVAL returning to his
own stance. The last line is "Next time... my own way."

The paired authored actors are 1.2 metres apart. Their ring samples share one
app-owned corner rotation and offset, never the finished fight's live positions.
RIVAL root/heading are zero; the companion root is `(0, 0, 1.2)` with heading pi.
The paired actors are hidden during the ring-center ceremony; the champion is
hidden at the gym cut. Authored pelvis positions also drive the
trunks and waistband so the seated pose remains connected. The app owns the stool,
camera, belt, stopped screen, captions, playback freeze and transitions.

Regenerate all three production tracks:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
  --python-exit-code 1 --python scripts/create_championship_scenes.py -- \
  --output-root "$PWD" --overwrite
```

Add `--ending-only` to regenerate just the ending and player tracks, leaving the
approved championship introduction unchanged.

Export checks schema, finite values, increasing timestamps, endpoints, fixed limb
lengths, unit scales, planted foot support, inverse torso-local reconstruction and
the final standard guard. Paired checks cover all 240 greeting frames for intersecting
torso, boot and glove meshes, plus 19 continuous glove-contact frames. The measured
surface gap is approximately 0.205 mm. These are authoring/source checks, not
confirmation of on-device SceneKit rendering.

Victory offers the ending through Continue; defeat and draw retain rematch without
the ending. Championship victory unlocks RIVAL's appearance, the story-exclusive
Final Champion outfit and an optional belt in the waiting room. The new outfit has
pearl-white trunks, black panels, gold piping, a crown waist crest, champion
lettering, curved gold knuckle panels and detailed matching boots. Existing story
victories unlock it through the same saved championship reward flag. Champion Gold
keeps its legacy story and ordinary achievement access. The film button replays
the entire greeting, victory ceremony and epilogue without modifying the
active checkpoint, learned observations, cleared opponents or viewing flags.

## Story Observation Memory

All story fights collect player habits and resolved attack outcomes. The first
four opponents continue using their fixed non-learning AI. Only championship RIVAL
uses the existing adaptive policy, frozen to the profile at the start of each
round. Completed rounds promote observations exactly once into story-only memory;
changes affect the next round, not current-round weights or difficulty. Ordinary
RIVAL's keys, statistics and learning remain separate.

Checkpoints carry the current round's uncommitted observations and fixed difficulty
alongside accumulated story memory. Restoring a down count retains that round's
profile; restoring a corner does not promote it again. Older saves default missing
fields without resetting victories, outfits, viewing history or the active bout.
