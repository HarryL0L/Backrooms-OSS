"""The Window Dresser: hostile Dead Mall entity, concept model (v2).

One continuous body grown from a skeleton (Skin modifier), so limbs join the
torso instead of poking into it, then sculpted in code: ribs, sunken belly,
spine and collarbones, bony knees and elbows, real cracks in the shell and
chunks broken away. Rigged with an armature and posed by bone directions.
The split head (two halves with teeth, a small face inside) rides the head
bone. Run:  python window_dresser.py <out_dir> [--fast] [--only 1,2,3] [--glb path]
"""
import math
import sys

import bpy  # noqa: I001  (bpy first: it makes bmesh/mathutils importable)
import bmesh
import numpy as np
from mathutils import Matrix, Vector

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/dresser"
GLB = sys.argv[sys.argv.index("--glb") + 1] if "--glb" in sys.argv else None
FAST = "--fast" in sys.argv

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ------------------------------------------------------------- materials ---
def node_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m, m.node_tree.nodes, m.node_tree.links


def fibreglass():
    """Yellowed ivory fibreglass: grime in the creases, hairline cracks,
    chipped patches down to grey filler."""
    m, n, l = node_mat("Fibreglass")
    bsdf = n["Principled BSDF"]
    tc = n.new("ShaderNodeTexCoord")
    # Cracks: thin Voronoi edges, distorted, only in some patches.
    dist = n.new("ShaderNodeTexNoise")
    dist.inputs["Scale"].default_value = 6.0
    mix_co = n.new("ShaderNodeMix")
    mix_co.data_type = "VECTOR"
    mix_co.inputs["Factor"].default_value = 0.18
    l.new(tc.outputs["Object"], mix_co.inputs["A"])
    l.new(dist.outputs["Color"], mix_co.inputs["B"])
    l.new(tc.outputs["Object"], dist.inputs["Vector"])
    vor = n.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 9.0
    l.new(mix_co.outputs["Result"], vor.inputs["Vector"])
    crack = n.new("ShaderNodeMapRange")
    crack.inputs["From Min"].default_value = 0.0
    crack.inputs["From Max"].default_value = 0.025
    crack.inputs["To Min"].default_value = 1.0
    crack.inputs["To Max"].default_value = 0.0
    l.new(vor.outputs["Distance"], crack.inputs["Value"])
    patch = n.new("ShaderNodeTexNoise")
    patch.inputs["Scale"].default_value = 2.2
    l.new(tc.outputs["Object"], patch.inputs["Vector"])
    patch_m = n.new("ShaderNodeMapRange")
    patch_m.inputs["From Min"].default_value = 0.52
    patch_m.inputs["From Max"].default_value = 0.6
    l.new(patch.outputs["Fac"], patch_m.inputs["Value"])
    cracks = n.new("ShaderNodeMath")
    cracks.operation = "MULTIPLY"
    l.new(crack.outputs["Result"], cracks.inputs[0])
    l.new(patch_m.outputs["Result"], cracks.inputs[1])
    # Chips: larger blotches where the gelcoat flaked off.
    chip = n.new("ShaderNodeTexNoise")
    chip.inputs["Scale"].default_value = 14.0
    chip.inputs["Detail"].default_value = 6.0
    l.new(tc.outputs["Object"], chip.inputs["Vector"])
    chip_m = n.new("ShaderNodeMapRange")
    chip_m.inputs["From Min"].default_value = 0.66
    chip_m.inputs["From Max"].default_value = 0.68
    l.new(chip.outputs["Fac"], chip_m.inputs["Value"])
    # Grime: ambient occlusion pulls dirt into the creases and joints.
    ao = n.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.06
    grime_n = n.new("ShaderNodeTexNoise")
    grime_n.inputs["Scale"].default_value = 30.0
    l.new(tc.outputs["Object"], grime_n.inputs["Vector"])
    base = n.new("ShaderNodeMix")
    base.data_type = "RGBA"
    base.inputs["A"].default_value = (0.42, 0.36, 0.24, 1)      # grime
    base.inputs["B"].default_value = (0.74, 0.66, 0.5, 1)       # yellowed ivory
    ao_c = n.new("ShaderNodeMapRange")
    ao_c.inputs["From Min"].default_value = 0.3
    ao_c.inputs["From Max"].default_value = 1.0
    ao_c.inputs["To Min"].default_value = 0.15
    l.new(ao.outputs["AO"], ao_c.inputs["Value"])
    l.new(ao_c.outputs["Result"], base.inputs["Factor"])
    filler = n.new("ShaderNodeMix")
    filler.data_type = "RGBA"
    filler.inputs["B"].default_value = (0.33, 0.33, 0.31, 1)
    l.new(base.outputs["Result"], filler.inputs["A"])
    l.new(chip_m.outputs["Result"], filler.inputs["Factor"])
    crk = n.new("ShaderNodeMix")
    crk.data_type = "RGBA"
    crk.inputs["B"].default_value = (0.08, 0.06, 0.04, 1)
    l.new(filler.outputs["Result"], crk.inputs["A"])
    l.new(cracks.outputs["Value"], crk.inputs["Factor"])
    l.new(crk.outputs["Result"], bsdf.inputs["Base Color"])
    rough = n.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = 0.28
    rough.inputs["To Max"].default_value = 0.75
    l.new(chip_m.outputs["Result"], rough.inputs["Value"])
    l.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Coat Weight"].default_value = 0.35
    bsdf.inputs["Coat Roughness"].default_value = 0.2
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.002
    hmix = n.new("ShaderNodeMath")
    hmix.operation = "SUBTRACT"
    hmix.inputs[0].default_value = 1.0
    hm2 = n.new("ShaderNodeMath")
    hm2.operation = "MAXIMUM"
    l.new(cracks.outputs["Value"], hm2.inputs[0])
    l.new(chip_m.outputs["Result"], hm2.inputs[1])
    l.new(hm2.outputs["Value"], hmix.inputs[1])
    l.new(hmix.outputs["Value"], bump.inputs["Height"])
    l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def simple(name, col, rough=0.5, metal=0.0, emit=None, strength=1.0):
    m, n, _ = node_mat(name)
    b = n["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


M_SKIN = fibreglass()
M_PIN = simple("Pin", (0.18, 0.17, 0.16), 0.35, 1.0)
M_INNER = simple("Inner", (0.03, 0.012, 0.01), 0.25)
M_TEETH = simple("Teeth", (0.62, 0.58, 0.48), 0.3)
M_TAG = simple("Tag", (0.85, 0.84, 0.8), 0.6)
M_TAG_RED = simple("TagRed", (0.45, 0.04, 0.03), 0.5)
M_INK = simple("Ink", (0.02, 0.02, 0.03), 0.6)
M_EYE = simple("EyeGlint", (0.0, 0.0, 0.0), 0.4, emit=(1.0, 0.92, 0.75), strength=6.0)


M_CAVITY = simple("Cavity", (0.05, 0.02, 0.015), 0.18)


def ellipsoid(name, r, mat=M_SKIN, segs=24, rings=14):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2]))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    me.materials.append(mat)
    for f in me.polygons:
        f.use_smooth = True
    return ob


def cyl(name, r, depth, mat=M_PIN, verts=12):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=r, radius2=r, depth=depth)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    me.materials.append(mat)
    return ob


# --------------------------------------------------------------- skeleton ---
# Joints (Blender Z up, the figure faces -Y) and skin radii (x, y).
JP = {}
RAD = {}
EDGES = []
BONES = []      # (name, head joint, tail joint, parent bone)


def j(name, pos, r):
    JP[name] = Vector(pos)
    RAD[name] = r if isinstance(r, tuple) else (r, r)


def bone(name, a, b, parent):
    BONES.append((name, a, b, parent))
    EDGES.append((a, b))


j("P0", (0, 0.0, 0.97), (0.14, 0.105))
j("S1", (0, 0.014, 1.14), (0.098, 0.07))
j("C", (0, 0.02, 1.36), (0.158, 0.1))
j("N0", (0, 0.03, 1.53), (0.085, 0.066))
j("N1", (0, 0.0, 1.69), (0.03, 0.032))
j("H", (0, -0.01, 1.9), 0.02)
bone("pelvis", "P0", "S1", None)
bone("spine", "S1", "C", "pelvis")
bone("chest", "C", "N0", "spine")
bone("neck", "N0", "N1", "chest")
# Extra skin rings along the torso (skin points only, not joints), so the
# sculpted ribs and belly have enough surface to live on.
for a_, b_ in (("P0", "S1"), ("S1", "C"), ("C", "N0")):
    EDGES.remove((a_, b_))
    prev = a_
    for k in (1, 2):
        t = k / 3
        nm = f"{a_}_{b_}_{k}"
        j(nm, JP[a_].lerp(JP[b_], t), tuple(RAD[a_][i] + (RAD[b_][i] - RAD[a_][i]) * t for i in range(2)))
        EDGES.append((prev, nm))
        prev = nm
    EDGES.append((prev, b_))
BONES.append(("head", "N1", "H", "neck"))     # the head is the fibreglass shell, not skin
for s, sd in ((1, "r"), (-1, "l")):
    j("SH" + sd, (0.185 * s, 0.03, 1.48), 0.046)
    j("E1" + sd, (0.212 * s, 0.05, 1.2), 0.031)
    j("E2" + sd, (0.222 * s, 0.04, 0.94), 0.027)
    j("W" + sd, (0.228 * s, 0.0, 0.69), (0.021, 0.018))
    j("PA" + sd, (0.233 * s, -0.012, 0.615), (0.03, 0.011))
    bone("clav_" + sd, "N0", "SH" + sd, "chest")
    bone("uarm_" + sd, "SH" + sd, "E1" + sd, "clav_" + sd)
    bone("marm_" + sd, "E1" + sd, "E2" + sd, "uarm_" + sd)
    bone("farm_" + sd, "E2" + sd, "W" + sd, "marm_" + sd)
    bone("hand_" + sd, "W" + sd, "PA" + sd, "farm_" + sd)
    # Four long fingers and a thumb, ends thin and splintered.
    for i, (dx, ln) in enumerate(((-0.021, 0.17), (-0.007, 0.195), (0.008, 0.185), (0.02, 0.15))):
        base = JP["PA" + sd] + Vector((dx * s, -0.004, 0.0))
        j(f"K{i}" + sd, base, 0.0085)
        j(f"M{i}" + sd, base + Vector((dx * 0.35 * s, -0.01, -ln * 0.55)), 0.0068)
        j(f"T{i}" + sd, base + Vector((dx * 0.6 * s, -0.018, -ln)), 0.0028)
        EDGES.append(("PA" + sd, f"K{i}" + sd))
        bone(f"f{i}a_" + sd, f"K{i}" + sd, f"M{i}" + sd, "hand_" + sd)
        bone(f"f{i}b_" + sd, f"M{i}" + sd, f"T{i}" + sd, f"f{i}a_" + sd)
    j("TB0" + sd, JP["W" + sd] + Vector((-0.008 * s, -0.022, -0.035)), 0.009)
    j("TB1" + sd, JP["TB0" + sd] + Vector((-0.01 * s, -0.03, -0.05)), 0.0075)
    j("TB2" + sd, JP["TB1" + sd] + Vector((-0.004 * s, -0.016, -0.045)), 0.0032)
    EDGES.append(("W" + sd, "TB0" + sd))
    bone("th0_" + sd, "TB0" + sd, "TB1" + sd, "hand_" + sd)
    bone("th1_" + sd, "TB1" + sd, "TB2" + sd, "th0_" + sd)
    j("HP" + sd, (0.098 * s, 0.0, 0.93), 0.078)
    j("KN" + sd, (0.104 * s, -0.022, 0.53), 0.044)
    j("A" + sd, (0.104 * s, 0.028, 0.1), 0.027)
    j("TO" + sd, (0.104 * s, -0.13, 0.025), (0.026, 0.012))
    EDGES.append(("P0", "HP" + sd))
    bone("thigh_" + sd, "HP" + sd, "KN" + sd, "pelvis")
    bone("shin_" + sd, "KN" + sd, "A" + sd, "thigh_" + sd)
    bone("foot_" + sd, "A" + sd, "TO" + sd, "shin_" + sd)

BONE_OF_TAIL = {b[2]: b[0] for b in BONES}
PARENT = {b[0]: b[3] for b in BONES}
HEAD_J = {b[0]: b[1] for b in BONES}
TAIL_J = {b[0]: b[2] for b in BONES}


def segdist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    q = a + np.outer(t, ab)
    return np.linalg.norm(p - q, axis=1), t


# Chunks of the fibreglass shell broken away: (centre, radius, shape seed).
HOLES = (((-0.08, -0.1, 1.27), 0.055, 1.0), ((0.11, -0.055, 0.78), 0.042, 3.0), ((-0.04, 0.085, 1.24), 0.05, 4.0))


# ------------------------------------------------------------------ body ---
def build_body():
    used = {a for e in EDGES for a in e}
    names = [nm for nm in JP if nm in used]     # (H is only a bone end, not skin)
    idx = {n: i for i, n in enumerate(names)}
    me = bpy.data.meshes.new("body")
    me.from_pydata([tuple(JP[n]) for n in names], [(idx[a], idx[b]) for a, b in EDGES], [])
    ob = bpy.data.objects.new("body", me)
    scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    sk = ob.modifiers.new("Skin", "SKIN")
    sk.branch_smoothing = 0.6
    sk.use_smooth_shade = True
    for n in names:
        me.skin_vertices[0].data[idx[n]].radius = RAD[n]
    me.skin_vertices[0].data[idx["P0"]].use_root = True
    sub = ob.modifiers.new("Sub", "SUBSURF")
    sub.levels = 3
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    ob.data = mesh
    sculpt(ob)
    return ob


def sculpt(ob):
    """Procedural sculpting on the rest pose."""
    me = ob.data
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    me.update()
    nrm = np.empty(n * 3)
    me.vertices.foreach_get("normal", nrm)
    nrm = nrm.reshape(n, 3)
    # The skin hull can fold at the chest; relax the torso surface first
    # (Laplacian smoothing, torso only) so the sculpting starts clean.
    ed = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ed)
    ed = ed.reshape(-1, 2)
    deg = np.zeros(n)
    np.add.at(deg, ed[:, 0], 1)
    np.add.at(deg, ed[:, 1], 1)
    region = (np.abs(co[:, 0]) < 0.21) & (co[:, 2] > 0.98) & (co[:, 2] < 1.6)
    for _ in range(14):
        acc = np.zeros_like(co)
        np.add.at(acc, ed[:, 0], co[ed[:, 1]])
        np.add.at(acc, ed[:, 1], co[ed[:, 0]])
        avg = acc / np.maximum(deg, 1)[:, None]
        co[region] += 0.5 * (avg[region] - co[region])
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    nrm = np.empty(n * 3)
    me.vertices.foreach_get("normal", nrm)
    nrm = nrm.reshape(n, 3)
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    disp = np.zeros(n)
    torso = (np.abs(x) < 0.2) & (z > 0.95) & (z < 1.56)
    torso &= ~((np.abs(x) > 0.15) & (z < 1.45))
    front = np.clip(-(y - 0.02) / 0.1, 0, 1)
    back = np.clip((y - 0.02) / 0.08, 0, 1)
    # Ribs: bands that run down towards the front, deep gaps between them.
    rz = (z - 0.035 * front)
    ribs = torso & (z > 1.17) & (z < 1.44)
    # Thin bony ridges with shallow gaps, strongest on the sides of the
    # chest, fading towards the sternum and the back.
    wave = np.cos(2 * np.pi * rz / 0.036)
    side = np.clip(np.abs(x) / 0.09, 0, 1) * np.clip(front * 1.5, 0, 1)
    disp += np.where(ribs, (0.0042 * np.maximum(wave, 0) ** 3 - 0.0012) * side, 0)
    # Sternum ridge and a hollow belly under the ribcage.
    disp += np.where(ribs & (np.abs(x) < 0.018) & (front > 0.6), 0.004, 0)
    belly = torso & (z > 1.0) & (z < 1.18) & (front > 0.2)
    disp -= np.where(belly, 0.032 * front * np.sin(np.clip((z - 1.0) / 0.18, 0, 1) * np.pi) * np.clip(1 - np.abs(x) / 0.1, 0, 1), 0)
    # Hip bones jutting at the front.
    for sx in (-1, 1):
        d = np.sqrt((x - 0.105 * sx) ** 2 + ((z - 1.02) * 1.6) ** 2)
        disp += np.where(front > 0.3, 0.017 * np.exp(-(d / 0.03) ** 2), 0)
    # Collarbones: ridges from the throat to the shoulders.
    clz = 1.5 + 0.03 * np.clip(np.abs(x) / 0.17, 0, 1)
    disp += np.where((front > 0.4) & (np.abs(x) > 0.025) & (np.abs(x) < 0.18), 0.011 * np.exp(-((z - clz) / 0.011) ** 2), 0)
    # Spine: a row of vertebrae down the back; shoulder blades.
    vert = torso & (back > 0.6) & (np.abs(x) < 0.022)
    disp += np.where(vert, 0.01 * np.maximum(np.sin(2 * np.pi * z / 0.034), 0) ** 0.5, 0)
    for sx in (-1, 1):
        d = np.sqrt(((x - 0.085 * sx) / 1.3) ** 2 + (z - 1.42) ** 2)
        disp += np.where(back > 0.5, 0.013 * np.exp(-(d / 0.04) ** 2), 0)
    # Bony knees and elbows.
    for sd in ("r", "l"):
        for jn, amt, side in (("KN", 0.012, -1), ("E1", 0.008, 1), ("E2", 0.0, 0)):
            c = np.array(JP[jn + sd])
            d = np.linalg.norm(co - c, axis=1)
            facing = (co[:, 1] - c[1]) * side > 0 if side else np.ones(n, bool)
            disp += np.where(facing, amt * np.exp(-(d / 0.03) ** 2), 0)
    co += nrm * disp[:, None]
    # The extra elbow is a snapped joint: pinched in, dark inside the crack.
    cav = np.zeros(n, bool)
    for sd in ("r", "l"):
        a, b = np.array(JP["E1" + sd]), np.array(JP["W" + sd])
        c = np.array(JP["E2" + sd])
        axis = (b - a) / np.linalg.norm(b - a)
        along = (co - c) @ axis
        near = (np.abs(along) < 0.012) & (np.linalg.norm(co - c, axis=1) < 0.05)
        radial = co - (c + np.outer(along, axis))
        pinch = 1 - 0.45 * np.exp(-(along / 0.006) ** 2)
        co[near] = (c + np.outer(along, axis) + radial * pinch[:, None])[near]
        cav |= near & (np.abs(along) < 0.004)
    me.vertices.foreach_set("co", co.ravel())
    me.materials.append(M_SKIN)
    me.materials.append(M_CAVITY)
    for p in me.polygons:
        if all(cav[v] for v in p.vertices):
            p.material_index = 1
    holes = np.zeros(n, bool)
    for centre, r, seed in HOLES:
        c = np.array(centre)
        d = np.linalg.norm(co - c, axis=1)
        ang = np.arctan2(co[:, 2] - c[2], co[:, 0] - c[0] + co[:, 1] - c[1])
        rr = r * (1 + 0.3 * np.sin(ang * 4 + seed) + 0.18 * np.sin(ang * 9 + seed * 2) + 0.1 * np.sin(ang * 17 + seed))
        holes |= d < rr
    ob["holes"] = [int(i) for i in np.nonzero(holes)[0]]
    for p in me.polygons:
        p.use_smooth = True
    me.update()
    # Real cracks: Voronoi F2-F1 edges cut into the surface, plus fine lumps.
    tex = bpy.data.textures.new("cracks", "VORONOI")
    tex.distance_metric = "DISTANCE"
    tex.weight_1 = -1.0
    tex.weight_2 = 1.0
    tex.noise_scale = 0.06
    tex.use_color_ramp = True
    tex.color_ramp.elements[0].position = 0.0
    tex.color_ramp.elements[0].color = (0, 0, 0, 1)
    tex.color_ramp.elements[1].position = 0.06
    tex.color_ramp.elements[1].color = (1, 1, 1, 1)
    dm = ob.modifiers.new("Cracks", "DISPLACE")
    dm.texture = tex
    dm.texture_coords = "OBJECT" if False else "GLOBAL"
    dm.strength = 0.0035
    dm.mid_level = 1.0
    lump = bpy.data.textures.new("lumps", "CLOUDS")
    lump.noise_scale = 0.03
    dl = ob.modifiers.new("Lumps", "DISPLACE")
    dl.texture = lump
    dl.texture_coords = "GLOBAL"
    dl.strength = 0.0008
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    ob.data = mesh


# ------------------------------------------------------------------ rig ---
def build_rig(body):
    ad = bpy.data.armatures.new("rig")
    arm = bpy.data.objects.new("rig", ad)
    scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, a, b, parent in BONES:
        eb = ad.edit_bones.new(name)
        eb.head = JP[a]
        eb.tail = JP[b]
        eb.roll = 0.0
        if parent:
            eb.parent = ad.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    # Weights by distance *along the surface*: torso skin reaches the arm
    # only round the shoulder, so a moving limb never drags the body with it.
    # Seeds are vertices that unambiguously belong to one bone (by distance
    # relative to that bone's thickness); every other vertex takes the bone
    # of its geodesically nearest seed. Labels are then smoothed over the
    # mesh so joints bend softly.
    import heapq
    me = body.data
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    names = [b[0] for b in BONES if b[0] != "head"]
    B = len(names)
    Dn = np.empty((n, B))
    for k, bn in enumerate(names):
        a_, b_ = np.array(JP[HEAD_J[bn]]), np.array(JP[TAIL_J[bn]])
        d, t = segdist(co, a_, b_)
        ra = sum(RAD[HEAD_J[bn]]) / 2
        rb = sum(RAD[TAIL_J[bn]]) / 2
        Dn[:, k] = d / (ra + (rb - ra) * t + 0.004)
    srt = np.sort(Dn, axis=1)
    best = np.argmin(Dn, axis=1)
    seed = (srt[:, 1] > srt[:, 0] * 1.45) & (srt[:, 0] < 1.6)
    ed = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ed)
    ed = ed.reshape(-1, 2)
    nb = [[] for _ in range(n)]
    for u, v in ed:
        w = float(np.linalg.norm(co[u] - co[v]))
        nb[u].append((v, w))
        nb[v].append((u, w))
    label = np.full(n, -1)
    dist = np.full(n, np.inf)
    hp = []
    for i in np.nonzero(seed)[0]:
        dist[i] = 0.0
        label[i] = best[i]
        hp.append((0.0, int(i)))
    heapq.heapify(hp)
    while hp:
        d0, u = heapq.heappop(hp)
        if d0 > dist[u]:
            continue
        for v, w in nb[u]:
            if d0 + w < dist[v]:
                dist[v] = d0 + w
                label[v] = label[u]
                heapq.heappush(hp, (d0 + w, v))
    label[label < 0] = best[label < 0]
    W = np.zeros((n, B))
    W[np.arange(n), label] = 1.0
    deg = np.zeros(n)
    np.add.at(deg, ed[:, 0], 1)
    np.add.at(deg, ed[:, 1], 1)
    for _ in range(10):
        acc = W.copy()
        np.add.at(acc, ed[:, 0], W[ed[:, 1]])
        np.add.at(acc, ed[:, 1], W[ed[:, 0]])
        W = acc / (1 + deg)[:, None]
    groups = {bn: body.vertex_groups.new(name=bn) for bn in names}
    top = np.argsort(-W, axis=1)[:, :4]
    for i in range(n):
        ws = W[i, top[i]]
        ws = ws / ws.sum()
        for k in range(4):
            if ws[k] > 0.01:
                groups[names[top[i, k]]].add([i], float(ws[k]), "REPLACE")
    # Broken-away chunks: subdivide around each hole so the edge can be
    # ragged, cut it out, and put a dark inner skin 1 cm inside (same
    # weights) under each one, so the shell reads as hollow fibreglass.
    def hole_r(c, r, seed, p):
        d = p - c
        ang = math.atan2(d.z, d.x + d.y)
        return r * (1 + 0.3 * math.sin(ang * 4 + seed) + 0.18 * math.sin(ang * 9 + seed * 2) + 0.1 * math.sin(ang * 17 + seed))

    bm = bmesh.new()
    bm.from_mesh(body.data)
    dl = bm.verts.layers.deform.verify()
    for c, r, seed in HOLES:
        c = Vector(c)
        near = [e for e in bm.edges if (e.verts[0].co - c).length < r * 1.9]
        if near:
            bmesh.ops.subdivide_edges(bm, edges=near, cuts=3, use_grid_fill=True)
    kill = set()
    for f in bm.faces:
        p = f.calc_center_median()
        for c, r, seed in HOLES:
            c = Vector(c)
            if (p - c).length < hole_r(c, r, seed, p):
                kill.add(f)
    inner_bm = bm.copy()
    bmesh.ops.delete(bm, geom=list(kill), context="FACES")
    bm.to_mesh(body.data)
    bm.free()
    inner_bm.normal_update()
    keep = set()
    for f in inner_bm.faces:
        p = f.calc_center_median()
        for c, r, seed in HOLES:
            if (p - Vector(c)).length < r * 1.7:
                keep.add(f)
    bmesh.ops.delete(inner_bm, geom=[f for f in inner_bm.faces if f not in keep], context="FACES")
    for v in inner_bm.verts:
        v.co -= v.normal * 0.011
    for f in inner_bm.faces:
        f.material_index = 1
    bmesh.ops.reverse_faces(inner_bm, faces=inner_bm.faces[:])
    inner = bpy.data.objects.new("body_inside", bpy.data.meshes.new("body_inside"))
    scene.collection.objects.link(inner)
    inner_bm.to_mesh(inner.data)
    inner_bm.free()
    for m in body.data.materials:
        inner.data.materials.append(m)
    for g in body.vertex_groups:
        inner.vertex_groups.new(name=g.name)
    for ob in (body, inner):
        ob.parent = arm
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
    return arm


def bone_parent(ob, arm, bone_name, world):
    """Parent `ob` to a bone, keeping `world` as its rest transform."""
    pb = arm.pose.bones[bone_name]
    tail = arm.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))
    ob.parent = arm
    ob.parent_type = "BONE"
    ob.parent_bone = bone_name
    ob.matrix_parent_inverse = tail.inverted()
    ob.matrix_basis = world


def pose(arm, dirs, root=None):
    """Pose by world directions per bone (unlisted bones keep their angle
    relative to the parent). root moves the pelvis."""
    rot = {}
    head = {}
    for name, a, b, parent in BONES:
        rest_dir = (JP[b] - JP[a]).normalized()
        if parent is None:
            R = Matrix.Identity(3)
            h = Vector(root) if root else JP[a]
        else:
            R = rot[parent]
            h = head[parent] + rot[parent] @ (JP[a] - JP[HEAD_J[parent]])
        cur = R @ rest_dir
        if name in dirs:
            want = Vector(dirs[name]).normalized()
            R = cur.rotation_difference(want).to_matrix() @ R
        rot[name] = R
        head[name] = h
        pb = arm.pose.bones[name]
        rest = pb.bone.matrix_local.to_3x3()
        m = (R @ rest).to_4x4()
        m.translation = h
        pb.matrix = m
        bpy.context.view_layer.update()
    return head, rot


def joint_world(head, rot, joint):
    b = BONE_OF_TAIL.get(joint)
    if b is None:
        return None
    return head[b] + rot[b] @ (JP[joint] - JP[HEAD_J[b]])


# ------------------------------------------------------------------ head ---
def build_head(arm):
    """Dormant: a smooth mannequin egg. Awake: the face has shattered into a
    jagged hole lined with teeth, and a small face stares out from inside."""
    centre = Vector((0, -0.005, 1.79))
    R = (0.086, 0.104, 0.134)

    def egg(name):
        ob = ellipsoid(name, R, M_SKIN, 64, 36)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        for v in bm.verts:
            if v.co.y < -0.07 and abs(v.co.x) < 0.03 and -0.03 < v.co.z < 0.03:
                v.co.y -= 0.007 * (1 - abs(v.co.x) / 0.03)
        bm.to_mesh(ob.data)
        bm.free()
        cr = ob.modifiers.new("Cracks", "DISPLACE")
        cr.texture = bpy.data.textures["cracks"]
        cr.texture_coords = "GLOBAL"
        cr.strength = 0.0025
        cr.mid_level = 1.0
        return ob

    calm = egg("head")
    bone_parent(calm, arm, "head", Matrix.Translation(centre))
    broken = egg("head_broken")
    bm = bmesh.new()
    bm.from_mesh(broken.data)
    hc = Vector((0.0, -0.1, -0.005))

    def rim(p):
        d = p - hc
        ang = math.atan2(d.z, d.x)
        return 0.06 * (1 + 0.28 * math.sin(ang * 5 + 1.3) + 0.16 * math.sin(ang * 11 + 0.4) + 0.12 * math.sin(ang * 23))

    bmesh.ops.delete(bm, geom=[f for f in bm.faces if (f.calc_center_median() - hc).length < rim(f.calc_center_median())], context="FACES")
    # Shell thickness: a dark inner wall.
    inside = bm.copy()
    for v in inside.verts:
        v.co *= 0.9
    bmesh.ops.reverse_faces(inside, faces=inside.faces[:])
    for f in inside.faces:
        f.material_index = 1
    edge_pts = [v.co.copy() for v in bm.verts if v.is_boundary]
    bm.to_mesh(broken.data)
    bm.free()
    broken.data.materials.append(M_INNER)
    shell = bpy.data.objects.new("head_inside", bpy.data.meshes.new("head_inside"))
    scene.collection.objects.link(shell)
    inside.to_mesh(shell.data)
    inside.free()
    shell.data.materials.append(M_SKIN)
    shell.data.materials.append(M_INNER)
    for f in shell.data.polygons:
        f.use_smooth = True
    shell.parent = broken
    # Teeth along the broken rim, pointing into the hole.
    rng = np.random.default_rng(11)
    edge_pts.sort(key=lambda q: math.atan2(q.z - hc.z, q.x - hc.x))
    for k, q in enumerate(edge_pts):
        if k % 2:
            continue
        ln = 0.012 + 0.02 * rng.random()
        cone = bpy.data.meshes.new("tooth")
        bm2 = bmesh.new()
        bmesh.ops.create_cone(bm2, cap_ends=True, segments=6, radius1=0.0042, radius2=0.0004, depth=ln)
        bm2.to_mesh(cone)
        bm2.free()
        to = bpy.data.objects.new("tooth", cone)
        scene.collection.objects.link(to)
        cone.materials.append(M_TEETH)
        to.parent = broken
        p = Vector(q)
        inward = (Vector((hc.x, p.y, hc.z)) - p).normalized()
        to.location = p + inward * ln * 0.45
        to.rotation_euler = inward.to_track_quat("Z", "Y").to_euler()
    bone_parent(broken, arm, "head", Matrix.Translation(centre))
    # The face inside, set back in the dark.
    inner = ellipsoid("inner_face", (0.05, 0.055, 0.07), M_SKIN, 28, 16)
    inner.parent = broken
    inner.location = (0.0, -0.035, -0.008)
    for sx in (-1, 1):
        eye = ellipsoid("inner_eye", (0.01, 0.01, 0.008), M_INNER, 12, 8)
        eye.parent = inner
        eye.location = (0.019 * sx, -0.039, 0.014)
        g = ellipsoid("inner_glint", (0.0016, 0.0014, 0.0016), M_EYE, 8, 6)
        g.parent = eye
        g.location = (0, -0.004, 0)
    mouth = ellipsoid("inner_mouth", (0.009, 0.007, 0.014), M_INNER, 12, 8)
    mouth.parent = inner
    mouth.location = (0, -0.048, -0.03)

    def show(awake):
        calm.hide_render = awake
        for o in [broken] + list(broken.children_recursive):
            o.hide_render = not awake
    return show


def build_props(arm):
    stand = []
    plate = cyl("stand_plate", 0.2, 0.012, M_PIN, 32)
    plate.location = (0, 0.12, 0.006)
    rod = cyl("stand_rod", 0.009, 0.36, M_PIN)
    rod.location = (0.104, 0.12, 0.18)
    rod2 = cyl("stand_rod2", 0.009, 0.1, M_PIN)
    rod2.location = (0.104, 0.075, 0.36)
    rod2.rotation_euler = (math.pi / 2, 0, 0)
    stand = [plate, rod, rod2]
    # Name tag on the chest: HELLO / my name is (blank).
    tag = bpy.data.objects.new("tag", bpy.data.meshes.new("tag"))
    scene.collection.objects.link(tag)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.08, v.co.y * 0.004, v.co.z * 0.048))
    bm.to_mesh(tag.data)
    bm.free()
    tag.data.materials.append(M_TAG)
    band = bpy.data.objects.new("tagband", bpy.data.meshes.new("tagband"))
    scene.collection.objects.link(band)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.081, v.co.y * 0.0045, v.co.z * 0.015 + 0.016))
    bm.to_mesh(band.data)
    bm.free()
    band.data.materials.append(M_TAG_RED)
    band.parent = tag
    for txt, zz, size, mat in (("HELLO", 0.016, 0.011, M_TAG), ("my name is", 0.001, 0.0065, M_TAG_RED)):
        cu = bpy.data.curves.new("t", "FONT")
        cu.body = txt
        cu.size = size
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        to = bpy.data.objects.new("tagtext", cu)
        scene.collection.objects.link(to)
        cu.materials.append(mat)
        to.parent = tag
        to.location = (0, -0.0026, zz)
        to.rotation_euler = (math.pi / 2, 0, 0)
    body = bpy.data.objects["body"]
    hit, loc, nrm, _ = body.ray_cast(Vector((0.075, -0.4, 1.41)), Vector((0, 1, 0)))
    if not hit:
        loc, nrm = Vector((0.075, -0.112, 1.41)), Vector((0, -1, 0))
    rotm = (-nrm).to_track_quat("Y", "Z").to_matrix().to_4x4()
    w = Matrix.Translation(loc + nrm * 0.0035) @ rotm
    bone_parent(tag, arm, "spine", w)
    return stand


# ----------------------------------------------------------------- poses ---
DISPLAY = {
    # A stiff shop pose: one forearm raised as if presenting something.
    "farm_r": (-0.05, -1.0, 0.15), "hand_r": (0.0, -1.0, 0.35), "marm_r": (0.05, -0.25, -1.0),
    "uarm_l": (-0.12, 0.0, -1.0), "head": (0.04, -0.06, 1.0),
}
HUNT = {
    "pelvis": (0, -0.45, 1), "spine": (0.04, -0.75, 1), "chest": (0.0, -0.65, 1), "neck": (0.08, -1.0, 0.55),
    "head": (0.12, -0.95, 0.55),
    "uarm_r": (0.2, -1.0, -0.12), "marm_r": (0.12, -1.0, -0.3), "farm_r": (0.04, -1.0, 0.3), "hand_r": (0.0, -1.0, -0.05),
    "uarm_l": (-0.35, -0.35, -1), "marm_l": (-0.1, 0.25, -1), "farm_l": (-0.05, -0.65, -1), "hand_l": (0.0, -0.5, -1),
    "thigh_r": (0.05, -0.8, -1), "shin_r": (0.0, 0.25, -1), "foot_r": (0, -1, -0.2),
    "thigh_l": (-0.1, 0.45, -1), "shin_l": (0.0, 0.75, -1), "foot_l": (0, -1, -0.75),
}
for sd in ("r", "l"):
    # Claw: fingers splay and curl.
    for i in range(4):
        HUNT[f"f{i}a_" + sd] = ((i - 1.5) * 0.25 * (1 if sd == "r" else -1), -1.0, -0.6) if sd == "r" else ((i - 1.5) * -0.2, -0.3, -1.0)
        HUNT[f"f{i}b_" + sd] = (0.0, -0.2, -1.0) if sd == "r" else (0.0, 0.1, -1.0)


def pose_on_floor(arm, dirs):
    """Pose, then lower or raise the pelvis so the lowest foot rests on the floor."""
    root = Vector(JP["P0"])
    for _ in range(2):
        head, rot = pose(arm, dirs, root)
        low = min(joint_world(head, rot, "A" + sd).z - 0.07 for sd in ("r", "l"))
        low = min(low, min(joint_world(head, rot, "TO" + sd).z - 0.02 for sd in ("r", "l")))
        root = root - Vector((0, 0, low))
    pose(arm, dirs, root)


def stage():
    # Dead mall: wet terrazzo floor, a shop front, dying fluorescent light.
    floor = bpy.data.objects.new("floor", bpy.data.meshes.new("floor"))
    scene.collection.objects.link(floor)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=8)
    bm.to_mesh(floor.data)
    bm.free()
    fm, n, l = node_mat("WetTile")
    b = n["Principled BSDF"]
    tc = n.new("ShaderNodeTexCoord")
    br = n.new("ShaderNodeTexBrick")
    br.inputs["Scale"].default_value = 3.2
    br.inputs["Mortar Size"].default_value = 0.012
    br.inputs["Color1"].default_value = (0.13, 0.12, 0.1, 1)
    br.inputs["Color2"].default_value = (0.1, 0.095, 0.08, 1)
    br.inputs["Mortar"].default_value = (0.04, 0.035, 0.03, 1)
    br.offset = 0.0
    l.new(tc.outputs["Object"], br.inputs["Vector"])
    l.new(br.outputs["Color"], b.inputs["Base Color"])
    wet = n.new("ShaderNodeTexNoise")
    wet.inputs["Scale"].default_value = 1.2
    l.new(tc.outputs["Object"], wet.inputs["Vector"])
    wr = n.new("ShaderNodeMapRange")
    wr.inputs["From Min"].default_value = 0.45
    wr.inputs["From Max"].default_value = 0.55
    wr.inputs["To Min"].default_value = 0.06
    wr.inputs["To Max"].default_value = 0.6
    l.new(wet.outputs["Fac"], wr.inputs["Value"])
    l.new(wr.outputs["Result"], b.inputs["Roughness"])
    floor.data.materials.append(fm)
    wall = bpy.data.objects.new("wall", bpy.data.meshes.new("wall"))
    scene.collection.objects.link(wall)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6)
    bm.to_mesh(wall.data)
    bm.free()
    wall.rotation_euler = (math.pi / 2, 0, 0)
    wall.location = (0, 3.0, 3)
    wall.data.materials.append(simple("Wall", (0.16, 0.14, 0.11), 0.85))
    # One hard light from above and in front (a lone working tube), a cold rim
    # light behind to cut the silhouette out of the dark.
    bpy.ops.object.light_add(type="SPOT", location=(0.7, -1.6, 3.3))
    lt = bpy.context.object
    lt.data.energy = 520
    lt.data.spot_size = math.radians(55)
    lt.data.spot_blend = 0.6
    lt.data.shadow_soft_size = 0.15
    lt.data.color = (0.9, 0.97, 1.0)
    lt.rotation_euler = (Vector((0, 0, 1.1)) - lt.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.light_add(type="AREA", location=(-0.8, 1.1, 2.2))
    rim = bpy.context.object
    rim.data.size = 0.6
    rim.data.energy = 45
    rim.data.color = (0.6, 0.75, 1.0)
    rim.rotation_euler = (Vector((0, 0, 1.3)) - rim.location).to_track_quat("-Z", "Y").to_euler()
    fill = rim
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.002, 0.002, 0.0025, 1)
    vol = w.node_tree.nodes.new("ShaderNodeVolumeScatter")
    vol.inputs["Density"].default_value = 0.012
    w.node_tree.links.new(vol.outputs["Volume"], w.node_tree.nodes["World Output"].inputs["Volume"])
    scene.world = w
    return lt


def camera(loc, look, lens=50):
    cam = bpy.data.objects.get("cam")
    if cam is None:
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scene.collection.objects.link(cam)
        scene.camera = cam
    cam.data.lens = lens
    cam.location = loc
    d = Vector(look) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def render(name, w=900, h=1200):
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24 if FAST else 96
    scene.cycles.use_denoising = True
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.filepath = f"{OUT}/{name}.png"
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    body = build_body()
    arm = build_rig(body)
    head_show = build_head(arm)
    head_show(False)
    stand = build_props(arm)
    tube = stage()
    print("body verts", len(body.data.vertices), "tris", sum(len(p.vertices) - 2 for p in body.data.polygons))
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    pose_on_floor(arm, DISPLAY)
    if GLB:
        bpy.ops.export_scene.gltf(filepath=GLB, export_format="GLB")
    camera((0.9, -3.4, 1.35), (0, 0, 1.05), 40)
    if not only or "1" in only:
        render("1_display")
    camera((0.55, -1.15, 1.18), (0.0, -0.05, 1.22), 45)
    if not only or "5" in only:
        render("5_torso", 1000, 1000)
    for o in stand:
        o.hide_render = True
    pose_on_floor(arm, HUNT)
    head_show(True)
    camera((1.7, -1.9, 0.85), (0.0, -0.3, 1.0), 30)
    if not only or "2" in only:
        render("2_awake")
    camera((-1.0, -2.5, 0.6), (0.0, -0.4, 1.15), 36)
    if not only or "4" in only:
        render("4_front")
    # Face close-up: aim at the head wherever the pose put it.
    hp = (arm.matrix_world @ arm.pose.bones["head"].matrix).translation
    hd = (arm.matrix_world @ arm.pose.bones["head"].matrix).to_3x3() @ Vector((0, 1, 0))
    fc = hp + hd * 0.1
    camera(fc + Vector((0.25, -0.75, -0.08)), fc, 55)
    if not only or "3" in only:
        render("3_face", 1000, 1000)
