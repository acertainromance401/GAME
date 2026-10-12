"""Author RIVAL's outboxer-win comparison scene using the existing FK rig.

Run with Blender --background --python-exit-code 1 --python this_file --
--output-root /path/to/workspace. Camera, replay monitor and captions are app-owned.
"""

import argparse
import json
import math
import os
from pathlib import Path
import shutil
import sys
import tempfile

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import create_rival_pressure_win as performance

author = performance.author
FPS = 30
DURATION = 8.4
FIRST_FRAME = 1
LAST_FRAME = FIRST_FRAME + round(FPS * DURATION)
RIG_NAME = "RivalOutboxerWin_Rig"
ACTION_NAME = "RIVAL | Comparison - Three Replays - Copied Steps - Doubt | 8.4s"
STEPS = (
    ("left", 4.45, 4.85, 0.09),
    ("right", 5.00, 5.40, 0.09),
    ("right", 5.65, 6.05, 0.0),
    ("left", 6.20, 6.60, 0.0),
)
BEATS = (
    ("WATCH | quietly studying the same movement", 0.0),
    ("REPLAY 1 | gentle glove tap", 1.05),
    ("REPLAY 2 | compare timing", 2.40),
    ("REPLAY 3 | repeat again", 3.55),
    ("COPY | low lead hand and small lateral steps", 4.45),
    ("COMPARE | hold, shoulders settle, eyes lower", 6.80),
    ("CAPTION | Why does mine look different? | app-owned", 6.40),
    ("END | unresolved, not a victory pose", DURATION),
)


def authored_sample(time, final_pose, final_points, lengths):
    copy_amount = author.ramp(time, 4.05, 4.70)
    doubt = author.ramp(time, 6.70, 7.35)
    tapping = max(performance.envelope(time, start, peak, end) for start, peak, end in
                  ((0.75, 1.05, 1.40), (2.05, 2.40, 2.75), (3.20, 3.55, 3.90)))
    breathing = 0.003 * math.sin(math.tau * time / 3.4)
    torso_y = 1.55 + breathing - 0.008 * doubt
    yaw = 0.10 * (1 - copy_amount) + final_pose["torsoYaw"] * copy_amount
    pitch = 0.025 + 0.045 * doubt
    lean = final_pose["torsoLean"] * copy_amount
    chest = author.torso_rotation(yaw, pitch, lean)
    pelvis = author.yaw_rotation(final_pose["hipYaw"])
    pivot = Vector((0, torso_y, 0))
    points = {}
    for side, sign in (("left", 1), ("right", -1)):
        height_offset = Vector((0, torso_y - 1.55, 0))
        shoulder = author.transform_point(final_pose[side + "Shoulder"] + height_offset, pivot, chest)
        watching_hand = Vector((sign * 0.53, 1.26, 0.36))
        copied_hand = final_pose[side + "Glove"].copy()
        if side == "left":
            watching_hand = watching_hand.lerp(Vector((0.45, 1.60, 0.64)), tapping)
            copied_hand = Vector((0.50, 1.34, 0.52))
        local_hand = watching_hand.lerp(copied_hand, copy_amount)
        local_hand.y -= 0.055 * doubt
        hand = author.transform_point(local_hand + height_offset, pivot, chest)
        pole = author.transform_point(Vector((sign * 0.65, 1.40, 0.09)) + height_offset, pivot, chest)
        elbow, solved_hand = author.solve_limb(shoulder, hand, pole,
                                             lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        if (solved_hand - hand).length > performance.TOLERANCE:
            raise ValueError("Unreachable review gesture: %s at %.3fs" % (side, time))
        hip = author.transform_point(final_pose[side + "Hip"], Vector((0, 0.86, 0)), pelvis)
        foot = final_pose[side + "Foot"].copy()
        offset = 0.0
        for step_side, start, end, destination in STEPS:
            if step_side != side or time < start:
                continue
            if time >= end:
                offset = destination
                continue
            progress = (time - start) / (end - start)
            offset += (destination - offset) * author.smooth(progress)
            foot.y += 0.014 * math.sin(math.pi * progress) ** 2
            break
        foot.x += offset
        knee, solved_foot = author.solve_limb(hip, foot, final_points[side + "Knee"],
                                            lengths[side + "_thigh"], lengths[side + "_shin"])
        if (solved_foot - foot).length > performance.TOLERANCE:
            raise ValueError("Unreachable practice step: %s at %.3fs" % (side, time))
        points.update({side + "Shoulder": shoulder, side + "Elbow": elbow,
                       side + "Glove": solved_hand, side + "Hip": hip,
                       side + "Knee": knee, side + "Foot": solved_foot})
    head = author.transform_point(Vector((0, 2.28 + breathing - 0.025 * doubt, 0.04 + 0.018 * doubt)),
                                  pivot, author.IDENTITY.slerp(chest, 0.55))
    return dict(root=Vector((0, 0, 0)), heading=0.0, chest=chest, hip=pelvis,
                torso_y=torso_y, head=head, lean=lean, points=points)


def author_scene():
    performance.FPS, performance.DURATION = FPS, DURATION
    performance.FIRST_FRAME, performance.LAST_FRAME = FIRST_FRAME, LAST_FRAME
    performance.RIG_NAME, performance.ACTION_NAME = RIG_NAME, ACTION_NAME
    performance.STEPS = STEPS
    performance.authored_sample = authored_sample
    performance.configure_helpers()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system, scene.unit_settings.scale_length = "METRIC", 1.0
    scene.render.fps, scene.render.fps_base = FPS, 1.0
    scene.frame_start, scene.frame_end = FIRST_FRAME, LAST_FRAME
    for name, time in BEATS:
        scene.timeline_markers.new(name, frame=FIRST_FRAME + round(time * FPS))
    pose = author.standard_guard()
    points = author.facing_points(pose)
    rig = author.create_rig(pose, points, author.new_collection("01 | RIVAL Editable Comparison FK"))
    rig.data.name = "RivalOutboxerWin_Skeleton"
    rig["practice_steps"] = json.dumps(STEPS)
    rig["aftermath_mood"] = "Admiration becomes comparison; still sincere, not yet hostile"
    performance.create_preview(rig, pose, points, author.new_collection("02 | Classic RIVAL Inspection Body"))
    author.create_stage(author.new_collection("03 | Inspection Floor - App Owns Replay Monitor"))
    performance.key_animation(rig, pose, points)
    scene["export_contract"] = "StoryIntroClip v1; evaluated FK, metres, +Y up/+Z forward/+X left"
    scene["stage_note"] = "Training room throughout; app owns monitor, playback loops and captions"
    scene["aftermath_duration"] = DURATION
    scene.frame_set(LAST_FRAME)
    return rig


def export_evaluated(rig):
    reference_lengths = author.limb_lengths(author.facing_points(author.standard_guard()))
    frames = []
    previous_feet = None
    for frame in range(FIRST_FRAME, LAST_FRAME + 1):
        sample, positions, feet, bones = author.read_evaluated_frame(rig, frame)
        if not all(math.isfinite(value) for value in author.numeric_values(sample)):
            raise ValueError("Nonfinite sampled pose")
        if max(abs(length - reference_lengths[name]) for name, length in author.limb_lengths(positions).items()) > performance.TOLERANCE:
            raise ValueError("Evaluated limb length drift")
        if any(abs(scale - 1) > performance.TOLERANCE for bone in bones for scale in bone.matrix.to_scale()):
            raise ValueError("Animated bone scale")
        if min(foot.y for foot in feet.values()) > author.CONTACT_HEIGHT + performance.TOLERANCE:
            raise ValueError("Both feet airborne")
        for side, foot in feet.items():
            if foot.y < author.CONTACT_HEIGHT - performance.TOLERANCE:
                raise ValueError("Foot below contact plane")
            swinging = frames and any(step_side == side and frames[-1]["time"] < end and sample["time"] > start
                                      for step_side, start, end, _ in STEPS)
            if previous_feet is not None and not swinging and (foot - previous_feet[side]).length > performance.TOLERANCE:
                raise ValueError("Planted foot drift")
        previous_feet = {side: foot.copy() for side, foot in feet.items()}
        frames.append(sample)
    if len(frames) != LAST_FRAME or frames[0]["time"] != 0 or frames[-1]["time"] != DURATION:
        raise ValueError("Missing sampled endpoints")
    if any(first["time"] >= second["time"] for first, second in zip(frames, frames[1:])):
        raise ValueError("Unsorted sampled times")
    print("RIVAL COMPARISON: %d evaluated frames, %.1fs, fixed limbs and planted support" % (len(frames), DURATION))
    return dict(version=1, duration=DURATION, frames=frames)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--overwrite", action="store_true")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    root = arguments.output_root.expanduser().resolve()
    blend_path = root / "art/Story/RivalOutboxerWin.blend"
    json_path = root / "PixelBoxingIOS/Resources/story_rival_outboxer_win.json"
    targets = (blend_path, json_path)
    if any(path.exists() for path in targets) and not arguments.overwrite:
        raise FileExistsError("Outputs exist; use --overwrite to back up and replace this scene only")
    rig = author_scene()
    payload = export_evaluated(rig)
    with tempfile.TemporaryDirectory(prefix="rival-outboxer-win-") as staging:
        staged_json = Path(staging) / json_path.name
        staged_json.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")
        staged_blend = Path(staging) / blend_path.name
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(staged_blend), check_existing=False)
        existing = [path for path in targets if path.exists()]
        if existing:
            backup = Path(tempfile.mkdtemp(prefix="rival-outboxer-win-backup-"))
            for path in existing:
                shutil.copy2(path, backup / path.name)
            print("OWN OUTPUT BACKUP: " + str(backup))
        for path in targets:
            path.parent.mkdir(parents=True, exist_ok=True)
        os.replace(staged_blend, blend_path)
        os.replace(staged_json, json_path)
    print("BLENDER SOURCE: " + str(blend_path))
    print("JSON RESOURCE: " + str(json_path))


if __name__ == "__main__":
    main()