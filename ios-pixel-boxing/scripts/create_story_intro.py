"""Author an editable RIVAL pressure intro and export evaluated Blender bones.

Run with Blender, not the workspace Python interpreter. No external packages.
"""

import argparse
import datetime
import json
import math
import os
from pathlib import Path
import shutil
import sys
import tempfile

import bpy
from mathutils import Matrix, Quaternion, Vector


FPS = 30
DURATION = 6.2
FIRST_FRAME = 1
LAST_FRAME = FIRST_FRAME + round(FPS * DURATION)
RIG_NAME = "PressureIntro_Rig"
BASE_HEIGHT = 0.13
CONTACT_HEIGHT = BASE_HEIGHT + 0.14
SCENE_TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
UP_BASIS = Vector((0, 0, 1)).to_track_quat("Y", "Z").to_matrix()
FOOT_BASIS = Vector((0, -1, 0)).to_track_quat("Y", "Z").to_matrix()
IDENTITY = Quaternion((1, 0, 0, 0))
POINT_FIELDS = (
    "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
    "leftGlove", "rightGlove", "leftHip", "rightHip",
    "leftKnee", "rightKnee", "leftFoot", "rightFoot",
)
SCALAR_FIELDS = (
    "torsoY", "torsoYaw", "torsoPitch", "torsoLean", "hipYaw", "headBob",
    "leftFootYaw", "rightFootYaw", "leftFootPitch", "rightFootPitch",
)
STEPS = (
    ("right", 0.12, 0.64, -1.44),
    ("left", 0.68, 1.20, -0.94),
    ("right", 1.24, 1.76, -0.84),
    ("left", 1.80, 2.32, -0.34),
    ("right", 2.36, 2.88, -0.28),
    ("left", 2.92, 3.44, 0.32),
)
INITIAL_FEET = {"left": Vector((0.31, CONTACT_HEIGHT, -1.54)),
                "right": Vector((-0.32, CONTACT_HEIGHT, -2.04))}


def smooth(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def ramp(time, start, end):
    return smooth((time - start) / (end - start))


def yaw_rotation(angle):
    return Quaternion(Vector((0, 1, 0)), angle)


def torso_rotation(yaw, pitch, lean):
    return (Quaternion(Vector((0, 0, 1)), lean)
            @ yaw_rotation(yaw) @ Quaternion(Vector((1, 0, 0)), pitch))


def blender_rotation(rotation):
    return SCENE_TO_BLENDER @ rotation.to_matrix() @ SCENE_TO_BLENDER.transposed()


def scene_rotation(rotation):
    return (SCENE_TO_BLENDER.transposed() @ rotation
            @ SCENE_TO_BLENDER).to_quaternion()


def transform_point(point, pivot, rotation):
    return pivot + rotation @ (point - pivot)


def standard_guard():
    """FightPose.neutral(stride: 0, style: .standard), then applyGuard(1)."""
    pivot = Vector((0, 1.55, 0))
    neutral_rotation = torso_rotation(-0.40, -0.06, 0)
    head = transform_point(Vector((0, 2.28, 0.04)), pivot,
                           IDENTITY.slerp(neutral_rotation, 0.55))
    pose = dict(torsoY=1.55, torsoYaw=-0.40, torsoPitch=-0.06,
                torsoLean=-0.015, hipYaw=-0.30, headBob=0.0,
                leftFootYaw=-0.18, rightFootYaw=-0.72,
                leftFootPitch=0.0, rightFootPitch=0.0)
    pose.update(leftShoulder=Vector((0.39, 1.82, 0)),
                rightShoulder=Vector((-0.39, 1.82, 0)),
                leftHip=Vector((0.22, 0.86, 0)),
                rightHip=Vector((-0.22, 0.86, 0)),
                leftFoot=Vector((0.31, 0.14, 0.32)),
                rightFoot=Vector((-0.32, 0.14, -0.28)))
    offsets = {"leftElbow": (0.40, -0.66, 0.20),
               "rightElbow": (-0.40, -0.66, 0.12),
               "leftGlove": (0.20, -0.10, 0.34),
               "rightGlove": (-0.20, -0.10, 0.32)}
    for field, offset in offsets.items():
        pose[field] = transform_point(head + Vector(offset), pivot,
                                      neutral_rotation.inverted())
    for side in ("left", "right"):
        hip = transform_point(pose[side + "Hip"], Vector((0, 0.86, 0)),
                              yaw_rotation(pose["hipYaw"]))
        pose[side + "Knee"] = ((hip + pose[side + "Foot"] + Vector((0, 0.16, 0))) * 0.5
                               + yaw_rotation(pose[side + "FootYaw"])
                               @ Vector((0, -0.07, 0.12)))
    return pose


def facing_points(pose):
    points = {}
    chest = torso_rotation(pose["torsoYaw"], pose["torsoPitch"], pose["torsoLean"])
    for field in POINT_FIELDS:
        if any(field.endswith(part) for part in ("Shoulder", "Elbow", "Glove")):
            points[field] = transform_point(pose[field], Vector((0, pose["torsoY"], 0)), chest)
        elif field.endswith("Hip"):
            points[field] = transform_point(pose[field], Vector((0, 0.86, 0)),
                                           yaw_rotation(pose["hipYaw"]))
        else:
            points[field] = pose[field].copy()
    return points


def limb_lengths(points):
    lengths = {}
    for side in ("left", "right"):
        for segment, start, end in (("upper_arm", "Shoulder", "Elbow"),
                                    ("forearm", "Elbow", "Glove"),
                                    ("thigh", "Hip", "Knee"),
                                    ("shin", "Knee", "Foot")):
            lengths[side + "_" + segment] = (points[side + end] - points[side + start]).length
    return lengths


def solve_limb(origin, target, pole, upper, lower):
    delta = target - origin
    distance = delta.length
    if distance < 1e-8:
        raise ValueError("Degenerate limb target")
    axis = delta / distance
    reach = min(upper + lower - 1e-7, max(abs(upper - lower) + 1e-7, distance))
    along = (upper * upper - lower * lower + reach * reach) / (2 * reach)
    height = math.sqrt(max(0.0, upper * upper - along * along))
    bend = pole - origin
    bend -= axis * bend.dot(axis)
    if bend.length < 1e-7:
        bend = axis.cross(Vector((1, 0, 0)))
        if bend.length < 1e-7:
            bend = axis.cross(Vector((0, 0, 1)))
    bend.normalize()
    return origin + axis * along + bend * height, origin + axis * reach


def foot_path(side, time):
    position = INITIAL_FEET[side].copy()
    yaw = 0.12
    pitch = 0.0
    for step_side, start, end, destination in STEPS:
        if step_side != side or time < start:
            continue
        if time >= end:
            position.z = destination
            if destination == (-0.28 if side == "right" else 0.32):
                yaw = -0.72 if side == "right" else -0.18
            continue
        progress = (time - start) / (end - start)
        position.z += (destination - position.z) * smooth(progress)
        position.y += 0.095 * math.sin(math.pi * progress) ** 2
        pitch = 0.20 * math.sin(2 * math.pi * progress) * math.sin(math.pi * progress)
        if destination == (-0.28 if side == "right" else 0.32):
            yaw += ((-0.72 if side == "right" else -0.18) - yaw) * smooth(progress)
        break
    return position, yaw, pitch


def authored_sample(time, final_pose, final_points, lengths):
    feet = {side: foot_path(side, time) for side in ("left", "right")}
    midpoint = (feet["left"][0].z + feet["right"][0].z) * 0.5
    travel = max(0.0, min(1.0, (midpoint + 1.79) / 1.81))
    root = Vector((0, 0, -1.8 + 1.8 * travel))
    for _, start, end, _ in STEPS:
        if start < time < end:
            root.y = -0.018 * math.sin(math.pi * (time - start) / (end - start)) ** 2
    root.y -= 0.014 * ramp(time, 2.92, 3.40) * (1 - ramp(time, 4.00, 4.90))
    heading = 0.20 * (1 - ramp(time, 4.05, 4.85))
    turn = ramp(time, 4.10, 4.90)
    guard = ramp(time, 4.72, 5.80)
    glance = ramp(time, 3.60, 3.88) * (1 - ramp(time, 3.95, 4.20))
    walking = 1 - ramp(time, 3.20, 3.60)
    cycle = math.sin(2 * math.pi * (time - 0.12) / 1.12) * walking
    yaw = -0.07 - 0.33 * turn - 0.12 * glance
    pitch = -0.025 - 0.035 * turn
    lean = 0.006 * cycle - 0.015 * guard
    hip_yaw = -0.04 - 0.26 * turn
    torso_y = 1.55 + 0.008 * cycle - 0.012 * ramp(time, 3.44, 3.60) * (1 - ramp(time, 3.70, 3.95))
    bob = 0.006 * cycle
    chest = torso_rotation(yaw, pitch, lean)
    hip_rotation = yaw_rotation(hip_yaw)
    facing = yaw_rotation(heading)
    pivot = Vector((0, torso_y, 0))
    points = {}
    foot_angles = {}
    for side, sign in (("left", 1), ("right", -1)):
        shoulder = transform_point(Vector((sign * 0.39, 1.82 + torso_y - 1.55, 0)), pivot, chest)
        lowered_hand = Vector((sign * 0.49, 1.05 + torso_y - 1.55,
                               0.025 + sign * 0.065 * cycle))
        raised_hand = transform_point(final_pose[side + "Glove"] + Vector((0, torso_y - 1.55, 0)), pivot, chest)
        hand = lowered_hand.lerp(raised_hand, guard)
        lowered_elbow = Vector((sign * 0.64, 1.53 + torso_y - 1.55, -0.07))
        raised_elbow = transform_point(final_pose[side + "Elbow"] + Vector((0, torso_y - 1.55, 0)), pivot, chest)
        elbow, hand = solve_limb(shoulder, hand, lowered_elbow.lerp(raised_elbow, guard),
                                 lengths[side + "_upper_arm"], lengths[side + "_forearm"])
        hip = transform_point(final_pose[side + "Hip"], Vector((0, 0.86, 0)), hip_rotation)
        foot_world, foot_yaw, foot_pitch = feet[side]
        foot = facing.inverted() @ (foot_world - root - Vector((0, BASE_HEIGHT, 0)))
        neutral_knee = final_points[side + "Knee"]
        walking_pole = Vector((sign * 0.27, 0.47, 0.38))
        knee, solved_foot = solve_limb(hip, foot, walking_pole.lerp(neutral_knee, turn),
                                      lengths[side + "_thigh"], lengths[side + "_shin"])
        if (solved_foot - foot).length > 2e-5:
            raise ValueError("Unreachable planted foot: %s at %.3fs (%.6fm)" %
                             (side, time, (solved_foot - foot).length))
        points.update({side + "Shoulder": shoulder, side + "Elbow": elbow,
                       side + "Glove": hand, side + "Hip": hip,
                       side + "Knee": knee, side + "Foot": solved_foot})
        foot_angles[side] = (foot_yaw - heading, foot_pitch)
    head_rotation = IDENTITY.slerp(chest, 0.55)
    head = transform_point(Vector((0, 2.28 + bob, 0.04)), pivot, head_rotation)
    return dict(root=root, heading=heading, chest=chest, hip=hip_rotation,
                torso_y=torso_y, head=head, lean=lean, points=points,
                foot_angles=foot_angles, guard=guard)


def new_collection(name):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for old_collection in tuple(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def bone_matrix(position, rotation):
    matrix = rotation.to_4x4()
    matrix.translation = SCENE_TO_BLENDER @ position
    return matrix


def create_rig(final_pose, final_points, collection):
    data = bpy.data.armatures.new("PressureIntro_Skeleton")
    rig = bpy.data.objects.new(RIG_NAME, data)
    collection.objects.link(rig)
    rig.location.z = BASE_HEIGHT
    rig.show_in_front = True
    data.display_type = "OCTAHEDRAL"
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    def add_bone(name, head, tail=None, parent=None, rotation=None, length=0.18, connected=False):
        bone = data.edit_bones.new(name)
        if rotation is not None:
            bone.head = SCENE_TO_BLENDER @ head
            bone.tail = bone.head + rotation @ Vector((0, length, 0))
            bone.matrix = bone_matrix(head, rotation)
            bone.length = length
        else:
            bone.head = SCENE_TO_BLENDER @ head
            bone.tail = SCENE_TO_BLENDER @ tail
        if parent is not None:
            bone.parent = data.edit_bones[parent]
            bone.use_connect = connected
        bone.use_deform = True
        return bone

    add_bone("CTRL_root", Vector((0, 0, 0)), rotation=UP_BASIS)
    chest_rotation = torso_rotation(-0.40, -0.06, -0.015)
    add_bone("CTRL_chest", Vector((0, 1.55, 0)), parent="CTRL_root",
             rotation=blender_rotation(chest_rotation) @ UP_BASIS, length=0.35)
    add_bone("CTRL_pelvis", Vector((0, 0.86, 0)), parent="CTRL_root",
             rotation=blender_rotation(yaw_rotation(-0.30)) @ UP_BASIS)
    head = transform_point(Vector((0, 2.28, 0.04)), Vector((0, 1.55, 0)),
                           IDENTITY.slerp(chest_rotation, 0.55))
    add_bone("head", head, parent="CTRL_root", rotation=UP_BASIS)
    for side in ("left", "right"):
        for name, start, end, parent, connected in (
            ("upper_arm", "Shoulder", "Elbow", "CTRL_chest", False),
            ("forearm", "Elbow", "Glove", side + "_upper_arm", True),
            ("thigh", "Hip", "Knee", "CTRL_pelvis", False),
            ("shin", "Knee", "Foot", side + "_thigh", True),
        ):
            add_bone(side + "_" + name, final_points[side + start], final_points[side + end],
                     parent, connected=connected)
        add_bone(side + "_hand", final_points[side + "Glove"], parent=side + "_forearm",
                 rotation=UP_BASIS, length=0.15, connected=True)
        foot_rotation = yaw_rotation(final_pose[side + "FootYaw"])
        add_bone(side + "_foot", final_points[side + "Foot"], parent=side + "_shin",
                 rotation=blender_rotation(foot_rotation) @ FOOT_BASIS, length=0.20, connected=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
    rig["authoring_version"] = 1
    rig["contract"] = "FightPose v1: inverse chest arms, inverse hip hips, facing knees/feet"
    rig["root_base_height"] = BASE_HEIGHT
    rig["walk_steps"] = json.dumps(STEPS)
    rig["anatomy_basis"] = "Fixed lengths from raw neutral standard + applyGuard(amount: 1)"
    return rig


def segment_matrix(rig, bone_name, start, end):
    bone = rig.data.bones[bone_name]
    rest_axis = (bone.tail_local - bone.head_local).normalized()
    axis = (SCENE_TO_BLENDER @ (end - start)).normalized()
    rotation = rest_axis.rotation_difference(axis).to_matrix() @ bone.matrix_local.to_3x3()
    return bone_matrix(start, rotation)


def key_animation(rig, final_pose, final_points):
    lengths = limb_lengths(final_points)
    scene = bpy.context.scene
    for frame in range(FIRST_FRAME, LAST_FRAME + 1):
        scene.frame_set(frame)
        time = (frame - FIRST_FRAME) / FPS
        sample = authored_sample(time, final_pose, final_points, lengths)
        points = sample["points"]
        root_transform = bone_matrix(sample["root"], blender_rotation(yaw_rotation(sample["heading"])))
        matrices = {"CTRL_root": root_transform @ UP_BASIS.to_4x4()}
        matrices["CTRL_chest"] = root_transform @ bone_matrix(Vector((0, sample["torso_y"], 0)),
                                                             blender_rotation(sample["chest"]) @ UP_BASIS)
        matrices["CTRL_pelvis"] = root_transform @ bone_matrix(Vector((0, 0.86, 0)),
                                                              blender_rotation(sample["hip"]) @ UP_BASIS)
        head_rotation = Quaternion(Vector((0, 0, 1)), -sample["lean"] * 0.45)
        matrices["head"] = root_transform @ bone_matrix(sample["head"], blender_rotation(head_rotation) @ UP_BASIS)
        for side in ("left", "right"):
            for segment, start, end in (("upper_arm", "Shoulder", "Elbow"),
                                        ("forearm", "Elbow", "Glove"),
                                        ("thigh", "Hip", "Knee"), ("shin", "Knee", "Foot")):
                name = side + "_" + segment
                matrices[name] = root_transform @ segment_matrix(rig, name, points[side + start], points[side + end])
            hand_pitch = math.pi * (1 - sample["guard"])
            hand_rotation = Quaternion(Vector((1, 0, 0)), hand_pitch)
            matrices[side + "_hand"] = root_transform @ bone_matrix(points[side + "Glove"],
                                                                   blender_rotation(hand_rotation) @ UP_BASIS)
            foot_yaw, foot_pitch = sample["foot_angles"][side]
            foot_rotation = yaw_rotation(foot_yaw) @ Quaternion(Vector((1, 0, 0)), foot_pitch)
            matrices[side + "_foot"] = root_transform @ bone_matrix(points[side + "Foot"],
                                                                   blender_rotation(foot_rotation) @ FOOT_BASIS)
        for bone in rig.pose.bones:
            rest = bone.bone
            arguments = dict(parent_matrix=matrices[bone.parent.name],
                             parent_matrix_local=bone.parent.bone.matrix_local) if bone.parent else {}
            bone.matrix_basis = rest.convert_local_to_pose(matrices[bone.name], rest.matrix_local,
                                                          invert=True, **arguments)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
            bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
        rig.keyframe_insert('["authoring_version"]', frame=frame, group="Metadata")
    action = rig.animation_data.action
    action.name = "PRESSURE | Walk - Settle - Glance - Face - High Guard | 6.2s"
    if hasattr(action, "layers") and len(action.layers):
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    channelbag = strip.channelbag(slot)
                    if channelbag is not None:
                        for curve in channelbag.fcurves:
                            for key in curve.keyframe_points:
                                key.interpolation = "LINEAR"
    else:
        for curve in action.fcurves:
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"


def material(name, color, roughness=0.8):
    linear_color = tuple(channel / 12.92 if channel <= 0.04045
                         else ((channel + 0.055) / 1.055) ** 2.4 for channel in color)
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*linear_color, 1)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*linear_color, 1)
    shader.inputs["Roughness"].default_value = roughness
    return result


def preview_piece(name, rig, collection, bone_name, position, dimensions, surface, shape="sphere", rotation=None):
    if shape == "box":
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj = bpy.context.object
        obj.scale = dimensions
        bevel = obj.modifiers.new("Soft preview edges", "BEVEL")
        bevel.width = 0.025
        bevel.segments = 3
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=1)
        obj = bpy.context.object
        obj.scale = Vector(dimensions) * 0.5
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    obj.name = name
    obj.location = SCENE_TO_BLENDER @ position
    if rotation is not None:
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = blender_rotation(rotation).to_quaternion()
    bpy.context.view_layer.update()
    mesh_transform = obj.matrix_world.copy()
    for vertex in obj.data.vertices:
        vertex.co = mesh_transform @ vertex.co
    obj.matrix_world = rig.matrix_world.copy()
    obj.data.materials.append(surface)
    group = obj.vertex_groups.new(name=bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    deform = obj.modifiers.new("Editable skeleton attachment", "ARMATURE")
    deform.object = rig
    deform.use_vertex_groups = True
    move_to_collection(obj, collection)
    return obj


def create_preview(rig, final_pose, points, collection):
    skin = material("Pressure | Skin", (0.74, 0.42, 0.26), 0.62)
    trunks = material("Pressure | Oxblood trunks", (0.34, 0.025, 0.10), 0.88)
    gloves = material("Pressure | Burgundy gloves", (0.43, 0.035, 0.13), 0.62)
    trim = material("Pressure | Ivory trim", (0.94, 0.93, 0.90), 0.88)
    dark = material("Pressure | Soles and eyes", (0.025, 0.035, 0.055))
    hair = material("Pressure | Cropped hair", (0.055, 0.045, 0.043), 0.96)
    chest_rotation = torso_rotation(-0.4, -0.06, -0.015)
    hip_rotation = yaw_rotation(-0.30)
    preview_piece("Preview torso", rig, collection, "CTRL_chest", Vector((0, 1.55, 0)),
                  (0.92, 0.624, 0.94), skin, rotation=chest_rotation)
    preview_piece("Preview trunks", rig, collection, "CTRL_pelvis", Vector((0, 0.86, 0)),
                  (0.84, 0.56, 0.45), trunks, "box", hip_rotation)
    preview_piece("Preview waistband", rig, collection, "CTRL_pelvis", Vector((0, 1.08, 0)),
                  (0.88, 0.59, 0.13), trim, "box", hip_rotation)
    head_rotation = IDENTITY.slerp(chest_rotation, 0.55)
    head = transform_point(Vector((0, 2.28, 0.04)), Vector((0, 1.55, 0)), head_rotation)
    neck = transform_point(Vector((0, 2.02, 0.015)), Vector((0, 1.55, 0)), head_rotation)
    preview_piece("Preview neck", rig, collection, "head", neck, (0.30, 0.30, 0.24), skin)
    preview_piece("Preview head", rig, collection, "head", head, (0.516, 0.528, 0.648), skin)
    preview_piece("Preview cropped hair", rig, collection, "head", head + Vector((0, 0.25, -0.012)),
                  (0.50, 0.49, 0.19), hair)
    for sign in (-1, 1):
        preview_piece("Preview eye " + str(sign), rig, collection, "head", head + Vector((sign * 0.11, 0.06, 0.245)),
                      (0.045, 0.035, 0.045), dark)
    for side, sign in (("left", 1), ("right", -1)):
        preview_piece(side + " shoulder", rig, collection, side + "_upper_arm", points[side + "Shoulder"],
                      (0.378, 0.378, 0.378), skin)
        for segment, start, end, radius in (("upper_arm", "Shoulder", "Elbow", 0.14),
                                            ("forearm", "Elbow", "Glove", 0.12),
                                            ("thigh", "Hip", "Knee", 0.17),
                                            ("shin", "Knee", "Foot", 0.14)):
            midpoint = (points[side + start] + points[side + end]) * 0.5
            bone = rig.data.bones[side + "_" + segment]
            bone_rotation = bone.matrix_local.to_quaternion()
            obj = preview_piece(side + " " + segment, rig, collection, bone.name, midpoint,
                                (radius * 2.24, radius * 2.24, bone.length + radius), skin)
            center = SCENE_TO_BLENDER @ midpoint
            along_bone = bone_rotation.to_matrix() @ UP_BASIS.transposed()
            for vertex in obj.data.vertices:
                vertex.co = center + along_bone @ (vertex.co - center)
        hand = points[side + "Glove"]
        preview_piece(side + " glove", rig, collection, side + "_hand", hand + Vector((0, 0, 0.025)),
                      (0.3672, 0.432, 0.3672), gloves)
        preview_piece(side + " cuff", rig, collection, side + "_hand", hand + Vector((0, -0.155, 0)),
                      (0.284, 0.284, 0.055), trim)
        foot = points[side + "Foot"]
        foot_rotation = yaw_rotation(final_pose[side + "FootYaw"])
        preview_piece(side + " boot", rig, collection, side + "_foot", foot + foot_rotation @ Vector((0, 0, 0.08)),
                      (0.31, 0.48, 0.22), trunks, "box", foot_rotation)
        preview_piece(side + " sole", rig, collection, side + "_foot", foot + foot_rotation @ Vector((0, -0.12, 0.08)),
                      (0.33, 0.51, 0.055), dark, "box", foot_rotation)
        preview_piece(side + " trunks stripe", rig, collection, "CTRL_pelvis",
                      Vector((0, 0.86, 0)) + hip_rotation @ Vector((sign * 0.402, -0.015, 0)),
                      (0.055, 0.40, 0.35), trim, "box", hip_rotation)


def create_stage(collection):
    scene = bpy.context.scene
    floor_material = material("Preview mat", (0.16, 0.17, 0.18), 0.98)
    bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, CONTACT_HEIGHT - 0.1475))
    floor = bpy.context.object
    floor.name = "Inspection floor | boot sole contact"
    floor.data.materials.append(floor_material)
    move_to_collection(floor, collection)
    for name, location in (("Camera_ThreeQuarter", (5.8, -8, 3.9)),
                           ("Camera_Front", (0, -9, 2.7)), ("Camera_Side", (8, 0.7, 2.7))):
        data = bpy.data.cameras.new(name)
        camera = bpy.data.objects.new(name, data)
        collection.objects.link(camera)
        camera.location = location
        camera.rotation_euler = (Vector((0, 0.7, 1.4)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        data.type = "ORTHO"
        data.ortho_scale = 4.8
        if name == "Camera_ThreeQuarter":
            scene.camera = camera
    for name, location, power, size in (("Key", (3, -4, 6), 1100, 5),
                                       ("Fill", (-4, -2, 4), 800, 4),
                                       ("Rim", (1, 4, 5), 1300, 3)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = power
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        collection.objects.link(light)
        light.location = location
        light.rotation_euler = (Vector((0, 0.5, 1.3)) - light.location).to_track_quat("-Z", "Y").to_euler()
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Pressure Preview World")
    scene.world.color = (0.16, 0.16, 0.16)
    engines = scene.render.bl_rna.properties["engine"].enum_items.keys()
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "AgX"


def author_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.frame_start = FIRST_FRAME
    scene.frame_end = LAST_FRAME
    for name, time in (("WALK | relaxed arms", 0), ("SETTLE | both feet planted", 3.44),
                       ("GLANCE", 3.60), ("FACE PLAYER", 4.05),
                       ("RAISE COMPACT GUARD", 4.72), ("HOLD | neutral standard guard", 5.80)):
        scene.timeline_markers.new(name, frame=FIRST_FRAME + round(time * FPS))
    final_pose = standard_guard()
    points = facing_points(final_pose)
    rig = create_rig(final_pose, points, new_collection("01 | Editable FK Armature"))
    create_preview(rig, final_pose, points, new_collection("02 | Pressure Inspection Body"))
    create_stage(new_collection("03 | Preview Stage and Cameras"))
    key_animation(rig, final_pose, points)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    scene.frame_set(LAST_FRAME)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_perspective = "CAMERA"
                area.spaces.active.shading.type = "MATERIAL"
    scene["intro_duration"] = DURATION
    scene["intro_note"] = "Preview geometry only. Export uses evaluated keyed FK bones, never authoring point arrays."
    return rig


def vector_json(vector):
    return {axis: float(value) for axis, value in zip(("x", "y", "z"), vector)}


def read_evaluated_frame(rig, frame):
    scene = bpy.context.scene
    scene.frame_set(frame)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = rig.evaluated_get(depsgraph)
    bones = evaluated.pose.bones
    root_matrix = evaluated.matrix_world @ bones["CTRL_root"].matrix @ UP_BASIS.transposed().to_4x4()
    inverse_root = root_matrix.inverted()
    root = SCENE_TO_BLENDER.transposed() @ (root_matrix.translation - Vector((0, 0, BASE_HEIGHT)))
    forward = SCENE_TO_BLENDER.transposed() @ (root_matrix.to_3x3() @ Vector((0, -1, 0)))
    heading = math.atan2(forward.x, forward.z)

    def point(bone_name, tail=False):
        bone = bones[bone_name]
        location = bone.tail if tail else bone.head
        return SCENE_TO_BLENDER.transposed() @ (inverse_root @ (evaluated.matrix_world @ location))

    def orientation(bone_name, basis):
        matrix = inverse_root @ evaluated.matrix_world @ bones[bone_name].matrix
        return scene_rotation(matrix.to_3x3() @ basis.transposed())

    chest = orientation("CTRL_chest", UP_BASIS)
    pelvis = orientation("CTRL_pelvis", UP_BASIS)
    chest_pivot = point("CTRL_chest")
    pelvis_pivot = point("CTRL_pelvis")
    pitch, yaw, lean = chest.to_euler("XYZ")
    pose = dict(torsoY=float(chest_pivot.y), torsoYaw=float(yaw),
                torsoPitch=float(pitch), torsoLean=float(lean), hipYaw=float(pelvis.to_euler("XYZ").y))
    head_unrotated = transform_point(point("head"), chest_pivot, IDENTITY.slerp(chest, 0.55).inverted())
    pose["headBob"] = float(head_unrotated.y - 2.28)
    positions = {}
    world_feet = {}
    for side in ("left", "right"):
        positions.update({side + "Shoulder": point(side + "_upper_arm"),
                          side + "Elbow": point(side + "_upper_arm", tail=True),
                          side + "Glove": point(side + "_forearm", tail=True),
                          side + "Hip": point(side + "_thigh"),
                          side + "Knee": point(side + "_thigh", tail=True),
                          side + "Foot": point(side + "_shin", tail=True)})
        for part in ("Shoulder", "Elbow", "Glove"):
            field = side + part
            pose[field] = vector_json(transform_point(positions[field], chest_pivot, chest.inverted()))
        pose[side + "Hip"] = vector_json(transform_point(positions[side + "Hip"], pelvis_pivot, pelvis.inverted()))
        pose[side + "Knee"] = vector_json(positions[side + "Knee"])
        pose[side + "Foot"] = vector_json(positions[side + "Foot"])
        foot_angles = orientation(side + "_foot", FOOT_BASIS).to_euler("XYZ")
        pose[side + "FootYaw"] = float(foot_angles.y)
        pose[side + "FootPitch"] = float(foot_angles.x)
        world_feet[side] = SCENE_TO_BLENDER.transposed() @ (evaluated.matrix_world @ bones[side + "_shin"].tail)
    return (dict(time=(frame - scene.frame_start) / FPS, root=vector_json(root),
                 heading=float(heading), pose=pose), positions, world_feet, bones)


def numeric_values(value):
    if isinstance(value, dict):
        for child in value.values():
            yield from numeric_values(child)
    elif isinstance(value, list):
        for child in value:
            yield from numeric_values(child)
    else:
        yield value


def export_evaluated(rig):
    scene = bpy.context.scene
    if scene.render.fps != FPS or abs(scene.render.fps_base - 1) > 1e-8:
        raise ValueError("The authoring scene must use exactly 30fps")
    if scene.frame_end - scene.frame_start != round(DURATION * FPS):
        raise ValueError("The authoring range must span 186 frame intervals (6.2 seconds)")
    frames = []
    reference_lengths = {name: rig.data.bones[name].length for name in limb_lengths(facing_points(standard_guard()))}
    maximum_length_error = 0.0
    maximum_plant_error = 0.0
    maximum_scale_error = 0.0
    previous_feet = None
    previous_time = None
    for frame in range(scene.frame_start, scene.frame_end + 1):
        sample, positions, feet, bones = read_evaluated_frame(rig, frame)
        if set(sample["pose"]) != set(POINT_FIELDS + SCALAR_FIELDS):
            raise ValueError("FightPose v1 schema mismatch")
        if not all(isinstance(value, (int, float)) and math.isfinite(value) for value in numeric_values(sample)):
            raise ValueError("Nonfinite evaluated data at frame %s" % frame)
        if previous_time is not None and sample["time"] <= previous_time:
            raise ValueError("Frame times are not strictly sorted")
        for name, length in limb_lengths(positions).items():
            maximum_length_error = max(maximum_length_error, abs(length - reference_lengths[name]))
        for bone in bones:
            maximum_scale_error = max(maximum_scale_error, max(abs(value - 1) for value in bone.matrix.to_scale()))
        for side in ("left", "right"):
            if feet[side].y < CONTACT_HEIGHT - 2e-5:
                raise ValueError("Foot penetrates contact plane at frame %s" % frame)
            if previous_feet is not None:
                swing = any(step_side == side and previous_time < end and sample["time"] > start
                            for step_side, start, end, _ in STEPS)
                if not swing:
                    maximum_plant_error = max(maximum_plant_error, (feet[side] - previous_feet[side]).length)
        previous_time = sample["time"]
        previous_feet = feet
        frames.append(sample)
    if maximum_length_error > 2e-5 or maximum_scale_error > 2e-5 or maximum_plant_error > 2e-5:
        raise ValueError("Evaluated anatomy/contact drift: lengths=%g scale=%g plant=%g" %
                         (maximum_length_error, maximum_scale_error, maximum_plant_error))
    expected = standard_guard()
    final = frames[-1]
    pose_errors = [abs(final["pose"][field] - expected[field]) for field in SCALAR_FIELDS]
    pose_errors.extend((Vector(tuple(final["pose"][field][axis] for axis in ("x", "y", "z")))
                        - expected[field]).length for field in POINT_FIELDS)
    maximum_pose_error = max(pose_errors)
    if maximum_pose_error > 2e-5:
        raise ValueError("Final raw neutral + full guard mismatch: %g" % maximum_pose_error)
    if Vector(tuple(final["root"].values())).length > 2e-5 or abs(final["heading"]) > 2e-5:
        raise ValueError("Last evaluated root/heading must be zero")
    if (Vector(tuple(frames[0]["root"].values())) - Vector((0, 0, -1.8))).length > 2e-5:
        raise ValueError("First evaluated root must be (0, 0, -1.8)")
    if frames[0]["time"] != 0 or abs(final["time"] - DURATION) > 1e-10:
        raise ValueError("Missing required time endpoints")
    final["root"] = dict(x=0.0, y=0.0, z=0.0)
    final["heading"] = 0.0
    print("EVALUATED EXPORT: frames=%d duration=%.3fs fps=%d" % (len(frames), DURATION, FPS))
    print("MAX ERRORS: limb=%.9fm plant=%.9fm scale=%.9f final_pose=%.9f" %
          (maximum_length_error, maximum_plant_error, maximum_scale_error, maximum_pose_error))
    print("FIXED BONE LENGTHS (m): " + json.dumps(reference_lengths, sort_keys=True))
    return dict(version=1, duration=DURATION, frames=frames)


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--overwrite", action="store_true", help="Back up existing targets, then regenerate")
    parser.add_argument("--export-existing", action="store_true", help="Export the saved .blend without rebuilding or saving it")
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return parser.parse_args(arguments)


def main():
    arguments = parse_arguments()
    root = arguments.output_root.expanduser().resolve()
    blend_path = root / "art/Story/PressureIntro.blend"
    json_path = root / "PixelBoxingIOS/Resources/story_pressure_intro.json"
    targets = [json_path] if arguments.export_existing else [blend_path, json_path]
    if any(path.exists() for path in targets) and not arguments.overwrite:
        raise FileExistsError("Targets already exist. Use --overwrite for timestamped backups; "
                              "use --export-existing --overwrite to preserve and re-export the saved rig.")
    if arguments.export_existing:
        if not blend_path.is_file():
            raise FileNotFoundError(blend_path)
        bpy.ops.wm.open_mainfile(filepath=str(blend_path))
        rig = bpy.data.objects.get(RIG_NAME)
        if rig is None or rig.type != "ARMATURE":
            raise ValueError("Saved scene is missing the editable PressureIntro_Rig armature")
    else:
        rig = author_scene()
    payload = export_evaluated(rig)
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".pressure-intro-", dir=str(blend_path.parent)) as staging:
        staged_json = Path(staging) / json_path.name
        with staged_json.open("w", encoding="utf-8") as stream:
            json.dump(payload, stream, separators=(",", ":"), allow_nan=False)
            stream.write("\n")
        staged_blend = Path(staging) / blend_path.name
        if not arguments.export_existing:
            bpy.context.scene.frame_set(LAST_FRAME)
            bpy.context.preferences.filepaths.save_version = 0
            bpy.ops.wm.save_as_mainfile(filepath=str(staged_blend), check_existing=False)
        existing = [path for path in targets if path.exists()]
        if existing:
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
            backup = blend_path.parent / "backups" / stamp
            backup.mkdir(parents=True, exist_ok=False)
            for path in existing:
                shutil.copy2(path, backup / path.name)
            print("PRESERVED EXISTING TARGETS: " + str(backup))
        if not arguments.export_existing:
            os.replace(staged_blend, blend_path)
        os.replace(staged_json, json_path)
    print("BLENDER RESULT: " + str(blend_path))
    print("RESOURCE RESULT: " + str(json_path))


if __name__ == "__main__":
    main()