"""Author RIVAL's counter-win imitation and slugger-win obsession performances.

Run with Blender --background --python-exit-code 1 --python this_file --
--output-root /path/to/workspace. Use --chapter counter or slugger for one track.
Stages, reference video, target bag, cameras and subtitles remain app-owned.
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
import create_rival_outboxer_win as comparison

author = comparison.author
performance = comparison.performance
SCENES = {
    "counter": {
        "duration": 8.0,
        "stem": "RivalCounterWin",
        "action": "RIVAL | Own Rhythm - Abandoned Technique - Imitation - No Satisfaction | 8.0s",
        "mood": "He discards his composed rhythm to copy the player; success brings no satisfaction",
        "steps": (("left", 4.30, 4.65, 0.07), ("right", 4.80, 5.15, 0.07),
                  ("right", 5.50, 5.85, 0.0), ("left", 6.00, 6.35, 0.0)),
        "hits": (("left", 0.62), ("right", 1.32), ("left", 3.90), ("right", 4.72), ("left", 5.42)),
        "beats": (("OWN RHYTHM | composed high guard", 0.0), ("OWN JAB", 0.62), ("OWN CROSS", 1.32),
                  ("STOP | look at the reference", 2.15), ("DISCARD | lower the lead hand", 2.85),
                  ("COPY | borrowed rhythm", 3.90), ("COPY | uncertain small steps", 4.30),
                  ("CAPTION | My way is not enough | app-owned", 6.0), ("END | no satisfaction", 8.0)),
    },
    "slugger": {
        "duration": 10.4,
        "stem": "RivalSluggerWin",
        "action": "RIVAL | Replay the Opening - Evade and Interrupt - Belt Ignored | 10.4s",
        "mood": "He watches only the player's openings and rehearses interruptions; the championship belt cannot draw his gaze",
        "steps": (),
        "hits": (("right", 2.40), ("right", 4.40), ("right", 6.40)),
        "beats": (("WATCH | the same exposed recovery, eyes on video", 0.0),
                  ("READY | compact counter guard", 0.95), ("EVADE 1 | move off the attack line", 2.02),
                  ("INTERRUPT 1 | single rear-hand response", 2.40), ("REPLAY | same opening", 3.30),
                  ("EVADE 2 | same response, not imitation", 4.02), ("INTERRUPT 2", 4.40),
                  ("REPLAY | same opening again", 5.30), ("EVADE 3", 6.02), ("INTERRUPT 3", 6.40),
                  ("HOLD | gaze remains on video", 7.10), ("BELT REVEAL | app-owned, never acknowledged", 8.15),
                  ("CAPTION | Not a single move | app-owned", 8.40), ("END | belt ignored", 10.4)),
    },
}
active_scene = SCENES["counter"]


def strike_amount(side, time):
    return max((performance.envelope(time, peak - 0.24, peak, peak + 0.32)
                for strike_side, peak in active_scene["hits"] if strike_side == side), default=0.0)


def blend_hand(first, second, shoulder, amount):
    start, end = first - shoulder, second - shoulder
    rotation = author.IDENTITY.slerp(start.normalized().rotation_difference(end.normalized()), amount)
    radius = start.length + (end.length - start.length) * amount
    return shoulder + (rotation @ start.normalized()) * radius


def authored_sample(time, final_pose, final_points, lengths):
    is_slugger = active_scene is SCENES["slugger"]
    ready = author.ramp(time, 0.35, 0.95) if is_slugger else 1.0
    imitation = 0.0 if is_slugger else author.ramp(time, 2.85, 3.40)
    stop = 0.0 if is_slugger else performance.envelope(time, 1.90, 2.45, 3.40)
    dissatisfaction = 0.0 if is_slugger else author.ramp(time, 6.35, 7.10)
    left_strike = strike_amount("left", time)
    right_strike = strike_amount("right", time)
    evade = max((performance.envelope(time, peak - 0.64, peak - 0.38, peak - 0.06)
                 for _, peak in active_scene["hits"]), default=0.0) if is_slugger else 0.0
    breathing = (0.003 if is_slugger else 0.003) * math.sin(math.tau * time / 2.8)
    torso_y = 1.55 + breathing - 0.009 * dissatisfaction
    yaw = (0.015 * ready + 0.065 * right_strike) if is_slugger else final_pose["torsoYaw"] * ready - 0.06 * left_strike + 0.08 * right_strike
    pitch = final_pose["torsoPitch"] * ready + 0.025 * (left_strike + right_strike) + 0.055 * dissatisfaction
    lean = final_pose["torsoLean"] * ready + (0.045 * evade if is_slugger else 0.0)
    chest = author.torso_rotation(yaw, pitch, lean)
    pelvis = author.yaw_rotation(final_pose["hipYaw"])
    pivot = Vector((0, torso_y, 0))
    height_offset = Vector((0, torso_y - 1.55, 0))
    points = {}
    for side, sign in (("left", 1), ("right", -1)):
        shoulder = author.transform_point(final_pose[side + "Shoulder"] + height_offset, pivot, chest)
        local_shoulder = final_pose[side + "Shoulder"]
        resting_hand = Vector((sign * 0.53, 1.26, 0.36))
        hand = blend_hand(resting_hand, final_pose[side + "Glove"], local_shoulder, ready)
        if side == "left":
            hand = blend_hand(hand, Vector((0.48, 1.36, 0.46)), local_shoulder, imitation)
        hand = blend_hand(hand, resting_hand, local_shoulder, 0.35 * stop + 0.035 * dissatisfaction)
        target = Vector((sign * 0.43, 1.82, 0.60 if side == "left" else 0.54))
        if is_slugger and side == "right":
            target = Vector((-0.18, 1.88, 0.62))
        hand = blend_hand(hand, target, local_shoulder, strike_amount(side, time))
        hand = author.transform_point(hand + height_offset, pivot, chest)
        pole = author.transform_point(Vector((sign * 0.65, 1.42, 0.08)) + height_offset, pivot, chest)
        elbow, solved_hand = author.solve_limb(shoulder, hand, pole,
                                             lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        if (solved_hand - hand).length > performance.TOLERANCE:
            raise ValueError("Unreachable %s strike: %s at %.3fs" % (active_scene["stem"], side, time))
        hip = author.transform_point(final_pose[side + "Hip"], Vector((0, 0.86, 0)), pelvis)
        foot = final_pose[side + "Foot"].copy()
        offset = 0.0
        for step_side, start, end, destination in active_scene["steps"]:
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
    head = author.transform_point(Vector((0, 2.28 + breathing - 0.03 * dissatisfaction, 0.04)),
                                  pivot, author.IDENTITY.slerp(chest, 0.55))
    return dict(root=Vector((0, 0, 0)), heading=0.0, chest=chest, hip=pelvis,
                torso_y=torso_y, head=head, lean=lean, points=points)


def generate(chapter, root, overwrite):
    global active_scene
    active_scene = SCENES[chapter]
    stem = active_scene["stem"]
    blend_path = root / ("art/Story/" + stem + ".blend")
    json_path = root / ("PixelBoxingIOS/Resources/story_rival_" + chapter + "_win.json")
    targets = (blend_path, json_path)
    if any(path.exists() for path in targets) and not overwrite:
        raise FileExistsError("Outputs exist for %s; use --overwrite for own-output backups" % chapter)
    comparison.DURATION = active_scene["duration"]
    comparison.LAST_FRAME = 1 + round(comparison.FPS * comparison.DURATION)
    comparison.RIG_NAME = stem + "_Rig"
    comparison.ACTION_NAME = active_scene["action"]
    comparison.STEPS = active_scene["steps"]
    comparison.BEATS = active_scene["beats"]
    comparison.authored_sample = authored_sample
    rig = comparison.author_scene()
    rig.data.name = stem + "_Skeleton"
    rig["aftermath_mood"] = active_scene["mood"]
    bpy.context.scene["stage_note"] = "App-owned reference video" if chapter == "counter" else "App-owned opening replay, counter pad and ignored belt reveal; gaze stays forward"
    payload = comparison.export_evaluated(rig)
    with tempfile.TemporaryDirectory(prefix="rival-" + chapter + "-win-") as staging:
        staged_json = Path(staging) / json_path.name
        staged_json.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")
        staged_blend = Path(staging) / blend_path.name
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(staged_blend), check_existing=False)
        existing = [path for path in targets if path.exists()]
        if existing:
            backup = Path(tempfile.mkdtemp(prefix="rival-" + chapter + "-win-backup-"))
            for path in existing:
                shutil.copy2(path, backup / path.name)
            print("OWN OUTPUT BACKUP: " + str(backup))
        for path in targets:
            path.parent.mkdir(parents=True, exist_ok=True)
        os.replace(staged_blend, blend_path)
        os.replace(staged_json, json_path)
    print("BLENDER SOURCE: " + str(blend_path))
    print("JSON RESOURCE: " + str(json_path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--chapter", choices=("counter", "slugger", "all"), default="all")
    parser.add_argument("--overwrite", action="store_true")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    root = arguments.output_root.expanduser().resolve()
    chapters = tuple(SCENES) if arguments.chapter == "all" else (arguments.chapter,)
    for chapter in chapters:
        generate(chapter, root, arguments.overwrite)


if __name__ == "__main__":
    main()