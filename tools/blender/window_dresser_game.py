"""Game version of the Window Dresser for Godot (mobile friendly).

Bakes the detailed sculpt (window_dresser.py) onto a light mesh: colour and
tangent-space normal maps, so the ribs, cracks and broken shell still read
at a fraction of the triangles. Same rig; stop-motion animations as actions
(one pose each, or a cycle with constant interpolation). Exports one GLB.

Run:  python window_dresser_game.py <out.glb> [--tex 1024] [--preview dir]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.argv = [sys.argv[0], "/tmp/unused"] + sys.argv[1:]
import window_dresser as W  # noqa: E402  (builds materials and the skeleton tables)
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

OUT = sys.argv[2]
TEX = int(sys.argv[sys.argv.index("--tex") + 1]) if "--tex" in sys.argv else 1024
PREVIEW = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
scene = bpy.context.scene


def select_only(objs, active):
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


# ------------------------------------------------------------- meshes ---
hi = W.build_body(3, "hi_body", True)
hi_inner = W.cut_holes(hi)
lo = W.build_body(1, "dresser_body", False)
print("game body tris", sum(len(p.vertices) - 2 for p in lo.data.polygons))

# UVs for the light mesh.
select_only([lo], lo)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(62), island_margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")


def bake_image(name, colour):
    img = bpy.data.images.new(name, TEX, TEX, alpha=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    return img


img_col = bake_image("dresser_albedo", True)
img_nrm = bake_image("dresser_normal", False)
mat = bpy.data.materials.new("DresserSkin")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
t_col = nt.nodes.new("ShaderNodeTexImage")
t_col.image = img_col
t_nrm = nt.nodes.new("ShaderNodeTexImage")
t_nrm.image = img_nrm
nmap = nt.nodes.new("ShaderNodeNormalMap")
lo.data.materials.clear()
lo.data.materials.append(mat)
for p in lo.data.polygons:
    p.material_index = 0

# ---------------------------------------------------------------- bake ---
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.025
scene.render.bake.max_ray_distance = 0.08
scene.render.bake.margin = 6
select_only([hi, hi_inner, lo], lo)
for img, node, kind in ((img_nrm, t_nrm, "NORMAL"), (img_col, t_col, "DIFFUSE")):
    nt.nodes.active = node
    if kind == "DIFFUSE":
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    else:
        bpy.ops.object.bake(type="NORMAL")
    print("baked", kind)
# Unused texture space takes the average skin colour / flat normal, so
# mipmaps don't bleed black into the seams at a distance.
import numpy as np  # noqa: E402
for img, fill in ((img_col, None), (img_nrm, (0.5, 0.5, 1.0, 1.0))):
    px = np.array(img.pixels[:]).reshape(-1, 4)
    empty = px[:, :3].sum(axis=1) < 1e-4
    if fill is None:
        fill = list(px[~empty].mean(axis=0))
        fill[3] = 1.0
    px[empty] = fill
    img.pixels[:] = px.ravel()
    img.update()
# Wire the textures in for export (glTF reads base colour + normal map).
nt.links.new(t_col.outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(t_nrm.outputs["Color"], nmap.inputs["Color"])
nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
bsdf.inputs["Roughness"].default_value = 0.4
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    for img in (img_col, img_nrm):
        img.filepath_raw = os.path.join(PREVIEW, img.name + ".png")
        img.file_format = "PNG"
        img.save()
for o in (hi, hi_inner):
    bpy.data.objects.remove(o)

# ----------------------------------------------------------------- rig ---
arm = W.build_rig(lo, holes=False)
arm.name = "dresser_rig"
show = W.build_head(arm)
stand = W.build_props(arm, "dresser_body")
for o in list(bpy.data.objects):
    if o.type == "FONT":            # tag lettering: unreadable at game distance
        bpy.data.objects.remove(o)
for name in ("head", "head_broken"):
    d = bpy.data.objects[name].modifiers.new("Decimate", "DECIMATE")
    d.ratio = 0.45
bpy.data.objects["head"].name = "head_calm"


def join_into(target, parts):
    """Merge child meshes into one (one draw call per material, not per tooth)."""
    parts = [p for p in parts if p.type == "MESH" and p != target]
    if not parts:
        return
    for p in parts:
        mw = p.matrix_world.copy()
        p.parent = None
        p.matrix_world = mw
    select_only(parts + [target], target)
    tmw = target.matrix_world.copy()
    bpy.ops.object.join()
    target.matrix_world = tmw


bpy.context.view_layer.update()
hb = bpy.data.objects["head_broken"]
join_into(hb, list(hb.children_recursive))
tg = bpy.data.objects["tag"]
join_into(tg, list(tg.children_recursive))
for o in stand:
    o.name = "display_" + o.name
    o.parent = None


# ----------------------------------------------------------- animations ---
def key_pose(action_name, frames, cycle=False):
    """frames: list of bone-direction dicts, one per stop-motion frame."""
    act = bpy.data.actions.new(action_name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for f, dirs in enumerate(frames):
        W.pose_on_floor(arm, dirs)
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f * 3 + 1)
            pb.keyframe_insert("location", frame=f * 3 + 1)
    if cycle:   # back to the first frame so it loops
        W.pose_on_floor(arm, frames[0])
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=len(frames) * 3 + 1)
            pb.keyframe_insert("location", frame=len(frames) * 3 + 1)
    for fc in _fcurves(act):
        for k in fc.keyframe_points:
            k.interpolation = "CONSTANT"
    act.use_fake_user = True
    return act


def _fcurves(act):
    if hasattr(act, "fcurves") and len(act.fcurves):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def mixed(base, **over):
    d = dict(base)
    d.update(over)
    return d


H = W.HUNT
REST = {}
stalk = [
    mixed(REST, head=(0.35, -0.1, 1.0), uarm_l=(-0.2, -0.1, -1.0)),
    mixed(REST, head=(-0.3, -0.35, 1.0), neck=(0.0, -0.3, 1.0), farm_r=(0.1, -1.0, 0.2), hand_r=(0.0, -1.0, 0.5)),
    mixed(REST, spine=(0.0, -0.25, 1.0), head=(0.55, -0.5, 0.7), uarm_r=(0.2, -0.6, -1.0), marm_r=(0.1, -1.0, -0.2)),
]
run = []
for k in range(6):
    a = 2 * math.pi * k / 6
    s, c = math.sin(a), math.cos(a)
    run.append(mixed(
        H,
        thigh_r=(0.05, -0.85 * s, -1.0), shin_r=(0.0, 0.3 + 0.55 * max(c, 0), -1.0),
        thigh_l=(-0.05, 0.85 * s, -1.0), shin_l=(0.0, 0.3 + 0.55 * max(-c, 0), -1.0),
        foot_r=(0, -1, -0.25 - 0.4 * max(-s, 0)), foot_l=(0, -1, -0.25 - 0.4 * max(s, 0)),
        uarm_r=(0.25, -0.9 + 0.5 * s, -0.4), farm_r=(0.04, -1.0, 0.25),
        uarm_l=(-0.3, -0.4 - 0.5 * s, -1.0),
        head=(0.12 + 0.15 * math.sin(a * 2.3), -0.95, 0.55 + 0.1 * c),
    ))
lunge = [mixed(H, uarm_r=(0.15, -1.0, 0.1), uarm_l=(-0.15, -1.0, 0.1), marm_r=(0.05, -1.0, 0.0),
               marm_l=(-0.05, -1.0, 0.0), farm_r=(0.0, -1.0, 0.0), farm_l=(0.0, -1.0, 0.0),
               spine=(0.0, -1.0, 0.8), neck=(0.0, -0.8, 0.6), head=(0.05, -0.28, 1.0))]
key_pose("dormant", [W.DISPLAY])
key_pose("stalk_a", [stalk[0]])
key_pose("stalk_b", [stalk[1]])
key_pose("stalk_c", [stalk[2]])
key_pose("hunt", [H])
key_pose("run", run, cycle=True)
key_pose("lunge", lunge)
arm.animation_data.action = bpy.data.actions["dormant"]

# --------------------------------------------------------------- export ---
show(False)
objs = [arm, lo] + [o for o in bpy.data.objects if o.parent and o.type == "MESH" and o not in (lo,)]
objs += [o for o in bpy.data.objects if o.name.startswith("display_")]
objs = list(dict.fromkeys(objs))
for o in objs:
    o.hide_render = False
    o.hide_set(False)
select_only(objs, arm)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True,
                          export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=False, export_image_format="AUTO")
print("exported", OUT, "objects", [o.name for o in objs][:12], "...", len(objs))
