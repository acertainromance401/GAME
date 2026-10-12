"""Author classic RIVAL's hopeful pressure-win aftermath in Blender.

Regenerate from the workspace root:
/Applications/Blender.app/Contents/MacOS/Blender --background --python \
scripts/create_rival_pressure_win.py -- --output-root "$PWD" --overwrite

--export-existing preserves the editable source and exports its evaluated bones.
--preview-dir /tmp/rival-pressure-win-preview renders the saved source only.
No camera, stage, audio, or caption data is added to StoryIntroClip v1.
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
from mathutils import Quaternion, Vector
from mathutils.bvhtree import BVHTree

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import create_story_intro as author


FPS = 30
DURATION = 8.2
FIRST_FRAME = 1
LAST_FRAME = FIRST_FRAME + round(FPS * DURATION)
RIG_NAME = "RivalPressureWin_Rig"
ACTION_NAME = "RIVAL | Admiration - Three Claps - Quiet Practice - Hope | 8.2s"
CLAP_TIMES = (1.1, 1.7, 2.3)
CLAP_HALF_GAP = 0.1772
GYM_CUT = 3.2
STEPS = (
    ("left", 3.65, 4.10, 0.365),
    ("right", 4.35, 4.80, -0.315),
    ("left", 5.15, 5.60, 0.32),
    ("right", 5.85, 6.30, -0.28),
)
BEATS = (
    ("ATTEND | quiet, arms at ease", 0.0),
    ("APPLAUD | warm support", 0.5),
    ("CLAP 1 | glove contact", 1.1),
    ("CLAP 2 | glove contact", 1.7),
    ("CLAP 3 | glove contact", 2.3),
    ("SETTLE | hopeful chin and chest lift", 2.5),
    ("GYM CUT | app-owned location/camera/audio", GYM_CUT),
    ("PRACTICE | lead step, composed standard guard", 3.65),
    ("PRACTICE | rear step", 4.35),
    ("PRACTICE | lead returns", 5.15),
    ("PRACTICE | rear returns", 5.85),
    ("CAPTION | Someday, I'll be like you | app-owned", 6.2),
    ("HOLD | relaxed ready, no punches", 6.5),
    ("NOD | sincere resolve", 7.0),
    ("END | planted standard stance", DURATION),
)
TOLERANCE = 2e-5


def envelope(time, start, peak, end):
    return author.ramp(time, start, peak) * (1 - author.ramp(time, peak, end))


def clap_gap(time):
    keys = ((0.5, 0.36), (0.80, 0.36), (1.1, CLAP_HALF_GAP), (1.4, 0.36),
            (1.7, CLAP_HALF_GAP), (2.0, 0.36), (2.3, CLAP_HALF_GAP), (2.5, 0.36))
    for (start, first), (end, second) in zip(keys, keys[1:]):
        if time <= end:
            return first + (second - first) * author.ramp(time, start, end)
    return keys[-1][1]


def foot_path(side, time, final_pose):
    foot = final_pose[side + "Foot"].copy()
    for step_side, start, end, destination in STEPS:
        if step_side != side or time < start:
            continue
        if time >= end:
            foot.z = destination
            continue
        progress = (time - start) / (end - start)
        foot.z += (destination - foot.z) * author.smooth(progress)
        foot.y += 0.016 * math.sin(math.pi * progress) ** 2
        break
    return foot


def authored_sample(time, final_pose, final_points, lengths):
    applause = author.ramp(time, 0.5, 0.85) * (1 - author.ramp(time, 2.5, 3.10))
    ready = author.ramp(time, GYM_CUT, 4.25)
    hope = envelope(time, 2.55, 2.95, 3.65)
    nod = envelope(time, 7.0, 7.25, 7.65)
    breathing = 0.004 * math.sin(math.tau * time / 3.1) * (1 - author.ramp(time, 7.65, DURATION))
    weight = 0.0
    for side, start, end, _ in STEPS:
        if start < time < end:
            weight = (-1 if side == "left" else 1) * 0.012 * math.sin(math.pi * (time - start) / (end - start)) ** 2
    torso_y = 1.55 + breathing + 0.008 * hope - 0.004 * nod
    yaw = final_pose["torsoYaw"] * ready
    pitch = -0.01 + (final_pose["torsoPitch"] + 0.01) * ready - 0.035 * hope + 0.045 * nod
    lean = final_pose["torsoLean"] * ready + weight
    chest = author.torso_rotation(yaw, pitch, lean)
    pelvis = author.yaw_rotation(final_pose["hipYaw"])
    pivot = Vector((0, torso_y, 0))
    points = {}
    for side, sign in (("left", 1), ("right", -1)):
        shoulder = author.transform_point(final_pose[side + "Shoulder"] + Vector((0, torso_y - 1.55, 0)), pivot, chest)
        resting_hand = author.transform_point(Vector((sign * 0.58, 1.12 + torso_y - 1.55, 0.18)), pivot, chest)
        clapping_hand = Vector((sign * clap_gap(time), 1.70 + breathing, 0.62))
        ready_hand = author.transform_point(final_pose[side + "Glove"] + Vector((0, torso_y - 1.55, 0)), pivot, chest)
        hand = resting_hand.lerp(clapping_hand, applause)
        hand.z += 0.16 * math.sin(math.pi * applause)
        entry_axis, ready_axis = hand - shoulder, ready_hand - shoulder
        arc = author.IDENTITY.slerp(entry_axis.normalized().rotation_difference(ready_axis.normalized()), ready)
        radius = entry_axis.length + (ready_axis.length - entry_axis.length) * ready
        hand = shoulder + (arc @ entry_axis.normalized()) * radius
        resting_pole = Vector((sign * 0.62, 1.45 + breathing, 0.04))
        clap_pole = Vector((sign * 0.56, 1.30 + breathing, 0.31))
        ready_pole = author.transform_point(final_pose[side + "Elbow"] + Vector((0, torso_y - 1.55, 0)), pivot, chest)
        pole = resting_pole.lerp(clap_pole, applause).lerp(ready_pole, ready)
        elbow, solved_hand = author.solve_limb(shoulder, hand, pole, lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        if (solved_hand - hand).length > TOLERANCE:
            raise ValueError("Unreachable glove: %s at %.3fs" % (side, time))
        hip = author.transform_point(final_pose[side + "Hip"], Vector((0, 0.86, 0)), pelvis)
        foot = foot_path(side, time, final_pose)
        knee, solved_foot = author.solve_limb(hip, foot, final_points[side + "Knee"], lengths[side + "_thigh"], lengths[side + "_shin"])
        if (solved_foot - foot).length > TOLERANCE:
            raise ValueError("Unreachable planted foot: %s at %.3fs" % (side, time))
        points.update({side + "Shoulder": shoulder, side + "Elbow": elbow,
                       side + "Glove": solved_hand, side + "Hip": hip,
                       side + "Knee": knee, side + "Foot": solved_foot})
    bob = breathing + 0.008 * hope - 0.012 * nod
    head = author.transform_point(Vector((0, 2.28 + bob, 0.04)), pivot, author.IDENTITY.slerp(chest, 0.55))
    return dict(root=Vector((0, 0, 0)), heading=0.0, chest=chest, hip=pelvis,
                torso_y=torso_y, head=head, lean=lean, points=points)


def wrist_rotation(points, side):
    return Vector((0, -1, 0)).rotation_difference((points[side + "Elbow"] - points[side + "Glove"]).normalized())


def key_animation(rig, final_pose, final_points):
    lengths = author.limb_lengths(final_points)
    scene = bpy.context.scene
    for frame in range(FIRST_FRAME, LAST_FRAME + 1):
        scene.frame_set(frame)
        sample = authored_sample((frame - FIRST_FRAME) / FPS, final_pose, final_points, lengths)
        points = sample["points"]
        matrices = {"CTRL_root": author.bone_matrix(sample["root"], author.UP_BASIS),
                    "CTRL_chest": author.bone_matrix(Vector((0, sample["torso_y"], 0)), author.blender_rotation(sample["chest"]) @ author.UP_BASIS),
                    "CTRL_pelvis": author.bone_matrix(Vector((0, 0.86, 0)), author.blender_rotation(sample["hip"]) @ author.UP_BASIS),
                    "head": author.bone_matrix(sample["head"], author.blender_rotation(Quaternion(Vector((0, 0, 1)), -sample["lean"] * 0.45)) @ author.UP_BASIS)}
        for side in ("left", "right"):
            for segment, start, end in (("upper_arm", "Shoulder", "Elbow"), ("forearm", "Elbow", "Glove"),
                                        ("thigh", "Hip", "Knee"), ("shin", "Knee", "Foot")):
                name = side + "_" + segment
                matrices[name] = author.segment_matrix(rig, name, points[side + start], points[side + end])
            matrices[side + "_hand"] = author.bone_matrix(points[side + "Glove"], author.blender_rotation(wrist_rotation(points, side)) @ author.UP_BASIS)
            matrices[side + "_foot"] = author.bone_matrix(points[side + "Foot"], author.blender_rotation(author.yaw_rotation(final_pose[side + "FootYaw"])) @ author.FOOT_BASIS)
        for bone in rig.pose.bones:
            parent = dict(parent_matrix=matrices[bone.parent.name], parent_matrix_local=bone.parent.bone.matrix_local) if bone.parent else {}
            bone.matrix_basis = bone.bone.convert_local_to_pose(matrices[bone.name], bone.bone.matrix_local, invert=True, **parent)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
            bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
    action = rig.animation_data.action
    action.name = ACTION_NAME
    for curve in action_curves(action):
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"


def action_curves(action):
    if hasattr(action, "layers") and action.layers:
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    bag = strip.channelbag(slot)
                    if bag is not None:
                        yield from bag.fcurves
    else:
        yield from action.fcurves


def round_piece(name, rig, collection, bone, center, radius, height, surface, rotation=None, scale=(1, 1, 1), capsule=True):
    half_stem = max(0.0, height * 0.5 - radius) if capsule else height * 0.5
    rings = []
    if capsule:
        for index in range(7):
            angle = -math.pi * 0.5 + index * math.pi / 12
            rings.append((radius * math.cos(angle), -half_stem + radius * math.sin(angle)))
        for index in range(7):
            angle = index * math.pi / 12
            rings.append((radius * math.cos(angle), half_stem + radius * math.sin(angle)))
    else:
        rings = [(radius, -half_stem), (radius, half_stem)]
    vertices, faces = [], []
    orientation = rotation if rotation is not None else author.IDENTITY
    for radial, vertical in rings:
        for index in range(24):
            angle = math.tau * index / 24
            local = Vector((radial * math.cos(angle) * scale[0], vertical * scale[1], radial * math.sin(angle) * scale[2]))
            vertices.append(author.SCENE_TO_BLENDER @ (center + orientation @ local))
    for row in range(len(rings) - 1):
        for index in range(24):
            following = (index + 1) % 24
            faces.append((row * 24 + index, row * 24 + following, (row + 1) * 24 + following, (row + 1) * 24 + index))
    faces.extend((tuple(reversed(range(24))), tuple((len(rings) - 1) * 24 + index for index in range(24))))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], [tuple(reversed(face)) for face in faces])
    mesh.materials.append(surface)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.matrix_world = rig.matrix_world.copy()
    obj.vertex_groups.new(name=bone).add(list(range(len(vertices))), 1.0, "REPLACE")
    obj.modifiers.new("Editable skeleton attachment", "ARMATURE").object = rig
    return obj


def create_preview(rig, pose, points, collection):
    skin = author.material("Classic RIVAL | Skin", (0.74, 0.42, 0.26), 0.62)
    trunks = author.material("Classic RIVAL | Red trunks", (0.52, 0.025, 0.07), 0.34)
    gloves = author.material("Classic RIVAL | Red gloves", (0.68, 0.035, 0.11), 0.24)
    accent = author.material("Classic RIVAL | Dark red wrist straps", (0.37, 0.02, 0.06), 0.42)
    dark = author.material("Classic RIVAL | Soles and eyes", (0.025, 0.035, 0.055), 0.75)
    for surface, metallic in ((trunks, 0.08), (gloves, 0.10), (accent, 0.04)):
        surface.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = metallic
    chest = author.torso_rotation(pose["torsoYaw"], pose["torsoPitch"], pose["torsoLean"])
    hips = author.yaw_rotation(pose["hipYaw"])
    round_piece("Classic torso", rig, collection, "CTRL_chest", Vector((0, 1.55, 0)), 0.4, 0.94, skin, chest, (1.08, 1, 0.72))
    author.preview_piece("Classic red trunks", rig, collection, "CTRL_pelvis", Vector((0, 0.86, 0)), (0.84, 0.56, 0.45), trunks, "box", hips)
    author.preview_piece("Classic red waistband", rig, collection, "CTRL_pelvis", Vector((0, 1.08, 0)), (0.88, 0.59, 0.13), trunks, "box", hips)
    head_rotation = author.IDENTITY.slerp(chest, 0.55)
    head = author.SCENE_TO_BLENDER.transposed() @ rig.data.bones["head"].head_local
    neck = author.transform_point(Vector((0, 2.02, 0.015)), Vector((0, 1.55, 0)), head_rotation)
    round_piece("Classic neck", rig, collection, "head", neck, 0.15, 0.24, skin, head_rotation, capsule=False)
    author.preview_piece("Classic bald head", rig, collection, "head", head, (0.516, 0.528, 0.648), skin)
    for sign in (-1, 1):
        author.preview_piece("Classic eye %d" % sign, rig, collection, "head", head + Vector((sign * 0.11, 0.06, 0.225)), (0.052, 0.052, 0.052), dark)
    for side, sign in (("left", 1), ("right", -1)):
        author.preview_piece("Classic %s shoulder" % side, rig, collection, side + "_upper_arm", points[side + "Shoulder"], (0.35, 0.35, 0.35), skin)
        for segment, start, end, radius in (("upper_arm", "Shoulder", "Elbow", 0.14), ("forearm", "Elbow", "Glove", 0.12),
                                           ("thigh", "Hip", "Knee", 0.17), ("shin", "Knee", "Foot", 0.14)):
            origin, target = points[side + start], points[side + end]
            if segment == "forearm":
                target = target + (origin - target).normalized() * 0.29
            if segment == "shin":
                target = target + Vector((0, 0.10, 0))
            direction = target - origin
            round_piece("Classic %s %s" % (side, segment), rig, collection, side + "_" + segment,
                        (origin + target) * 0.5, radius, direction.length, skin,
                        Vector((0, 1, 0)).rotation_difference(direction.normalized()))
        hand = points[side + "Glove"]
        author.preview_piece("Classic %s glove palm" % side, rig, collection, side + "_hand", hand + Vector((0, 0, 0.025)), (0.3672, 0.432, 0.3672), gloves)
        round_piece("Classic %s glove thumb" % side, rig, collection, side + "_hand", hand + Vector((-0.13 * sign, -0.015, 0.085)), 0.065, 0.20, gloves, Quaternion(Vector((0, 0, 1)), 0.55 * sign))
        round_piece("Classic %s glove cuff" % side, rig, collection, side + "_hand", hand + Vector((0, -0.18, 0)), 0.135, 0.22, gloves, capsule=False)
        round_piece("Classic %s glove strap" % side, rig, collection, side + "_hand", hand + Vector((0, -0.155, 0)), 0.142, 0.055, accent, capsule=False)
        foot = points[side + "Foot"]
        rotation = author.yaw_rotation(pose[side + "FootYaw"])
        author.preview_piece("Classic %s boot" % side, rig, collection, side + "_foot", foot + rotation @ Vector((0, 0, 0.08)), (0.31, 0.48, 0.22), trunks, "box", rotation)
        author.preview_piece("Classic %s sole" % side, rig, collection, side + "_foot", foot + rotation @ Vector((0, -0.12, 0.08)), (0.33, 0.51, 0.055), dark, "box", rotation)


def configure_helpers():
    author.FPS, author.DURATION = FPS, DURATION
    author.FIRST_FRAME, author.LAST_FRAME = FIRST_FRAME, LAST_FRAME
    author.RIG_NAME, author.STEPS = RIG_NAME, STEPS


def author_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system, scene.unit_settings.scale_length = "METRIC", 1.0
    scene.render.fps, scene.render.fps_base = FPS, 1.0
    scene.frame_start, scene.frame_end = FIRST_FRAME, LAST_FRAME
    for name, time in BEATS:
        scene.timeline_markers.new(name, frame=FIRST_FRAME + round(time * FPS))
    pose = author.standard_guard()
    points = author.facing_points(pose)
    rig = author.create_rig(pose, points, author.new_collection("01 | Classic RIVAL Editable FK"))
    rig.data.name = "RivalPressureWin_Skeleton"
    del rig["walk_steps"]
    rig["practice_steps"] = json.dumps(STEPS)
    rig["anatomy_basis"] = "Fixed joint/contact lengths from final classic standard guard"
    rig["aftermath_mood"] = "Pure admiration: supportive, sincere, hopeful; not obsession"
    create_preview(rig, pose, points, author.new_collection("02 | Classic RIVAL Inspection Body"))
    author.create_stage(author.new_collection("03 | Inspection Only - App Owns Stage Cut"))
    for name in ("Camera_ThreeQuarter", "Camera_Front", "Camera_Side"):
        camera = bpy.data.objects[name]
        target = Vector((0, 0, 1.45))
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 3.8
    scene.world.name = "RIVAL Hopeful Inspection World"
    key_animation(rig, pose, points)
    scene["aftermath_duration"] = DURATION
    scene["gym_cut_seconds"] = GYM_CUT
    scene["caption_seconds"] = "6.2-8.2 | Someday, I'll be like you | app-owned"
    scene["export_contract"] = "StoryIntroClip v1; metres, +Y up/+Z forward/+X left; evaluated FK only"
    scene["stage_note"] = "Inspection floor only. Ringside before 3.2s; separate empty gym from 3.2s, app-owned. No root teleport."
    scene.frame_set(LAST_FRAME)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    return rig


def evaluated_surface(names, depsgraph):
    vertices, polygons = [], []
    for name in names:
        evaluated = bpy.data.objects[name].evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        base = len(vertices)
        vertices.extend(evaluated.matrix_world @ vertex.co for vertex in mesh.vertices)
        polygons.extend(tuple(base + index for index in polygon.vertices) for polygon in mesh.polygons)
        evaluated.to_mesh_clear()
    return vertices, BVHTree.FromPolygons(vertices, polygons)


def inspect_glove_contact(time):
    bpy.context.scene.frame_set(FIRST_FRAME + round(time * FPS))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    gloves = {side: evaluated_surface(["Classic %s glove %s" % (side, part) for part in ("palm", "thumb", "cuff", "strap")], depsgraph)
              for side in ("left", "right")}
    gap = min(gloves["right"][1].find_nearest(point)[3] for point in gloves["left"][0])
    overlaps = len(gloves["left"][1].overlap(gloves["right"][1]))
    torso = evaluated_surface(["Classic torso"], depsgraph)[1]
    torso_overlap = any(surface[1].overlap(torso) for surface in gloves.values())
    print("GLOVE SURFACES: time=%.3fs gap=%.6fm intersecting_triangles=%d torso_intersection=%s" % (time, gap, overlaps, torso_overlap))
    if gap > 0.002 or overlaps or torso_overlap:
        raise ValueError("Clap must touch within 2mm without glove/torso interpenetration")


def export_evaluated(rig):
    scene = bpy.context.scene
    action = rig.animation_data.action if rig.animation_data else None
    if action is None or action.name != ACTION_NAME:
        raise ValueError("Missing named RIVAL aftermath FK Action")
    curves = list(action_curves(action))
    if len(curves) < len(rig.pose.bones) * 7 or any(bone.constraints for bone in rig.pose.bones):
        raise ValueError("Expected editable keyed FK location/quaternion channels, without runtime IK")
    if (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base) != (FIRST_FRAME, LAST_FRAME, FPS, 1.0):
        raise ValueError("Source must have 247 samples over 246 intervals at exactly 30fps")
    reference = author.standard_guard()
    lengths = author.limb_lengths(author.facing_points(reference))
    frames, measured = [], []
    previous_feet = None
    maximum_length_error = maximum_scale_error = maximum_plant_error = maximum_cut_delta = 0.0
    maximum_lift = 0.0
    for frame in range(FIRST_FRAME, LAST_FRAME + 1):
        sample, positions, feet, bones = author.read_evaluated_frame(rig, frame)
        if set(sample) != {"time", "root", "heading", "pose"} or set(sample["pose"]) != set(author.POINT_FIELDS + author.SCALAR_FIELDS):
            raise ValueError("StoryIntroClip v1 schema mismatch")
        if not all(isinstance(value, (int, float)) and math.isfinite(value) for value in author.numeric_values(sample)):
            raise ValueError("Nonfinite export at frame %d" % frame)
        if frames and sample["time"] <= frames[-1]["time"]:
            raise ValueError("Unsorted sample times")
        if Vector(tuple(sample["root"].values())).length > TOLERANCE or abs(sample["heading"]) > TOLERANCE:
            raise ValueError("This planted scene must keep root/heading zero, including the gym cut")
        for name, length in author.limb_lengths(positions).items():
            maximum_length_error = max(maximum_length_error, abs(length - lengths[name]))
        for bone in bones:
            maximum_scale_error = max(maximum_scale_error, max(abs(value - 1) for value in bone.matrix.to_scale()))
        depsgraph = bpy.context.evaluated_depsgraph_get()
        torso_surface = evaluated_surface(["Classic torso"], depsgraph)[1]
        for side in ("left", "right"):
            glove_surface = evaluated_surface(["Classic %s glove %s" % (side, part) for part in ("palm", "thumb", "cuff", "strap")], depsgraph)[1]
            if glove_surface.overlap(torso_surface):
                raise ValueError("Glove/torso intersection: %s at %.3fs" % (side, sample["time"]))
        if min(foot.y for foot in feet.values()) > author.CONTACT_HEIGHT + TOLERANCE:
            raise ValueError("Both feet airborne at %.3fs" % sample["time"])
        for side in ("left", "right"):
            if feet[side].y < author.CONTACT_HEIGHT - TOLERANCE:
                raise ValueError("Foot below contact plane")
            maximum_lift = max(maximum_lift, feet[side].y - author.CONTACT_HEIGHT)
            swing = frames and any(step_side == side and frames[-1]["time"] < end and sample["time"] > start for step_side, start, end, _ in STEPS)
            if previous_feet is not None and not swing:
                maximum_plant_error = max(maximum_plant_error, (feet[side] - previous_feet[side]).length)
            elbow_local = author.transform_point(positions[side + "Elbow"], Vector((0, sample["pose"]["torsoY"], 0)),
                                                 author.torso_rotation(sample["pose"]["torsoYaw"], sample["pose"]["torsoPitch"], sample["pose"]["torsoLean"]).inverted())
            if elbow_local.x * (1 if side == "left" else -1) < 0.20:
                raise ValueError("Crossed or reversed elbow at %.3fs" % sample["time"])
        if measured and abs(sample["time"] - GYM_CUT) < 0.07:
            maximum_cut_delta = max(maximum_cut_delta, max((positions[field] - measured[-1][field]).length for field in author.POINT_FIELDS))
        measured.append({name: point.copy() for name, point in positions.items()})
        previous_feet = {side: foot.copy() for side, foot in feet.items()}
        sample["root"], sample["heading"] = dict(x=0.0, y=0.0, z=0.0), 0.0
        frames.append(sample)
    if max(maximum_length_error, maximum_scale_error, maximum_plant_error) > TOLERANCE:
        raise ValueError("Evaluated FK drift: limb=%g scale=%g plant=%g" % (maximum_length_error, maximum_scale_error, maximum_plant_error))
    if maximum_lift > 0.016 + TOLERANCE or maximum_cut_delta > 0.035:
        raise ValueError("Step too high or pose discontinuity at gym cut")
    if len(frames) != 247 or frames[0]["time"] != 0 or frames[-1]["time"] != DURATION:
        raise ValueError("Missing prescribed count/time endpoints")
    final = frames[-1]["pose"]
    errors = [abs(final[field] - reference[field]) for field in author.SCALAR_FIELDS]
    errors.extend((Vector(tuple(final[field].values())) - reference[field]).length for field in author.POINT_FIELDS)
    if max(errors) > TOLERANCE:
        raise ValueError("Final classic guard differs from invariant anatomy basis")
    contacts = []
    for time in CLAP_TIMES:
        index = round(time * FPS)
        distance = (measured[index]["leftGlove"] - measured[index]["rightGlove"]).length
        neighbors = [(measured[index + offset]["leftGlove"] - measured[index + offset]["rightGlove"]).length for offset in (-1, 1)]
        if abs(distance - 2 * CLAP_HALF_GAP) > TOLERANCE or any(neighbor <= distance for neighbor in neighbors):
            raise ValueError("Missing controlled clap minimum at %.3fs" % time)
        inspect_glove_contact(time)
        contacts.append((frames[index]["time"], distance))
    print("EVALUATED RIVAL: frames=%d duration=%.3fs fps=%d bones=%d curves=%d keys=%d" %
          (len(frames), DURATION, FPS, len(rig.pose.bones), len(curves), sum(len(curve.keyframe_points) for curve in curves)))
    print("ACTION: " + action.name)
    print("MAX ERRORS: limb=%.9fm scale=%.9f planted=%.9fm cut_delta=%.6fm lift=%.6fm; no double airborne" %
          (maximum_length_error, maximum_scale_error, maximum_plant_error, maximum_cut_delta, maximum_lift))
    print("CLAPS (time, joint separation metres): " + str(contacts))
    print("GYM CUT: %.3fs frame=%d; root/heading zero throughout" % (GYM_CUT, FIRST_FRAME + round(GYM_CUT * FPS)))
    print("FIXED LIMB LENGTHS (m): " + json.dumps(lengths, sort_keys=True))
    return dict(version=1, duration=DURATION, frames=frames)


def render_previews(directory):
    directory.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    saved = scene.frame_current, scene.camera, scene.render.filepath
    scene.render.resolution_x, scene.render.resolution_y = 800, 600
    scene.render.image_settings.file_format = "PNG"
    for label, time, camera in (("quiet", 0, "Front"), ("open_clap", 1.4, "Front"),
                                ("clap1", 1.1, "Front"), ("clap2", 1.7, "ThreeQuarter"),
                                ("clap3", 2.3, "Side"), ("hope", 2.95, "ThreeQuarter"),
                                ("gym_cut", GYM_CUT, "Front"), ("lead_step", 3.88, "ThreeQuarter"),
                                ("rear_step", 4.58, "Side"), ("nod", 7.25, "ThreeQuarter"),
                                ("ready", DURATION, "Front"), ("ready_side", DURATION, "Side")):
        scene.frame_set(FIRST_FRAME + round(time * FPS))
        scene.camera = bpy.data.objects["Camera_" + camera]
        scene.render.filepath = str(directory / (label + ".png"))
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(scene.render.filepath, check_existing=False)
        pixels = image.pixels[:]
        luminance = [sum(pixels[index:index + 3]) / 3 for index in range(0, len(pixels), 4 * 97)]
        if tuple(image.size) != (800, 600) or not luminance or max(luminance) - min(luminance) < 0.03:
            raise ValueError("Blank or invalid saved PNG: " + label)
        print("RENDER PIXELS: %s 800x600 luminance_range=%.4f" % (label, max(luminance) - min(luminance)))
        bpy.data.images.remove(image)
    scene.frame_set(saved[0])
    scene.camera, scene.render.filepath = saved[1:]
    print("SAVED SOURCE PREVIEWS: " + str(directory))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--overwrite", action="store_true", help="Back up and replace only this scene's own output(s)")
    parser.add_argument("--export-existing", action="store_true", help="Export evaluated saved FK edits without replacing the .blend")
    parser.add_argument("--preview-dir", type=Path, help="Inspection renders outside the repository/output root")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    root = arguments.output_root.expanduser().resolve()
    blend_path = root / "art/Story/RivalPressureWin.blend"
    json_path = root / "PixelBoxingIOS/Resources/story_rival_pressure_win.json"
    targets = (json_path,) if arguments.export_existing else (blend_path, json_path)
    if any(path.exists() for path in targets) and not arguments.overwrite:
        raise FileExistsError("RIVAL aftermath outputs exist; use --overwrite for backups of only these outputs")
    preview_dir = arguments.preview_dir.expanduser().resolve() if arguments.preview_dir else None
    workspace = Path(__file__).resolve().parents[1]
    if preview_dir is not None and any(preview_dir == owner or owner in preview_dir.parents for owner in (workspace, root)):
        raise ValueError("Inspection renders must be outside the workspace/output root")
    configure_helpers()
    if arguments.export_existing:
        bpy.ops.wm.open_mainfile(filepath=str(blend_path))
        rig = bpy.data.objects.get(RIG_NAME)
        if rig is None or rig.type != "ARMATURE":
            raise ValueError("Saved source lacks the RIVAL aftermath armature")
    else:
        rig = author_scene()
    payload = export_evaluated(rig)
    with tempfile.TemporaryDirectory(prefix="rival-pressure-win-stage-") as staging:
        staged_json = Path(staging) / json_path.name
        staged_json.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")
        if json.loads(staged_json.read_text(encoding="utf-8")) != payload:
            raise ValueError("Production JSON round-trip mismatch")
        if not arguments.export_existing:
            staged_blend = Path(staging) / blend_path.name
            bpy.context.scene.frame_set(LAST_FRAME)
            bpy.context.preferences.filepaths.save_version = 0
            bpy.ops.wm.save_as_mainfile(filepath=str(staged_blend), check_existing=False)
        existing = [path for path in targets if path.exists()]
        if existing:
            backup = Path(tempfile.mkdtemp(prefix="rival-pressure-win-backup-"))
            for path in existing:
                shutil.copy2(path, backup / path.name)
            print("OWN OUTPUT BACKUP: " + str(backup))
        json_path.parent.mkdir(parents=True, exist_ok=True)
        if not arguments.export_existing:
            blend_path.parent.mkdir(parents=True, exist_ok=True)
            os.replace(staged_blend, blend_path)
        os.replace(staged_json, json_path)
    if preview_dir is not None:
        bpy.ops.wm.open_mainfile(filepath=str(blend_path))
        render_previews(preview_dir)
    print("BLENDER SOURCE: " + str(blend_path))
    print("JSON RESOURCE: " + str(json_path))


if __name__ == "__main__":
    main()