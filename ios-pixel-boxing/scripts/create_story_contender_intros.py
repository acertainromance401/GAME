"""Author separate counter and slugger introductions with the existing FK rig.

Run using Blender --background --python-exit-code 1 --python this_file --
--output-root /path/to/workspace. Select --chapter counter or slugger for one.
Camera, venue, captions and audio remain app-owned.
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
TOLERANCE = 2e-5
SCENES = {
    "counter": {
        "duration": 6.6,
        "stem": "CounterIntro",
        "action": "COUNTER | Measured Entry - Observe - Small Slip - Compact Guard | 6.6s",
        "steps": (("right", 0.16, 0.64, -1.44), ("left", 0.74, 1.22, -0.94),
                  ("right", 1.32, 1.80, -0.84), ("left", 1.90, 2.38, -0.34),
                  ("right", 2.48, 2.92, -0.28), ("left", 3.02, 3.46, 0.32)),
        "beats": (("ENTER | composed, measured steps", 0.0), ("GUARD | hands rise during approach", 2.15),
                  ("OBSERVE | stop, assess the player", 3.60), ("SLIP | small defensive rehearsal", 4.48),
                  ("SET | compact guard, no attack", 5.25), ("HOLD | waiting for the first move", 6.0)),
    },
    "slugger": {
        "duration": 7.4,
        "stem": "SluggerIntro",
        "action": "SLUGGER | Heavy Entry - Shoulder Release - Glove Touch - Low Guard | 7.4s",
        "steps": (("right", 0.20, 0.80, -1.44), ("left", 0.94, 1.54, -0.94),
                  ("right", 1.68, 2.28, -0.84), ("left", 2.42, 3.02, -0.34),
                  ("right", 3.16, 3.70, -0.28), ("left", 3.84, 4.38, 0.32)),
        "beats": (("ENTER | slower, heavy planted steps", 0.0), ("STOP | settle the weight", 4.38),
                  ("SHOULDERS | short release", 4.75), ("GLOVES | one deliberate touch", 5.54),
                  ("SET | low, heavy guard", 6.15), ("HOLD | quiet face-off", 6.70)),
    },
}
active_scene = SCENES["counter"]


def blend_hand(first, second, shoulder, amount):
    start, end = first - shoulder, second - shoulder
    rotation = author.IDENTITY.slerp(start.normalized().rotation_difference(end.normalized()), amount)
    return shoulder + (rotation @ start.normalized()) * (start.length + (end.length - start.length) * amount)


def final_guard():
    pose = author.standard_guard()
    if active_scene is SCENES["counter"]:
        return pose
    reference = author.facing_points(pose)
    lengths = author.limb_lengths(reference)
    pose.update(torsoYaw=-0.24, torsoPitch=-0.045, torsoLean=-0.008, hipYaw=-0.24)
    pose["leftGlove"] = Vector((0.50, 1.48, 0.44))
    pose["rightGlove"] = Vector((-0.48, 1.62, 0.42))
    points = author.facing_points(pose)
    chest = author.torso_rotation(pose["torsoYaw"], pose["torsoPitch"], pose["torsoLean"])
    pivot = Vector((0, pose["torsoY"], 0))
    for side in ("left", "right"):
        elbow, hand = author.solve_limb(points[side + "Shoulder"], points[side + "Glove"],
                                        reference[side + "Elbow"], lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        if (hand - points[side + "Glove"]).length > TOLERANCE:
            raise ValueError("Unreachable low guard: " + side)
        pose[side + "Elbow"] = author.transform_point(elbow, pivot, chest.inverted())
        knee, foot = author.solve_limb(points[side + "Hip"], points[side + "Foot"],
                                      reference[side + "Knee"], lengths[side + "_thigh"], lengths[side + "_shin"])
        if (foot - points[side + "Foot"]).length > TOLERANCE:
            raise ValueError("Unreachable low-guard support: " + side)
        pose[side + "Knee"] = knee
    return pose


def foot_path(side, time, pose):
    position = author.INITIAL_FEET[side].copy()
    yaw, pitch = 0.12, 0.0
    slugger = active_scene is SCENES["slugger"]
    for step_side, start, end, destination in active_scene["steps"]:
        if step_side != side or time < start:
            continue
        final_step = destination == pose[side + "Foot"].z or abs(destination - pose[side + "Foot"].z) < 1e-6
        if time >= end:
            position.z = destination
            if final_step:
                yaw = pose[side + "FootYaw"]
            continue
        progress = (time - start) / (end - start)
        position.z += (destination - position.z) * author.smooth(progress)
        position.y += (0.040 if slugger else 0.052) * math.sin(math.pi * progress) ** 2
        pitch = (0.10 if slugger else 0.14) * math.sin(2 * math.pi * progress) * math.sin(math.pi * progress)
        if final_step:
            yaw += (pose[side + "FootYaw"] - yaw) * author.smooth(progress)
        break
    return position, yaw, pitch


def authored_sample(time, pose, final_points, lengths):
    slugger = active_scene is SCENES["slugger"]
    walk_end = active_scene["steps"][-1][2]
    feet = {side: foot_path(side, time, pose) for side in ("left", "right")}
    midpoint = (feet["left"][0] + feet["right"][0]) * 0.5
    final_midpoint = (pose["leftFoot"] + pose["rightFoot"]) * 0.5
    root = Vector((0, 0, midpoint.z - final_midpoint.z))
    for _, start, end, _ in active_scene["steps"]:
        if start < time < end:
            root.y = -(0.023 if slugger else 0.012) * math.sin(math.pi * (time - start) / (end - start)) ** 2
    heading = (0.10 if slugger else -0.08) * (1 - author.ramp(time, 0.80, walk_end))
    facing = author.yaw_rotation(heading)
    stance = author.ramp(time, walk_end - 0.70, walk_end + 0.55)
    walking = 1 - author.ramp(time, walk_end - 0.25, walk_end + 0.20)
    cycle = math.sin(math.tau * (time - 0.16) / (1.44 if slugger else 1.16)) * walking
    observe = 0.0 if slugger else performance.envelope(time, 3.62, 3.95, 4.26)
    slip = 0.0 if slugger else performance.envelope(time, 4.20, 4.48, 4.94)
    shoulders = performance.envelope(time, 4.50, 4.75, 5.05) if slugger else 0.0
    touch = performance.envelope(time, 5.15, 5.54, 5.98) if slugger else 0.0
    yaw = -0.06 + (pose["torsoYaw"] + 0.06) * stance - 0.075 * observe + 0.045 * shoulders
    pitch = -0.02 + (pose["torsoPitch"] + 0.02) * stance + 0.035 * slip - 0.025 * shoulders
    lean = pose["torsoLean"] * stance + 0.004 * cycle + 0.070 * slip
    torso_y = pose["torsoY"] + (0.009 if slugger else 0.005) * cycle + 0.018 * shoulders
    chest = author.torso_rotation(yaw, pitch, lean)
    pelvis = author.yaw_rotation(-0.05 + (pose["hipYaw"] + 0.05) * stance)
    pivot = Vector((0, torso_y, 0))
    height_offset = Vector((0, torso_y - pose["torsoY"], 0))
    hands_ready = author.ramp(time, 4.00, 6.25) if slugger else author.ramp(time, 1.45, 3.10)
    points, foot_angles = {}, {}
    for side, sign in (("left", 1), ("right", -1)):
        shoulder = author.transform_point(pose[side + "Shoulder"] + height_offset, pivot, chest)
        resting_hand = author.transform_point(Vector((sign * 0.58, 1.15, 0.20 + sign * 0.035 * cycle)) + height_offset, pivot, chest)
        ready_hand = author.transform_point(pose[side + "Glove"] + height_offset, pivot, chest)
        hand = blend_hand(resting_hand, ready_hand, shoulder, hands_ready)
        if slugger:
            hand = blend_hand(hand, Vector((sign * performance.CLAP_HALF_GAP, 1.70, 0.62)), shoulder, touch)
        pole = author.transform_point(Vector((sign * 0.64, 1.43, 0.05)) + height_offset, pivot, chest)
        ready_pole = author.transform_point(pose[side + "Elbow"] + height_offset, pivot, chest)
        pole = pole.lerp(ready_pole, hands_ready * (1 - touch))
        elbow, solved_hand = author.solve_limb(shoulder, hand, pole, lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        if (solved_hand - hand).length > TOLERANCE:
            raise ValueError("Unreachable intro hand: %s at %.3fs" % (side, time))
        hip = author.transform_point(pose[side + "Hip"], Vector((0, 0.86, 0)), pelvis)
        foot_world, foot_yaw, foot_pitch = feet[side]
        foot = facing.inverted() @ (foot_world - root - Vector((0, author.BASE_HEIGHT, 0)))
        knee_pole = Vector((sign * 0.27, 0.47, 0.38)).lerp(final_points[side + "Knee"], stance)
        knee, solved_foot = author.solve_limb(hip, foot, knee_pole, lengths[side + "_thigh"], lengths[side + "_shin"])
        if (solved_foot - foot).length > TOLERANCE:
            raise ValueError("Unreachable intro support: %s at %.3fs" % (side, time))
        points.update({side + "Shoulder": shoulder, side + "Elbow": elbow, side + "Glove": solved_hand,
                       side + "Hip": hip, side + "Knee": knee, side + "Foot": solved_foot})
        foot_angles[side] = (foot_yaw - heading, foot_pitch)
    head = author.transform_point(Vector((0, 2.28 + 0.004 * cycle - 0.018 * observe, 0.04)),
                                  pivot, author.IDENTITY.slerp(chest, 0.55))
    return dict(root=root, heading=heading, chest=chest, hip=pelvis, torso_y=torso_y,
                head=head, lean=lean, points=points, foot_angles=foot_angles, guard=hands_ready)


def create_preview(rig, pose, points, collection, chapter):
    performance.create_preview(rig, pose, points, collection)
    colors = {
        "counter": {"Red trunks": (0.035, 0.28, 0.19), "Red gloves": (0.045, 0.39, 0.25),
                    "Dark red wrist straps": (0.76, 0.83, 0.79), "Skin": (0.67, 0.44, 0.29)},
        "slugger": {"Red trunks": (0.065, 0.065, 0.065), "Red gloves": (0.10, 0.10, 0.10),
                    "Dark red wrist straps": (0.82, 0.66, 0.23), "Skin": (0.63, 0.37, 0.23)},
    }[chapter]
    for surface in bpy.data.materials:
        if not surface.name.startswith("Classic RIVAL | "):
            continue
        suffix = surface.name.split(" | ", 1)[1]
        if suffix in colors:
            converted = tuple(((value + 0.055) / 1.055) ** 2.4 if value > 0.04045 else value / 12.92 for value in colors[suffix])
            surface.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*converted, 1.0)
        surface.name = chapter.title() + " | " + suffix
    trim = bpy.data.materials[chapter.title() + " | Dark red wrist straps"]
    bpy.data.objects["Classic red waistband"].data.materials[0] = trim
    if chapter == "counter":
        hair = author.material("Counter | Cropped hair", (0.035, 0.030, 0.026), 0.95)
        head = author.SCENE_TO_BLENDER.transposed() @ rig.data.bones["head"].head_local
        author.preview_piece("Counter cropped hair", rig, collection, "head", head + Vector((0, 0.22, -0.035)),
                             (0.46, 0.16, 0.48), hair)
    else:
        torso = bpy.data.objects["Classic torso"]
        center = sum((vertex.co for vertex in torso.data.vertices), Vector()) / len(torso.data.vertices)
        for vertex in torso.data.vertices:
            delta = author.SCENE_TO_BLENDER.transposed() @ (vertex.co - center)
            vertex.co = center + author.SCENE_TO_BLENDER @ Vector((delta.x * 1.10, delta.y, delta.z * 1.08))


def export_evaluated(rig, pose):
    frames, previous_feet = [], None
    reference_lengths = author.limb_lengths(author.facing_points(pose))
    for frame in range(author.FIRST_FRAME, author.LAST_FRAME + 1):
        sample, points, feet, bones = author.read_evaluated_frame(rig, frame)
        if set(sample["pose"]) != set(author.POINT_FIELDS + author.SCALAR_FIELDS) or not all(math.isfinite(value) for value in author.numeric_values(sample)):
            raise ValueError("Invalid sampled pose schema or coordinates")
        if max(abs(length - reference_lengths[name]) for name, length in author.limb_lengths(points).items()) > TOLERANCE:
            raise ValueError("Evaluated limb length drift")
        if any(abs(scale - 1) > TOLERANCE for bone in bones for scale in bone.matrix.to_scale()):
            raise ValueError("Animated limb scale")
        if min(foot.y for foot in feet.values()) > author.CONTACT_HEIGHT + TOLERANCE:
            raise ValueError("Both feet airborne")
        for side, foot in feet.items():
            if foot.y < author.CONTACT_HEIGHT - TOLERANCE:
                raise ValueError("Foot below contact plane")
            swing = frames and any(step_side == side and frames[-1]["time"] < end and sample["time"] > start
                                   for step_side, start, end, _ in active_scene["steps"])
            if previous_feet is not None and not swing and (foot - previous_feet[side]).length > TOLERANCE:
                raise ValueError("Planted foot drift")
        previous_feet = {side: foot.copy() for side, foot in feet.items()}
        frames.append(sample)
    final = frames[-1]
    errors = [abs(final["pose"][field] - pose[field]) for field in author.SCALAR_FIELDS]
    errors.extend((Vector(tuple(final["pose"][field][axis] for axis in ("x", "y", "z"))) - pose[field]).length for field in author.POINT_FIELDS)
    if max(errors) > TOLERANCE or Vector(tuple(final["root"].values())).length > TOLERANCE or abs(final["heading"]) > TOLERANCE:
        raise ValueError("Final authored guard or root mismatch")
    if len(frames) != author.LAST_FRAME or frames[0]["time"] != 0 or final["time"] != active_scene["duration"]:
        raise ValueError("Missing frame/time endpoints")
    if any(first["time"] >= second["time"] for first, second in zip(frames, frames[1:])):
        raise ValueError("Unsorted sample times")
    final["root"], final["heading"] = dict(x=0.0, y=0.0, z=0.0), 0.0
    print("%s: %d evaluated frames, %.1fs; fixed limbs, planted support, final guard checked" %
          (active_scene["stem"], len(frames), active_scene["duration"]))
    return dict(version=1, duration=active_scene["duration"], frames=frames)


def generate(chapter, root, overwrite):
    global active_scene
    active_scene = SCENES[chapter]
    stem = active_scene["stem"]
    blend_path = root / ("art/Story/" + stem + ".blend")
    json_path = root / ("PixelBoxingIOS/Resources/story_" + chapter + "_intro.json")
    targets = (blend_path, json_path)
    if any(path.exists() for path in targets) and not overwrite:
        raise FileExistsError("Outputs exist for %s; use --overwrite for own-output backups" % chapter)
    author.FPS, author.DURATION = FPS, active_scene["duration"]
    author.FIRST_FRAME, author.LAST_FRAME = 1, 1 + round(FPS * author.DURATION)
    author.RIG_NAME, author.STEPS = stem + "_Rig", active_scene["steps"]
    author.authored_sample = authored_sample
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system, scene.unit_settings.scale_length = "METRIC", 1.0
    scene.render.fps, scene.render.fps_base = FPS, 1.0
    scene.frame_start, scene.frame_end = author.FIRST_FRAME, author.LAST_FRAME
    for name, time in active_scene["beats"]:
        scene.timeline_markers.new(name, frame=1 + round(time * FPS))
    pose = final_guard()
    points = author.facing_points(pose)
    rig = author.create_rig(pose, points, author.new_collection("01 | " + chapter.title() + " Editable FK"))
    rig.data.name = stem + "_Skeleton"
    rig["intro_style"] = active_scene["action"]
    create_preview(rig, pose, points, author.new_collection("02 | " + chapter.title() + " Inspection Body"), chapter)
    author.create_stage(author.new_collection("03 | Inspection Floor and Cameras"))
    author.key_animation(rig, pose, points)
    rig.animation_data.action.name = active_scene["action"]
    scene["intro_duration"] = author.DURATION
    scene["export_contract"] = "StoryIntroClip v1; evaluated FK, metres, +Y up/+Z forward/+X left"
    payload = export_evaluated(rig, pose)
    scene.frame_set(author.LAST_FRAME)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    with tempfile.TemporaryDirectory(prefix="story-" + chapter + "-intro-") as staging:
        staged_json = Path(staging) / json_path.name
        staged_json.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")
        staged_blend = Path(staging) / blend_path.name
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(staged_blend), check_existing=False)
        existing = [path for path in targets if path.exists()]
        if existing:
            backup = Path(tempfile.mkdtemp(prefix="story-" + chapter + "-intro-backup-"))
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
    for chapter in tuple(SCENES) if arguments.chapter == "all" else (arguments.chapter,):
        generate(chapter, root, arguments.overwrite)


if __name__ == "__main__":
    main()