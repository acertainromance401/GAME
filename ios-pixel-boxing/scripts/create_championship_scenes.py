"""Author championship intro, victory ceremony and isolated ending actors.

Run in Blender with --background --factory-startup --python-exit-code 1
--python scripts/create_championship_scenes.py -- --output-root /workspace.
Only selected outputs are replaced with --overwrite, after own-output backups.
Locations, corner stool, stopped video, belt and player visibility are app-owned.
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
from mathutils.bvhtree import BVHTree

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import create_story_contender_intros as contender

performance = contender.performance
author = performance.author
FPS = 30
TOLERANCE = performance.TOLERANCE
SPACING = 1.2
CEREMONY_START = 8.0
GYM_CUT = 16.0
SEAT_DROP = 0.40
CONTACT_HEIGHT = 1.90
CONTACT_FORWARD = 0.52
CONTACT_START = 5.4
CONTACT_END = 6.0
SCENES = {
    "intro": {
        "stem": "ChampionshipIntro", "resource": "story_championship_intro.json",
        "duration": 9.0, "root": (0.0, 0.0, 0.0), "heading": 0.0,
        "action": "RIVAL | Focus - Quiet Strap Adjustment - Own Compact Guard | 9s",
        "beats": (("WAIT | focused on actual opponent", 0.0),
                  ("ADJUST | quiet glove and wrist strap", 2.4),
                  ("RELEASE | attention never leaves opponent", 4.5),
                  ("GUARD | compact standard guard", 6.6),
                  ("READY | gameplay-compatible hold", 8.0)),
    },
    "ending": {
        "stem": "ChampionshipEnding", "resource": "story_championship_ending.json",
        "duration": 19.0, "root": (0.0, 0.0, 0.0), "heading": 0.0,
        "action": "RIVAL | Respect - Yield to Champion - Own Guard | 19s",
        "beats": (("CORNER | seated, feet supported", 0.0),
                  ("FACE | lift face, not studying attacks", 0.8),
                  ("STAND | unhurried recovery", 2.2),
                  ("UP | planted, facing player", 4.3),
                  ("RECIPROCATE | left glove", 5.0),
                  ("CONTACT | matching player glove", CONTACT_START),
                  ("WITHDRAW", CONTACT_END),
                  ("NOD | genuine, reserved", 6.7),
                  ("BELT | app-owned player reward", 6.8),
                  ("CEREMONY | app isolates player at ring center", CEREMONY_START),
                  ("GYM CUT | stopped video, no player", GYM_CUT),
                  ("OWN GUARD | no imitation, no punches", GYM_CUT),
                  ("HOLD | unresolved but his own rhythm", GYM_CUT + 2.4)),
    },
    "player": {
        "stem": "ChampionshipEndingPlayer", "resource": "story_championship_ending_player.json",
        "duration": 19.0, "root": (0.0, 0.0, SPACING), "heading": math.pi,
        "action": "PLAYER | Respect - Belt Award - Both Arms Raised - Champion Hold | 19s",
        "beats": (("WAIT | quiet neutral guard", 0.0),
                  ("OFFER | left glove, not an attack", 4.3),
                  ("CONTACT | RIVAL reciprocates", CONTACT_START),
                  ("WITHDRAW", CONTACT_END),
                  ("WIN | quiet, waist clear for belt", 6.7),
                  ("BELT | app-owned reward", 6.8),
                  ("REVEAL | championship outfit, ring center", CEREMONY_START),
                  ("RAISE | both gloves, staggered naturally", 9.2),
                  ("CHAMPION | raised arms, planted feet", 11.2),
                  ("LOWER | belt remains visible", 13.7),
                  ("HOLD | quiet winner", 15.5),
                  ("HIDE | app hides companion at gym cut", GYM_CUT)),
    },
}
contact_x = None


def contact_geometry(rig, points):
    """Fit the inherited glove meshes, not an assumed spherical radius."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    vertices, polygons = [], []
    joint = points["leftGlove"] + Vector((0, author.BASE_HEIGHT, 0))
    for part in ("palm", "thumb", "cuff", "strap"):
        evaluated = bpy.data.objects["Classic left glove " + part].evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        base = len(vertices)
        vertices.extend(author.SCENE_TO_BLENDER.transposed() @ (evaluated.matrix_world @ vertex.co) - joint
                        for vertex in mesh.vertices)
        polygons.extend(tuple(base + index for index in polygon.vertices) for polygon in mesh.polygons)
        evaluated.to_mesh_clear()

    def surfaces(lateral):
        rival_joint = Vector((lateral, CONTACT_HEIGHT + author.BASE_HEIGHT, CONTACT_FORWARD))
        player_joint = Vector((-lateral, CONTACT_HEIGHT + author.BASE_HEIGHT, SPACING - CONTACT_FORWARD))
        rival_vertices = [rival_joint + vertex for vertex in vertices]
        player_vertices = [player_joint + author.yaw_rotation(math.pi) @ vertex for vertex in vertices]
        return rival_vertices, BVHTree.FromPolygons(rival_vertices, polygons), BVHTree.FromPolygons(player_vertices, polygons)

    lower, upper = 0.10, 0.28
    if not surfaces(lower)[1].overlap(surfaces(lower)[2]) or surfaces(upper)[1].overlap(surfaces(upper)[2]):
        raise ValueError("Inherited glove contact is not bracketed at 1.2m spacing")
    for _ in range(24):
        midpoint = (lower + upper) * 0.5
        _, rival_surface, player_surface = surfaces(midpoint)
        if rival_surface.overlap(player_surface):
            lower = midpoint
        else:
            upper = midpoint
    lateral = upper + 0.00005
    rival_vertices, rival_surface, player_surface = surfaces(lateral)
    gap = min(player_surface.find_nearest(vertex)[3] for vertex in rival_vertices)
    if rival_surface.overlap(player_surface) or gap > 0.002:
        raise ValueError("Inherited glove surface contact could not be fitted")
    print("CONTACT FIT: spacing=%.6fm left/left joint=(+/-%.9f, %.6f, %.6f/%.6f); surface gap=%.9fm" %
          (SPACING, lateral, CONTACT_HEIGHT + author.BASE_HEIGHT, CONTACT_FORWARD, SPACING - CONTACT_FORWARD, gap))
    return lateral


def authored_sample(track, time, pose, final_points, lengths):
    is_intro, is_player = track == "intro", track == "player"
    gym = track == "ending" and time >= GYM_CUT
    stand = author.ramp(time, 2.2, 4.3)
    seated = (1 - stand) if track == "ending" and not gym else 0.0
    ready = author.ramp(time, 6.6, 8.0) if is_intro else author.ramp(time, GYM_CUT, GYM_CUT + 2.4) if gym else 0.0
    adjustment = performance.envelope(time, 2.4, 3.2, 4.5) if is_intro else 0.0
    nod = performance.envelope(time, 6.7, 7.05, 7.6) if track == "ending" and not gym else 0.0
    fatigue = (1 - author.ramp(time, 0.8, 1.8)) * seated * 0.035
    breathing = 0.002 * math.sin(math.tau * time / 3.8)
    breathing *= 1 - author.ramp(time, 7.8 if is_intro else GYM_CUT + 2.0, 8.4 if is_intro else GYM_CUT + 2.4)
    height_offset = Vector((0, -SEAT_DROP * seated + breathing, 0))
    torso_y = pose["torsoY"] + height_offset.y
    resting_yaw = -0.18 if is_intro else -0.16
    yaw = resting_yaw + (pose["torsoYaw"] - resting_yaw) * ready
    pitch = -0.02 + 0.10 * seated + (pose["torsoPitch"] + 0.02) * ready + 0.025 * nod
    lean = pose["torsoLean"] * ready
    chest = author.torso_rotation(yaw, pitch, lean)
    pelvis = author.yaw_rotation(pose["hipYaw"])
    pivot = Vector((0, torso_y, 0))
    pelvis_pivot = Vector((0, 0.86 - SEAT_DROP * seated, 0))
    gesture = 0.0
    if not is_intro and not gym:
        gesture = author.ramp(time, 4.3 if is_player else 5.0, CONTACT_START)
        gesture *= 1 - author.ramp(time, CONTACT_END, 6.7 if is_player else 6.2)
    points, foot_angles = {}, {}
    for side, sign in (("left", 1), ("right", -1)):
        shoulder = author.transform_point(pose[side + "Shoulder"] + height_offset, pivot, chest)
        resting = Vector((sign * 0.65, 1.26, 0.38))
        if is_player:
            resting = pose[side + "Glove"].copy()
        adjusted = Vector((0.20, 1.73, 0.62)) if side == "left" else Vector((-0.13, 1.55, 0.62))
        hand = contender.blend_hand(resting, adjusted, pose[side + "Shoulder"], adjustment)
        hand = contender.blend_hand(hand, pose[side + "Glove"], pose[side + "Shoulder"], ready)
        hand = author.transform_point(hand + height_offset, pivot, chest)
        if side == "left" and gesture:
            hand = contender.blend_hand(hand, Vector((contact_x, CONTACT_HEIGHT, CONTACT_FORWARD)), shoulder, gesture)
        elif is_player and side == "right":
            hand = Vector((-0.72, 1.40, 0.12)) + height_offset
        resting_pole = author.transform_point(Vector((sign * 0.65, 1.40, 0.06)) + height_offset, pivot, chest)
        guard_pole = author.transform_point(pose[side + "Elbow"] + height_offset, pivot, chest)
        pole = resting_pole.lerp(guard_pole, ready)
        if is_player:
            delay = 0.12 if side == "right" else 0.0
            celebration = author.ramp(time, 9.2 + delay, 11.0 + delay)
            celebration *= 1 - author.ramp(time, 13.7 + delay, 15.35 + delay)
            raised_hand = author.transform_point(Vector((sign * 0.66, 2.62, 0.10)) + height_offset, pivot, chest)
            raised_direction = raised_hand - shoulder
            raised_radius = min(raised_direction.length,
                                (lengths[side + "_upper_arm"] + lengths[side + "_forearm"]) * 0.95)
            raised_hand = shoulder + raised_direction.normalized() * raised_radius
            hand = contender.blend_hand(hand, raised_hand, shoulder, celebration)
            raised_pole = author.transform_point(Vector((sign * 0.82, 2.15, 0.08)) + height_offset, pivot, chest)
            pole = pole.lerp(raised_pole, celebration)
        elbow, solved_hand = author.solve_limb(shoulder, hand, pole,
                                               lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        if (hand - solved_hand).length > TOLERANCE:
            raise ValueError("Unreachable %s %s glove at %.3fs: radius %.9fm" % (track, side, time, (hand - shoulder).length))
        hip = author.transform_point(pose[side + "Hip"], Vector((0, 0.86, 0)), pelvis)
        hip.y -= SEAT_DROP * seated
        foot = pose[side + "Foot"].copy()
        if side == "right" and track == "ending" and not gym:
            step = author.ramp(time, 2.8, 3.6)
            foot.z = 0.18 + (pose[side + "Foot"].z - 0.18) * step
            if 2.8 < time < 3.6:
                foot.y += 0.018 * math.sin(math.pi * (time - 2.8) / 0.8) ** 2
        knee_pole = final_points[side + "Knee"].lerp(Vector((sign * 0.30, 0.48, 0.64)), seated)
        knee, solved_foot = author.solve_limb(hip, foot, knee_pole,
                                              lengths[side + "_thigh"], lengths[side + "_shin"])
        if (foot - solved_foot).length > TOLERANCE:
            raise ValueError("Unreachable %s %s supported foot at %.3fs" % (track, side, time))
        points.update({side + "Shoulder": shoulder, side + "Elbow": elbow, side + "Glove": solved_hand,
                       side + "Hip": hip, side + "Knee": knee, side + "Foot": solved_foot})
        foot_angles[side] = (pose[side + "FootYaw"], 0.0)
    head = author.transform_point(Vector((0, 2.28 + height_offset.y - fatigue - 0.018 * nod, 0.04)),
                                  pivot, author.IDENTITY.slerp(chest, 0.55))
    return dict(root=Vector(SCENES[track]["root"]), heading=SCENES[track]["heading"],
                chest=chest, hip=pelvis, pelvis_pivot=pelvis_pivot, torso_y=torso_y,
                head=head, lean=lean, points=points, foot_angles=foot_angles, guard=ready)


def key_animation(track, rig, pose, points):
    """Use the existing fixed FK matrices with a separately lowered pelvis."""
    lengths = author.limb_lengths(points)
    scene = bpy.context.scene
    for frame in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(frame)
        sample = authored_sample(track, (frame - 1) / FPS, pose, points, lengths)
        root = author.bone_matrix(sample["root"], author.blender_rotation(author.yaw_rotation(sample["heading"])))
        matrices = {"CTRL_root": root @ author.UP_BASIS.to_4x4(),
                    "CTRL_chest": root @ author.bone_matrix(Vector((0, sample["torso_y"], 0)), author.blender_rotation(sample["chest"]) @ author.UP_BASIS),
                    "CTRL_pelvis": root @ author.bone_matrix(sample["pelvis_pivot"], author.blender_rotation(sample["hip"]) @ author.UP_BASIS),
                    "head": root @ author.bone_matrix(sample["head"], author.UP_BASIS)}
        hand_rotation = author.IDENTITY.slerp(sample["chest"], 1 - sample["guard"]) if track == "intro" else author.IDENTITY
        for side in ("left", "right"):
            for segment, start, end in (("upper_arm", "Shoulder", "Elbow"), ("forearm", "Elbow", "Glove"),
                                        ("thigh", "Hip", "Knee"), ("shin", "Knee", "Foot")):
                name = side + "_" + segment
                matrices[name] = root @ author.segment_matrix(rig, name, sample["points"][side + start], sample["points"][side + end])
            matrices[side + "_hand"] = root @ author.bone_matrix(sample["points"][side + "Glove"], author.blender_rotation(hand_rotation) @ author.UP_BASIS)
            matrices[side + "_foot"] = root @ author.bone_matrix(sample["points"][side + "Foot"],
                                                               author.blender_rotation(author.yaw_rotation(pose[side + "FootYaw"])) @ author.FOOT_BASIS)
        for bone in rig.pose.bones:
            parent = dict(parent_matrix=matrices[bone.parent.name], parent_matrix_local=bone.parent.bone.matrix_local) if bone.parent else {}
            bone.matrix_basis = bone.bone.convert_local_to_pose(matrices[bone.name], bone.bone.matrix_local, invert=True, **parent)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
            bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
    action = rig.animation_data.action
    action.name, action.use_fake_user = SCENES[track]["action"], True
    for curve in performance.action_curves(action):
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"


def author_scene(track):
    global contact_x
    config = SCENES[track]
    author.FPS, author.DURATION = FPS, config["duration"]
    author.FIRST_FRAME, author.LAST_FRAME = 1, 1 + round(FPS * config["duration"])
    author.RIG_NAME, author.STEPS = config["stem"] + "_Rig", ()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system, scene.unit_settings.scale_length = "METRIC", 1.0
    scene.render.fps, scene.render.fps_base = FPS, 1.0
    scene.frame_start, scene.frame_end = author.FIRST_FRAME, author.LAST_FRAME
    for name, time in config["beats"]:
        scene.timeline_markers.new(name, frame=1 + round(time * FPS))
    pose = author.standard_guard()
    points = author.facing_points(pose)
    rig = author.create_rig(pose, points, author.new_collection("01 | " + config["stem"] + " Editable FK"))
    rig.data.name = config["stem"] + "_Skeleton"
    performance.create_preview(rig, pose, points, author.new_collection("02 | Inherited Fighter Inspection Body"))
    if contact_x is None:
        contact_x = contact_geometry(rig, points)
    author.create_stage(author.new_collection("03 | Inspection Only - App Owns Venue and Props"))
    key_animation(track, rig, pose, points)
    scene["export_contract"] = "StoryIntroClip v1; evaluated FK, metres, +Y up/+Z forward; Blender (x,z,-y)"
    scene["duration_seconds"], scene["actor_role"] = config["duration"], track
    scene["app_props"] = "Corner stool; reward belt at 6.8; champion reveal and center placement at 8.0; gym and player hide at 16.0"
    scene["root_contract"] = "Absolute authored coordinates, never relative to live gameplay fighter" if track == "player" else "Root and heading zero; app owns placement"
    scene["player_spacing_metres"], scene["gym_cut_seconds"] = SPACING, GYM_CUT
    scene["ceremony_start_seconds"] = CEREMONY_START
    scene["glove_contact_world"] = json.dumps({"rival": [contact_x, CONTACT_HEIGHT + author.BASE_HEIGHT, CONTACT_FORWARD],
                                               "player": [-contact_x, CONTACT_HEIGHT + author.BASE_HEIGHT, SPACING - CONTACT_FORWARD],
                                               "seconds": [CONTACT_START, CONTACT_END]})
    rig["seating_validation"] = "Only neutral-relative torso height bounds differ before 4.3s; fixed limbs and foot penetration remain checked"
    scene.frame_set(1 if track == "ending" else scene.frame_end)
    return rig


def sample_surfaces(depsgraph):
    names = {"torso": ["Classic torso", "Classic red trunks", "Classic red waistband"],
             "left_foot": ["Classic left boot", "Classic left sole"],
             "right_foot": ["Classic right boot", "Classic right sole"]}
    for side in ("left", "right"):
        names[side + "_glove"] = ["Classic %s glove %s" % (side, part) for part in ("palm", "thumb", "cuff", "strap")]
    return {name: performance.evaluated_surface(objects, depsgraph) for name, objects in names.items()}


def export_evaluated(track, rig):
    config, scene = SCENES[track], bpy.context.scene
    action = rig.animation_data.action
    curves = list(performance.action_curves(action))
    if action.name != config["action"] or len(curves) < len(rig.pose.bones) * 7 or any(bone.constraints for bone in rig.pose.bones):
        raise ValueError("Expected named editable FK action without constraints")
    if (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base) != (1, 1 + round(FPS * config["duration"]), FPS, 1.0):
        raise ValueError("Unexpected frame range or sample rate")
    pose = author.standard_guard()
    lengths = author.limb_lengths(author.facing_points(pose))
    frames, paired, previous_feet = [], {}, None
    maximum_length_error = maximum_scale_error = maximum_plant_error = 0.0
    maximum_reconstruction_error = maximum_lift = 0.0
    for frame in range(scene.frame_start, scene.frame_end + 1):
        sample, points, feet, bones = author.read_evaluated_frame(rig, frame)
        time = sample["time"]
        if set(sample) != {"time", "root", "heading", "pose"} or set(sample["pose"]) != set(author.POINT_FIELDS + author.SCALAR_FIELDS):
            raise ValueError("StoryIntroClip v1 frame schema mismatch")
        if not all(isinstance(value, (int, float)) and math.isfinite(value) for value in author.numeric_values(sample)):
            raise ValueError("Nonfinite evaluated data")
        root = Vector(tuple(sample["root"][axis] for axis in ("x", "y", "z")))
        heading_error = abs(math.atan2(math.sin(sample["heading"] - config["heading"]), math.cos(sample["heading"] - config["heading"])))
        if (root - Vector(config["root"])).length > TOLERANCE or heading_error > TOLERANCE:
            raise ValueError("Authored fixed root/heading drift")
        for name, length in author.limb_lengths(points).items():
            maximum_length_error = max(maximum_length_error, abs(length - lengths[name]))
        for bone in bones:
            maximum_scale_error = max(maximum_scale_error, max(abs(value - 1) for value in bone.matrix.to_scale()))
        reconstructed_pose = {name: Vector(tuple(value[axis] for axis in ("x", "y", "z"))) if isinstance(value, dict) else value
                              for name, value in sample["pose"].items()}
        reconstructed = author.facing_points(reconstructed_pose)
        maximum_reconstruction_error = max(maximum_reconstruction_error, max((points[name] - reconstructed[name]).length for name in author.POINT_FIELDS))
        seated = track == "ending" and time < 4.3
        expected_torso = 1.55 - SEAT_DROP * (1 - author.ramp(time, 2.2, 4.3)) if seated else 1.55
        if abs(sample["pose"]["torsoY"] - expected_torso) > 0.01:
            raise ValueError("Torso outside intentional seated/standing bounds")
        if min(foot.y for foot in feet.values()) > author.CONTACT_HEIGHT + TOLERANCE:
            raise ValueError("Both feet airborne")
        for side, foot in feet.items():
            if foot.y < author.CONTACT_HEIGHT - TOLERANCE:
                raise ValueError("Foot below contact plane")
            maximum_lift = max(maximum_lift, foot.y - author.CONTACT_HEIGHT)
            swing = track == "ending" and side == "right" and previous_feet is not None and frames[-1]["time"] < 3.6 and time > 2.8
            if previous_feet is not None and not swing:
                maximum_plant_error = max(maximum_plant_error, (foot - previous_feet[side]).length)
        previous_feet = {side: foot.copy() for side, foot in feet.items()}
        surfaces = sample_surfaces(bpy.context.evaluated_depsgraph_get())
        for side in ("left", "right"):
            if surfaces[side + "_glove"][1].overlap(surfaces["torso"][1]):
                raise ValueError("%s %s glove/torso penetration at %.3fs" % (track, side, time))
            floor = author.CONTACT_HEIGHT - 0.1475
            if min(vertex.z for vertex in surfaces[side + "_foot"][0]) < floor - TOLERANCE:
                raise ValueError("Boot sole below support floor at %.3fs" % time)
        if track != "intro" and time < CEREMONY_START:
            world_points = {name: root + Vector((0, author.BASE_HEIGHT, 0)) + author.yaw_rotation(sample["heading"]) @ point
                            for name, point in points.items()}
            paired[frame] = (world_points, surfaces)
        sample["root"], sample["heading"] = author.vector_json(Vector(config["root"])), config["heading"]
        frames.append(sample)
    if max(maximum_length_error, maximum_scale_error, maximum_plant_error, maximum_reconstruction_error) > TOLERANCE:
        raise ValueError("Evaluated FK drift: limb=%g scale=%g plant=%g inverse-pose=%g" %
                         (maximum_length_error, maximum_scale_error, maximum_plant_error, maximum_reconstruction_error))
    if len(frames) != 1 + round(FPS * config["duration"]) or frames[0]["time"] != 0 or frames[-1]["time"] != config["duration"]:
        raise ValueError("Missing frame count or endpoints")
    if any(first["time"] >= second["time"] for first, second in zip(frames, frames[1:])):
        raise ValueError("Unsorted times")
    if track != "player":
        final = frames[-1]["pose"]
        errors = [abs(final[name] - pose[name]) for name in author.SCALAR_FIELDS]
        errors.extend((Vector(tuple(final[name][axis] for axis in ("x", "y", "z"))) - pose[name]).length for name in author.POINT_FIELDS)
        if max(errors) > TOLERANCE:
            raise ValueError("Final gameplay standard guard mismatch")
    print("%s: frames=%d duration=%.1fs fps=30 bones=%d curves=%d root=%s heading=%.9f" %
          (config["stem"], len(frames), config["duration"], len(rig.pose.bones), len(curves), config["root"], config["heading"]))
    print("MAX ERRORS: limb=%.9fm scale=%.9f planted=%.9fm inverse-pose=%.9fm lift=%.9fm" %
          (maximum_length_error, maximum_scale_error, maximum_plant_error, maximum_reconstruction_error, maximum_lift))
    print("FIXED LIMB LENGTHS: " + json.dumps(lengths, sort_keys=True))
    if track == "ending":
        for time in (0.0, 2.2, 4.3):
            sample = frames[round(time * FPS)]["pose"]
            print("SEATING: %.1fs torsoY=%.6fm hipsY=%.6f/%.6fm kneesY=%.6f/%.6fm" %
                  (time, sample["torsoY"], sample["leftHip"]["y"], sample["rightHip"]["y"], sample["leftKnee"]["y"], sample["rightKnee"]["y"]))
    return dict(version=1, duration=config["duration"], frames=frames), paired


def validate_companions(rival_frames, player_frames):
    minimum_gap, maximum_gap, maximum_target_error = math.inf, 0.0, 0.0
    contact_count = 0
    for frame in rival_frames:
        rival_points, rival = rival_frames[frame]
        player_points, player = player_frames[frame]
        time = (frame - 1) / FPS
        for first in ("torso", "left_foot", "right_foot", "left_glove", "right_glove"):
            for second in ("torso", "left_foot", "right_foot", "left_glove", "right_glove"):
                if rival[first][1].overlap(player[second][1]):
                    raise ValueError("Actor penetration %s/%s at %.3fs" % (first, second, time))
        if CONTACT_START <= time <= CONTACT_END:
            gap = min(player["left_glove"][1].find_nearest(vertex)[3] for vertex in rival["left_glove"][0])
            minimum_gap, maximum_gap = min(minimum_gap, gap), max(maximum_gap, gap)
            for points, target in ((rival_points, Vector((contact_x, CONTACT_HEIGHT + author.BASE_HEIGHT, CONTACT_FORWARD))),
                                   (player_points, Vector((-contact_x, CONTACT_HEIGHT + author.BASE_HEIGHT, SPACING - CONTACT_FORWARD)))):
                maximum_target_error = max(maximum_target_error, (points["leftGlove"] - target).length)
            contact_count += 1
    if contact_count != 1 + round((CONTACT_END - CONTACT_START) * FPS) or maximum_gap > 0.002 or maximum_target_error > TOLERANCE:
        raise ValueError("Missing physically matched continuous glove contact")
    print("COMPANIONS: %d ring frames; no torso/boot/glove intersection between actors" % len(rival_frames))
    print("CONTACT: left/left %.1f-%.1fs %d frames gap=%.9f..%.9fm target_error=%.9fm spacing=%.6fm" %
          (CONTACT_START, CONTACT_END, contact_count, minimum_gap, maximum_gap, maximum_target_error, SPACING))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--ending-only", action="store_true")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    root = arguments.output_root.expanduser().resolve()
    tracks = ("ending", "player") if arguments.ending_only else tuple(SCENES)
    targets = [(root / ("art/Story/" + config["stem"] + ".blend"), root / ("PixelBoxingIOS/Resources/" + config["resource"]))
               for config in (SCENES[track] for track in tracks)]
    existing = [path for pair in targets for path in pair if path.exists()]
    if existing and not arguments.overwrite:
        raise FileExistsError("Championship outputs exist; --overwrite backs up only selected resources")
    with tempfile.TemporaryDirectory(prefix="rival-championship-stage-") as staging:
        paired, staged = {}, []
        for track, (blend_path, json_path) in zip(tracks, targets):
            rig = author_scene(track)
            payload, paired[track] = export_evaluated(track, rig)
            staged_json = Path(staging) / json_path.name
            staged_json.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")
            if json.loads(staged_json.read_text(encoding="utf-8")) != payload:
                raise ValueError("Production JSON round-trip mismatch")
            staged_blend = Path(staging) / blend_path.name
            bpy.context.scene.frame_set(1 if track == "ending" else bpy.context.scene.frame_end)
            bpy.context.preferences.filepaths.save_version = 0
            bpy.ops.wm.save_as_mainfile(filepath=str(staged_blend), check_existing=False)
            staged.extend(((staged_blend, blend_path), (staged_json, json_path)))
        validate_companions(paired["ending"], paired["player"])
        if existing:
            backup = Path(tempfile.mkdtemp(prefix="rival-championship-own-backup-"))
            for path in existing:
                shutil.copy2(path, backup / path.name)
            print("OWN OUTPUT BACKUP: " + str(backup))
        for source, destination in staged:
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.replace(source, destination)
            print("OUTPUT: " + str(destination))


if __name__ == "__main__":
    main()