"""Author and export the editable Blender outboxer introduction for RIVAL.

Run with Blender's Python. Shared FK, preview, and coordinate-contract helpers
come from create_story_intro; this wrapper never calls its pressure entry point.
"""

import argparse
import json
import math
import os
from pathlib import Path
import sys
import tempfile

import bpy
from mathutils import Quaternion, Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import create_story_intro as author


FPS = 30
DURATION = 6.8
FIRST_FRAME = 1
LAST_FRAME = FIRST_FRAME + round(FPS * DURATION)
RIG_NAME = "OutboxerIntro_Rig"
ACTION_NAME = "OUTBOXER | Diagonal Entry - Side Step - Acknowledge - Bladed Guard | 6.8s"
ROOT_START = Vector((0.65, 0, -1.50))
ENTRY_HEADING = math.atan2(-ROOT_START.x, -ROOT_START.z)
STEPS = (
    ("right", 0.18, 0.96, (0.13, author.CONTACT_HEIGHT, -0.68)),
    ("left", 1.08, 1.88, (0.47, author.CONTACT_HEIGHT, 0.12)),
    ("right", 2.02, 2.78, (-0.32, author.CONTACT_HEIGHT, -0.28)),
    ("left", 3.12, 3.66, (0.31, author.CONTACT_HEIGHT, 0.32)),
)
BEATS = (
    ("ENTER | diagonal from own corner", 0),
    ("WALK | three alternating planted steps", 0.18),
    ("SHIFT | light lateral step, no jump", 3.12),
    ("ACKNOWLEDGE | calm lead glove and nod", 4.02),
    ("SET | low lead, high rear, bladed torso", 5.10),
    ("HOLD | outboxing stance", 5.90),
)


def outboxer_guard():
    pose = author.standard_guard()
    reference = author.facing_points(pose)
    lengths = author.limb_lengths(reference)
    pose.update(torsoYaw=-0.58, torsoPitch=-0.04, torsoLean=-0.006, hipYaw=-0.42)
    pose["leftGlove"] += Vector((0, -0.52, 0.16))
    pose["leftElbow"] += Vector((0, -0.17, 0.09))
    points = author.facing_points(pose)
    chest = author.torso_rotation(pose["torsoYaw"], pose["torsoPitch"], pose["torsoLean"])
    pivot = Vector((0, pose["torsoY"], 0))
    for side in ("left", "right"):
        elbow, hand = author.solve_limb(
            points[side + "Shoulder"], points[side + "Glove"], points[side + "Elbow"],
            lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        pose[side + "Elbow"] = author.transform_point(elbow, pivot, chest.inverted())
        pose[side + "Glove"] = author.transform_point(hand, pivot, chest.inverted())
        knee, foot = author.solve_limb(
            points[side + "Hip"], points[side + "Foot"], reference[side + "Knee"],
            lengths[side + "_thigh"], lengths[side + "_shin"])
        if (foot - points[side + "Foot"]).length > 2e-5:
            raise ValueError("Final outboxer foot is unreachable: " + side)
        pose[side + "Knee"] = knee
    return pose


def foot_path(side, time, final_pose):
    facing = author.yaw_rotation(ENTRY_HEADING)
    position = ROOT_START + facing @ (final_pose[side + "Foot"]
                                      + Vector((0, author.BASE_HEIGHT, 0)))
    yaw = ENTRY_HEADING + final_pose[side + "FootYaw"] * 0.35
    pitch = 0.0
    for step_side, start, end, destination in STEPS:
        if step_side != side or time < start:
            continue
        target = Vector(destination)
        target_yaw = final_pose[side + "FootYaw"]
        if time >= end:
            position = target
            yaw = target_yaw
            continue
        progress = (time - start) / (end - start)
        position = position.lerp(target, author.smooth(progress))
        position.y += (0.045 if start > 3 else 0.075) * math.sin(math.pi * progress) ** 2
        yaw += (target_yaw - yaw) * author.smooth(progress)
        pitch = 0.12 * math.sin(2 * math.pi * progress) * math.sin(math.pi * progress)
        break
    return position, yaw, pitch


def authored_sample(time, final_pose, final_points, lengths):
    feet = {side: foot_path(side, time, final_pose) for side in ("left", "right")}
    heading = ENTRY_HEADING * (1 - author.ramp(time, 0.80, 2.78))
    facing = author.yaw_rotation(heading)
    midpoint = (feet["left"][0] + feet["right"][0]) * 0.5
    final_midpoint = (final_pose["leftFoot"] + final_pose["rightFoot"]) * 0.5
    root = midpoint - facing @ (final_midpoint + Vector((0, author.BASE_HEIGHT, 0)))
    root.y = -0.04 * author.ramp(time, 0, 0.30) * (1 - author.ramp(time, 3.66, 4.10))
    for _, start, end, _ in STEPS:
        if start < time < end:
            root.y -= 0.012 * math.sin(math.pi * (time - start) / (end - start)) ** 2
    shift = author.ramp(time, 2.82, 3.06) * (1 - author.ramp(time, 3.66, 3.92))
    root.x -= 0.022 * shift
    set_stance = author.ramp(time, 2.40, 5.90)
    walking = 1 - author.ramp(time, 2.56, 2.86)
    cycle = math.sin(2 * math.pi * (time - 0.18) / 1.64) * walking
    acknowledgment = author.ramp(time, 4.02, 4.34) * (1 - author.ramp(time, 4.60, 4.96))
    yaw = -0.12 + (final_pose["torsoYaw"] + 0.12) * set_stance
    pitch = -0.025 + (final_pose["torsoPitch"] + 0.025) * set_stance
    lean = 0.006 * cycle + final_pose["torsoLean"] * set_stance - 0.012 * shift
    hip_yaw = -0.14 + (final_pose["hipYaw"] + 0.14) * author.ramp(time, 1.20, 3.66)
    torso_y = 1.55 + 0.006 * cycle
    chest = author.torso_rotation(yaw, pitch, lean)
    pelvis = author.yaw_rotation(hip_yaw)
    pivot = Vector((0, torso_y, 0))
    points = {}
    foot_angles = {}
    hands_ready = author.ramp(time, 2.25, 3.86)
    for side, sign in (("left", 1), ("right", -1)):
        shoulder = author.transform_point(
            final_pose[side + "Shoulder"] + Vector((0, torso_y - 1.55, 0)), pivot, chest)
        resting_hand = Vector((sign * 0.46, 1.13 + torso_y - 1.55,
                               0.05 + sign * 0.045 * cycle))
        ready_hand = author.transform_point(
            final_pose[side + "Glove"] + Vector((0, torso_y - 1.55, 0)), pivot, chest)
        hand = resting_hand.lerp(ready_hand, hands_ready)
        if side == "left":
            hand += chest @ Vector((0.01, 0.34, -0.035)) * acknowledgment
        elbow_pole = Vector((sign * 0.62, 1.52 + torso_y - 1.55, -0.10))
        ready_elbow = author.transform_point(
            final_pose[side + "Elbow"] + Vector((0, torso_y - 1.55, 0)), pivot, chest)
        elbow, hand = author.solve_limb(shoulder, hand, elbow_pole.lerp(ready_elbow, hands_ready),
                                        lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        hip = author.transform_point(final_pose[side + "Hip"], Vector((0, 0.86, 0)), pelvis)
        foot_world, foot_yaw, foot_pitch = feet[side]
        foot = facing.inverted() @ (foot_world - root - Vector((0, author.BASE_HEIGHT, 0)))
        pole = Vector((sign * 0.28, 0.48, 0.38)).lerp(final_points[side + "Knee"], set_stance)
        knee, solved_foot = author.solve_limb(hip, foot, pole,
                                             lengths[side + "_thigh"], lengths[side + "_shin"])
        error = (solved_foot - foot).length
        if error > 2e-5:
            raise ValueError("Unreachable foot: %s at %.3fs (%.6fm)" % (side, time, error))
        points.update({side + "Shoulder": shoulder, side + "Elbow": elbow,
                       side + "Glove": hand, side + "Hip": hip,
                       side + "Knee": knee, side + "Foot": solved_foot})
        foot_angles[side] = (foot_yaw - heading, foot_pitch)
    head = author.transform_point(Vector((0, 2.28 + 0.004 * cycle - 0.024 * acknowledgment, 0.04)),
                                  pivot, author.IDENTITY.slerp(chest, 0.55))
    return dict(root=root, heading=heading, chest=chest, hip=pelvis, torso_y=torso_y,
                head=head, lean=lean, points=points, foot_angles=foot_angles, guard=hands_ready)


def slim_piece(obj, factors, basis=None):
    center = sum((vertex.co for vertex in obj.data.vertices), Vector()) / len(obj.data.vertices)
    for vertex in obj.data.vertices:
        delta = vertex.co - center
        if basis is not None:
            delta = basis.transposed() @ delta
        delta = Vector(tuple(value * factor for value, factor in zip(delta, factors)))
        vertex.co = center + (basis @ delta if basis is not None else delta)


def create_preview(rig, final_pose, points, collection):
    author.create_preview(rig, final_pose, points, collection)
    colors = {
        "Skin": (0.82, 0.62, 0.47), "Oxblood trunks": (0.035, 0.27, 0.92),
        "Burgundy gloves": (0.035, 0.34, 0.98), "Ivory trim": (0.97, 0.98, 1.0),
        "Soles and eyes": (0.022, 0.028, 0.040), "Cropped hair": (0.10, 0.072, 0.055),
    }
    names = {"Oxblood trunks": "Sapphire trunks", "Burgundy gloves": "Blue gloves",
             "Ivory trim": "White trim", "Cropped hair": "Swept hair"}
    for surface in tuple(bpy.data.materials):
        if not surface.name.startswith("Pressure | "):
            continue
        suffix = surface.name.split(" | ", 1)[1]
        replacement = author.material("Outboxer | " + names.get(suffix, suffix), colors[suffix],
                                      surface.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value)
        surface.user_remap(replacement)
        bpy.data.materials.remove(surface)
    for obj in tuple(collection.objects):
        if obj.name == "Preview cropped hair":
            mesh = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.meshes.remove(mesh)
            continue
        if obj.name == "Preview torso":
            slim_piece(obj, (0.78, 0.72, 0.97))
        elif obj.name in ("Preview trunks", "Preview waistband"):
            slim_piece(obj, (0.86, 0.75, 1.0))
        elif obj.name == "Preview head":
            slim_piece(obj, (0.90, 0.92, 0.96))
        elif obj.name == "Preview neck":
            slim_piece(obj, (0.84, 0.84, 1.0))
        elif obj.name.endswith(" shoulder"):
            slim_piece(obj, (0.80, 0.80, 0.80))
        elif any(obj.name.endswith(" " + segment) for segment in ("upper_arm", "forearm", "thigh", "shin")):
            bone = rig.data.bones[obj.vertex_groups[0].name]
            slim_piece(obj, (0.78, 1.0, 0.78), bone.matrix_local.to_3x3().normalized())
        elif obj.name.endswith(" glove") or obj.name.endswith(" cuff"):
            slim_piece(obj, (0.92, 0.92, 0.92))
        elif obj.name.endswith(" trunks stripe"):
            center = Vector((0, 0.86, 0))
            for vertex in obj.data.vertices:
                delta = author.SCENE_TO_BLENDER.transposed() @ vertex.co - center
                vertex.co = author.SCENE_TO_BLENDER @ (center + Vector((delta.x * 0.86, delta.y, delta.z * 0.75)))
        obj.name = "Outboxer | " + obj.name.removeprefix("Preview ")
    head = author.SCENE_TO_BLENDER.transposed() @ rig.data.bones["head"].head_local
    hair = bpy.data.materials["Outboxer | Swept hair"]
    skin = bpy.data.materials["Outboxer | Skin"]
    dark = bpy.data.materials["Outboxer | Soles and eyes"]
    author.preview_piece("Outboxer | fitted swept hair", rig, collection, "head",
                         head + Vector((0, 0.255, -0.035)), (0.46, 0.43, 0.19), hair)
    for index in range(3):
        author.preview_piece("Outboxer | swept forelock %d" % index, rig, collection, "head",
                             head + Vector((-0.115 + index * 0.095, 0.255 + index * 0.012, 0.13)),
                             (0.23, 0.16, 0.11), hair,
                             rotation=Quaternion(Vector((0, 0, 1)), -0.16))
    author.preview_piece("Outboxer | nose", rig, collection, "head",
                         head + Vector((0, 0.018, 0.252)), (0.060, 0.068, 0.095), skin)
    author.preview_piece("Outboxer | clean shaven mouth", rig, collection, "head",
                         head + Vector((0, -0.105, 0.232)), (0.083, 0.018, 0.014), dark, "box")
    for sign in (-1, 1):
        author.preview_piece("Outboxer | ear %d" % sign, rig, collection, "head",
                             head + Vector((sign * 0.229, 0.02, 0)), (0.075, 0.095, 0.145), skin)
    white = bpy.data.materials["Outboxer | White trim"]
    for side in ("left", "right"):
        author.preview_piece("Outboxer | %s white glove panel" % side, rig, collection, side + "_hand",
                             points[side + "Glove"] + Vector((0, 0.045, 0.163)),
                             (0.17, 0.028, 0.12), white)


def configure_helpers():
    author.FPS = FPS
    author.DURATION = DURATION
    author.FIRST_FRAME = FIRST_FRAME
    author.LAST_FRAME = LAST_FRAME
    author.RIG_NAME = RIG_NAME
    author.STEPS = STEPS
    author.authored_sample = authored_sample


def author_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.frame_start, scene.frame_end = FIRST_FRAME, LAST_FRAME
    for name, time in BEATS:
        scene.timeline_markers.new(name, frame=FIRST_FRAME + round(time * FPS))
    pose = outboxer_guard()
    points = author.facing_points(pose)
    rig = author.create_rig(pose, points, author.new_collection("01 | Outboxer Editable FK Armature"))
    rig.data.name = "OutboxerIntro_Skeleton"
    rig["anatomy_basis"] = "Pressure-compatible joint/contact landmarks and fixed segment lengths; outboxing guard"
    rig["intro_style"] = "Lean, clean-shaven, swept hair, blue/white; no punches or jumps"
    create_preview(rig, pose, points, author.new_collection("02 | Outboxer Inspection Body"))
    author.create_stage(author.new_collection("03 | Outboxer Preview Stage and Cameras"))
    for obj in tuple(bpy.data.objects):
        if obj.type in ("CAMERA", "LIGHT"):
            obj.name = "Outboxer_" + obj.name
    scene.world.name = "Outboxer Preview World"
    author.key_animation(rig, pose, points)
    rig.animation_data.action.name = ACTION_NAME
    scene["intro_duration"] = DURATION
    scene["intro_note"] = "Editable keyed FK action. JSON reads evaluated depsgraph bones only. Cameras/mesh are authoring preview."
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    scene.frame_set(LAST_FRAME)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_perspective = "CAMERA"
                area.spaces.active.shading.type = "MATERIAL"
    return rig


def export_evaluated(rig, enforce_authored_pose=True):
    scene = bpy.context.scene
    if scene.render.fps != FPS or scene.render.fps_base != 1 or scene.frame_end - scene.frame_start != DURATION * FPS:
        raise ValueError("Outboxer source must span 204 intervals at exactly 30fps")
    if rig.animation_data is None or rig.animation_data.action is None:
        raise ValueError("Missing editable armature Action")
    if not rig.animation_data.action.name.startswith("OUTBOXER | "):
        raise ValueError("Not an outboxer Action")
    expected = outboxer_guard()
    lengths = author.limb_lengths(author.facing_points(expected))
    frames = []
    previous_feet = None
    previous_time = None
    maximum_length_error = maximum_plant_error = maximum_scale_error = 0.0
    for frame in range(scene.frame_start, scene.frame_end + 1):
        sample, positions, feet, bones = author.read_evaluated_frame(rig, frame)
        if set(sample["pose"]) != set(author.POINT_FIELDS + author.SCALAR_FIELDS):
            raise ValueError("StoryIntroClip v1 pose schema mismatch")
        if not all(math.isfinite(value) for value in author.numeric_values(sample)):
            raise ValueError("Nonfinite evaluated values at frame %d" % frame)
        if previous_time is not None and sample["time"] <= previous_time:
            raise ValueError("Unsorted evaluated times")
        for name, length in author.limb_lengths(positions).items():
            maximum_length_error = max(maximum_length_error, abs(length - lengths[name]))
        for bone in bones:
            maximum_scale_error = max(maximum_scale_error, max(abs(value - 1) for value in bone.matrix.to_scale()))
        if min(feet[side].y for side in feet) > author.CONTACT_HEIGHT + 2e-5:
            raise ValueError("Both feet airborne at frame %d" % frame)
        for side in ("left", "right"):
            if feet[side].y < author.CONTACT_HEIGHT - 2e-5:
                raise ValueError("Foot below contact plane at frame %d" % frame)
            swing = previous_time is not None and any(
                step_side == side and previous_time < end and sample["time"] > start
                for step_side, start, end, _ in STEPS)
            if previous_feet is not None and not swing:
                maximum_plant_error = max(maximum_plant_error, (feet[side] - previous_feet[side]).length)
        previous_time, previous_feet = sample["time"], feet
        frames.append(sample)
    if max(maximum_length_error, maximum_plant_error, maximum_scale_error) > 2e-5:
        raise ValueError("Evaluated anatomy/contact drift: limb=%g plant=%g scale=%g" %
                         (maximum_length_error, maximum_plant_error, maximum_scale_error))
    first, final = frames[0], frames[-1]
    if first["time"] != 0 or final["time"] != DURATION:
        raise ValueError("Missing time endpoints")
    if (Vector(tuple(first["root"][axis] for axis in ("x", "y", "z"))) - ROOT_START).length > 2e-5:
        raise ValueError("First root is not the diagonal ring-corner entry")
    if Vector(tuple(final["root"].values())).length > 2e-5 or abs(final["heading"]) > 2e-5:
        raise ValueError("Final root and heading must be zero")
    if enforce_authored_pose:
        errors = [abs(final["pose"][field] - expected[field]) for field in author.SCALAR_FIELDS]
        errors.extend((Vector(tuple(final["pose"][field][axis] for axis in ("x", "y", "z")))
                       - expected[field]).length for field in author.POINT_FIELDS)
        if max(errors) > 2e-5:
            raise ValueError("Evaluated final outboxing stance mismatch: %g" % max(errors))
    final["root"], final["heading"] = dict(x=0.0, y=0.0, z=0.0), 0.0
    print("EVALUATED OUTBOXER: frames=%d duration=%.3fs fps=%d action=%s" %
          (len(frames), DURATION, FPS, rig.animation_data.action.name))
    print("MAX ERRORS: limb=%.9fm planted=%.9fm scale=%.9f; no double airborne frames" %
          (maximum_length_error, maximum_plant_error, maximum_scale_error))
    return dict(version=1, duration=DURATION, frames=frames)


def render_previews(directory):
    directory.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    saved = (scene.frame_current, scene.camera, scene.render.filepath,
             scene.render.resolution_x, scene.render.resolution_y)
    scene.render.resolution_x, scene.render.resolution_y = 800, 600
    scene.render.image_settings.file_format = "PNG"
    for label, time in (("entry", 0), ("step1", 0.58), ("step2", 1.48), ("step3", 2.38),
                        ("side_step", 3.40), ("acknowledgment", 4.40), ("stance", 6.8)):
        scene.frame_set(FIRST_FRAME + round(time * FPS))
        scene.render.filepath = str(directory / (label + "_threequarter.png"))
        bpy.ops.render.render(write_still=True)
    scene.frame_set(LAST_FRAME)
    for name in ("Front", "Side"):
        scene.camera = bpy.data.objects["Outboxer_Camera_" + name]
        scene.render.filepath = str(directory / ("stance_" + name.lower() + ".png"))
        bpy.ops.render.render(write_still=True)
    scene.frame_set(saved[0])
    scene.camera, scene.render.filepath = saved[1:3]
    scene.render.resolution_x, scene.render.resolution_y = saved[3:]
    print("SOURCE PREVIEWS: " + str(directory))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--overwrite", action="store_true", help="Replace only the two outboxer outputs after successful evaluation")
    parser.add_argument("--export-existing", action="store_true", help="Export saved Blender edits without regenerating or replacing the source")
    parser.add_argument("--preview-dir", type=Path, help="Render source previews outside the output root, for example /tmp/outboxer-preview")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    root = arguments.output_root.expanduser().resolve()
    blend_path = root / "art/Story/OutboxerIntro.blend"
    json_path = root / "PixelBoxingIOS/Resources/story_outboxer_intro.json"
    targets = (json_path,) if arguments.export_existing else (blend_path, json_path)
    if any(path.exists() for path in targets) and not arguments.overwrite:
        raise FileExistsError("Outboxer targets exist; pass --overwrite to replace only these outputs")
    preview_dir = arguments.preview_dir.expanduser().resolve() if arguments.preview_dir else None
    if preview_dir is not None and (preview_dir == root or root in preview_dir.parents):
        raise ValueError("Preview output must be outside the repository/output root")
    configure_helpers()
    if arguments.export_existing:
        bpy.ops.wm.open_mainfile(filepath=str(blend_path))
        rig = bpy.data.objects.get(RIG_NAME)
        if rig is None or rig.type != "ARMATURE":
            raise ValueError("Saved source lacks OutboxerIntro_Rig")
    else:
        rig = author_scene()
    payload = export_evaluated(rig, enforce_authored_pose=not arguments.export_existing)
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="rival-outboxer-") as staging:
        staged_json = Path(staging) / json_path.name
        staged_json.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")
        if not arguments.export_existing:
            staged_blend = Path(staging) / blend_path.name
            bpy.context.scene.frame_set(LAST_FRAME)
            bpy.context.preferences.filepaths.save_version = 0
            bpy.ops.wm.save_as_mainfile(filepath=str(staged_blend), check_existing=False)
            os.replace(staged_blend, blend_path)
        os.replace(staged_json, json_path)
    if preview_dir is not None:
        render_previews(preview_dir)
    print("BLENDER SOURCE: " + str(blend_path))
    print("JSON RESOURCE: " + str(json_path))


if __name__ == "__main__":
    main()