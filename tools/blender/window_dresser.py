"""The Window Dresser: hostile Dead Mall entity, concept model.

Builds a segmented fibreglass mannequin (rigid parts on a joint hierarchy, no
skinning, so it is cheap on weak phones), poses it and renders concept shots.
Run with Blender's Python module:  python window_dresser.py <out_dir> [--glb path]
"""
import math
import sys

import bpy  # noqa: I001  (bpy first: it makes bmesh/mathutils importable)
import bmesh
from mathutils import Euler, Vector

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


# ----------------------------------------------------------------- shapes ---
def loft(name, pts, radii, segs=20, cap=True, mat=M_SKIN, subsurf=1):
    """Smooth tube through points (local space) with (rx, ry) per point."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        p = Vector(p)
        a = Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])
        t = a.normalized()
        side = Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 1, 0))
        u = (side - t * side.dot(t)).normalized()
        v = t.cross(u)
        rx, ry = radii[i]
        ring = []
        for k in range(segs):
            ang = 2 * math.pi * k / segs
            ring.append(bm.verts.new(p + u * math.cos(ang) * rx + v * math.sin(ang) * ry))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            k2 = (k + 1) % segs
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    me.materials.append(mat)
    for f in me.polygons:
        f.use_smooth = True
    if subsurf:
        sm = ob.modifiers.new("Subsurf", "SUBSURF")
        sm.levels = subsurf
        sm.render_levels = subsurf + 1
    return ob


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


# ------------------------------------------------------------- skeleton ---
# Rigid joints (empties). Rest positions, Blender Z-up, figure faces -Y.
J = {}
REST = {}


def joint(name, pos, parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.04
    scene.collection.objects.link(e)
    if parent:
        e.parent = J[parent]
        e.location = Vector(pos) - REST[parent]
    else:
        e.location = pos
    REST[name] = Vector(pos)
    J[name] = e
    return e


def attach(ob, jname, offset=(0, 0, 0)):
    ob.parent = J[jname]
    ob.location = offset


H = 2.08   # just too tall for a person
joint("root", (0, 0, 0))
joint("hips", (0, 0, 1.0), "root")
joint("spine", (0, 0, 1.13), "hips")
joint("neck", (0, 0, 1.57), "spine")
joint("head", (0, 0, 1.73), "neck")
for s, side in ((1, "r"), (-1, "l")):
    joint("shoulder_" + side, (0.205 * s, 0, 1.5), "spine")
    joint("elbow1_" + side, (0.22 * s, 0, 1.2), "shoulder_" + side)
    joint("elbow2_" + side, (0.225 * s, 0, 0.93), "elbow1_" + side)    # the extra one
    joint("wrist_" + side, (0.23 * s, 0, 0.67), "elbow2_" + side)
    joint("hip_" + side, (0.095 * s, 0, 0.98), "hips")
    joint("knee_" + side, (0.1 * s, 0, 0.55), "hip_" + side)
    joint("ankle_" + side, (0.1 * s, 0.0, 0.09), "knee_" + side)

GAP = 0.009   # visible gap at every joint, the pins show through


def seg_between(name, ja, jb, ra, rb, gap_a=0.0, gap_b=0.0, pin=False, profile=None):
    """A tapered limb segment from joint ja to joint jb. Normal joints overlap
    (rounded ends sink into the neighbour, like a shop mannequin's fitted
    parts); a gap leaves the steel pin showing."""
    a = REST[ja]
    b = REST[jb]
    d = b - a
    L = d.length
    t = d.normalized()
    s0 = gap_a if gap_a > 0 else -ra * 0.55
    s1 = L - gap_b if gap_b > 0 else L + rb * 0.55
    prof = profile or [(0.0, 0.55), (0.04, 0.9), (0.15, 1.0), (0.55, 0.94), (0.88, 0.88), (0.96, 0.82), (1.0, 0.5)]
    pts, rad = [], []
    for f, k in prof:
        pts.append(t * (s0 + (s1 - s0) * f))
        r = (ra + (rb - ra) * f) * k
        rad.append((r, r))
    ob = loft(name, pts, rad, 20)
    attach(ob, ja)
    if pin:
        p = cyl(name + "_pin", min(ra, rb) * 0.3, max(gap_b, 0.02) * 2.4)
        p.rotation_euler = t.to_track_quat("Z", "Y").to_euler()
        attach(p, jb)
    return ob


# Torso: fitted shell from the waist cut to the neck. Pelvis below the cut,
# with a crack-thin gap (it was snapped there once).
torso = loft("torso", [(0, 0.004, 0.006), (0, 0.0, 0.05), (0, -0.004, 0.13), (0, -0.012, 0.22), (0, -0.01, 0.29),
                       (0, -0.002, 0.35), (0, 0.006, 0.395), (0, 0.012, 0.425), (0, 0.016, 0.445), (0, 0.016, 0.455)],
             [(0.122, 0.082), (0.125, 0.084), (0.14, 0.094), (0.156, 0.108), (0.162, 0.11), (0.178, 0.1),
              (0.19, 0.088), (0.165, 0.074), (0.09, 0.055), (0.045, 0.042)], 32)
attach(torso, "spine")
pelvis = loft("pelvis", [(0, 0.012, -0.17), (0, 0.006, -0.12), (0, 0.0, -0.05), (0, -0.002, 0.03), (0, 0.002, 0.1), (0, 0.004, 0.122)],
              [(0.06, 0.05), (0.15, 0.1), (0.172, 0.112), (0.162, 0.104), (0.128, 0.088), (0.122, 0.082)], 32)
attach(pelvis, "hips")
waist_pin = cyl("waist_pin", 0.026, 0.03)
attach(waist_pin, "spine")
# A neck that is a little too long.
neck = loft("neck", [(0, 0, -0.02), (0, 0, 0.07), (0, 0, 0.14)], [(0.036, 0.038), (0.031, 0.033), (0.029, 0.031)], 16)
attach(neck, "neck")

# Head: an egg split down the middle into two halves that can open.
joint("jaw_r", (0.0, 0.1, 1.8), "head")
joint("jaw_l", (0.0, 0.1, 1.8), "head")


def head_half(side):
    s = 1.0 if side == "r" else -1.0
    ob = ellipsoid("head_" + side, (0.088, 0.105, 0.135), M_SKIN, 32, 18)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    # Keep one half, cap the cut with the dark inside.
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0.004 * s, 0, 0), plane_no=(s, 0, 0), clear_inner=True)
    cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    fill = bmesh.ops.edgeloop_fill(bm, edges=cut)
    me.materials.append(M_INNER)
    for f in fill["faces"]:
        f.material_index = 1
        f.smooth = False
    # Faint nose ridge and brow: mannequin heads are almost featureless.
    for v in bm.verts:
        if v.co.y < -0.07 and abs(v.co.x) < 0.03 and -0.03 < v.co.z < 0.03:
            v.co.y -= 0.008 * (1 - abs(v.co.x) / 0.03)
        if v.co.y < -0.06 and 0.035 < v.co.z < 0.055:
            v.co.y -= 0.004
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    # Teeth: a row of thin yellowed pegs along the cut edge, inside.
    teeth = []
    for i in range(13):
        a = math.pi * (0.12 + 0.76 * i / 12)
        y = -math.sin(a) * 0.1
        z = math.cos(a) * 0.125
        t = bpy.data.objects.new("tooth", None)
        cone = bpy.data.meshes.new("tooth_" + side + str(i))
        bm2 = bmesh.new()
        bmesh.ops.create_cone(bm2, cap_ends=True, segments=6, radius1=0.006, radius2=0.0005, depth=0.022)
        bm2.to_mesh(cone)
        bm2.free()
        to = bpy.data.objects.new("tooth_" + side + str(i), cone)
        scene.collection.objects.link(to)
        cone.materials.append(M_TEETH)
        to.parent = ob
        to.location = (0.006 * s, y * 0.92, z * 0.92)
        to.rotation_euler = (0, -s * math.pi / 2, 0)
    ob.parent = J["jaw_" + side]
    ob.location = Vector((0, 0, 1.8)) - REST["jaw_" + side]
    return ob


head_half("r")
head_half("l")
# Inside the hollow head: a second, smaller face with empty eyes.
inner = ellipsoid("inner_face", (0.052, 0.06, 0.078), M_SKIN, 24, 14)
attach(inner, "head", (0, -0.012, 0.065))
for sx in (-1, 1):
    # Hollow sockets: dark ellipsoids sunk into the face, a pinprick of
    # light deep inside each.
    eye = ellipsoid("inner_eye", (0.012, 0.012, 0.009), M_INNER, 12, 8)
    eye.parent = inner
    eye.location = (0.02 * sx, -0.041, 0.014)
    glint = ellipsoid("inner_glint", (0.0018, 0.0015, 0.0018), M_EYE, 8, 6)
    glint.parent = eye
    glint.location = (0.0, -0.004, 0.0)
mouth = ellipsoid("inner_mouth", (0.012, 0.006, 0.004), M_INNER, 12, 6)
mouth.parent = inner
mouth.location = (0, -0.056, -0.03)

# Limbs: arms are one segment too long (two elbows), hands reach the knees.
for s, side in ((1, "r"), (-1, "l")):
    seg_between("uarm_" + side, "shoulder_" + side, "elbow1_" + side, 0.05, 0.038,
                profile=[(0.0, 0.7), (0.06, 1.0), (0.3, 1.0), (0.7, 0.9), (0.95, 0.85), (1.0, 0.5)])
    # The extra elbow: a hard gap with the pin showing, edges a bit ragged.
    seg_between("marm_" + side, "elbow1_" + side, "elbow2_" + side, 0.037, 0.033, gap_b=0.026, pin=True)
    seg_between("farm_" + side, "elbow2_" + side, "wrist_" + side, 0.034, 0.025, gap_a=0.008)
    # Mannequin hand: long, fingers fused, the thumb apart.
    hand = loft("hand_" + side, [(0, 0, 0.01), (0, 0, -0.04), (0.004 * s, -0.004, -0.1), (0.007 * s, -0.01, -0.17), (0.008 * s, -0.016, -0.215), (0.008 * s, -0.019, -0.232)],
                [(0.02, 0.026), (0.015, 0.04), (0.011, 0.042), (0.009, 0.034), (0.006, 0.02), (0.003, 0.008)], 18)
    attach(hand, "wrist_" + side)
    thumb = loft("thumb_" + side, [(0, -0.02, -0.03), (0, -0.034, -0.07), (0.0, -0.036, -0.105)],
                 [(0.009, 0.009), (0.008, 0.007), (0.004, 0.004)], 10)
    attach(thumb, "wrist_" + side)
    seg_between("thigh_" + side, "hip_" + side, "knee_" + side, 0.085, 0.052,
                profile=[(0.0, 0.6), (0.06, 1.0), (0.25, 1.0), (0.7, 0.86), (0.95, 0.84), (1.0, 0.5)])
    seg_between("shin_" + side, "knee_" + side, "ankle_" + side, 0.05, 0.03,
                profile=[(0.0, 0.5), (0.05, 0.98), (0.25, 1.05), (0.6, 0.85), (0.95, 0.82), (1.0, 0.45)])
    foot = loft("foot_" + side, [(0, 0.035, 0.0), (0, 0.03, -0.045), (0, -0.04, -0.075), (0, -0.13, -0.084), (0, -0.175, -0.085), (0, -0.19, -0.084)],
                [(0.028, 0.03), (0.034, 0.034), (0.038, 0.02), (0.034, 0.012), (0.026, 0.01), (0.012, 0.006)], 16)
    attach(foot, "ankle_" + side)

# The display stand: a steel rod from a base plate into the right calf. When
# it wakes the rod is torn out; an empty base plate is the clue.
stand = bpy.data.objects.new("stand", None)
scene.collection.objects.link(stand)
plate = cyl("stand_plate", 0.2, 0.012, M_PIN, 32)
plate.parent = stand
plate.location = (0, 0.12, 0.006)
rod = cyl("stand_rod", 0.009, 0.38, M_PIN)
rod.parent = stand
rod.location = (0.1, 0.12, 0.19)
rod_top = cyl("stand_rod2", 0.009, 0.13, M_PIN)
rod_top.parent = stand
rod_top.location = (0.1, 0.06, 0.38)
rod_top.rotation_euler = (math.pi / 2, 0, 0)

# Name tag on the chest: HELLO / my name is (blank).
tag = bpy.data.objects.new("tag", bpy.data.meshes.new("tag"))
scene.collection.objects.link(tag)
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * 0.085, v.co.y * 0.004, v.co.z * 0.05))
bm.to_mesh(tag.data)
bm.free()
tag.data.materials.append(M_TAG)
attach(tag, "spine", (-0.08, -0.112, 0.31))
tag.rotation_euler = (0.18, 0, 0.12)
band = bpy.data.objects.new("tagband", bpy.data.meshes.new("tagband"))
scene.collection.objects.link(band)
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * 0.086, v.co.y * 0.0045, v.co.z * 0.016 + 0.017))
bm.to_mesh(band.data)
bm.free()
band.data.materials.append(M_TAG_RED)
band.parent = tag
for txt, z, size, mat in (("HELLO", 0.017, 0.012, M_TAG), ("my name is", 0.002, 0.007, M_TAG_RED)):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = txt
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    to = bpy.data.objects.new("tagtext", cu)
    scene.collection.objects.link(to)
    cu.materials.append(mat)
    to.parent = tag
    to.location = (0, -0.0026, z)
    to.rotation_euler = (math.pi / 2, 0, 0)


# ------------------------------------------------------------------ poses ---
def rot(j, x=0.0, y=0.0, z=0.0):
    J[j].rotation_euler = Euler((math.radians(x), math.radians(y), math.radians(z)))


def pose_display():
    """Dormant: a normal shop mannequin on its stand, one hand on the hip."""
    for j in J:
        J[j].rotation_euler = (0, 0, 0)
    J["root"].location = (0, 0, 0)
    for o in stand.children:
        o.hide_render = False
    rot("shoulder_l", 0, -8, 0)
    rot("elbow1_l", 0, 0, 0)
    rot("elbow2_l", -10, 0, 0)
    rot("shoulder_r", 5, 25, 0)
    rot("elbow1_r", -70, 20, 0)
    rot("elbow2_r", -40, 0, 0)
    rot("wrist_r", 0, -40, 0)
    rot("hip_r", 0, 4, 0)
    rot("hip_l", -4, -3, 0)
    rot("head", 4, 0, -6)


def pose_awake():
    """Hunting: hunched towards you, one arm reaching, the other hanging with
    its extra elbow bent the wrong way, head cocked and the face split open."""
    for j in J:
        J[j].rotation_euler = (0, 0, 0)
    for o in stand.children:
        o.hide_render = True
    J["root"].location = (0, 0, -0.12)
    rot("hips", 18, 0, 0)
    rot("spine", 26, 0, 4)
    rot("neck", -26, 0, -4)
    rot("head", -8, 24, 6)
    rot("jaw_r", 0, 0, 40)
    rot("jaw_l", 0, 0, -40)
    rot("shoulder_l", -38, 14, 0)
    rot("elbow1_l", -18, 0, 0)
    rot("elbow2_l", 34, 0, 0)        # bends backwards
    rot("wrist_l", -25, 0, 0)
    rot("shoulder_r", -100, 6, 0)
    rot("elbow1_r", -8, 0, 0)
    rot("elbow2_r", 22, 0, 0)        # the wrong elbow, bent back
    rot("wrist_r", 12, 0, 0)
    # (the legs inherit the pelvis tilt of 18 degrees)
    rot("hip_r", -53, 0, 4)
    rot("knee_r", 60, 0, 0)
    rot("ankle_r", -25, 0, 0)
    rot("hip_l", -6, 0, -6)
    rot("knee_l", 30, 0, 0)
    rot("ankle_l", -30, 0, 0)


# ------------------------------------------------------------------ stage ---
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
    tube = stage()
    if GLB:
        pose_display()
        bpy.ops.export_scene.gltf(filepath=GLB, export_format="GLB", use_selection=False)
    only = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
    pose_display()
    camera((0.9, -3.4, 1.35), (0, 0, 1.05), 40)
    if not only or "1" in only:
        render("1_display")
    pose_awake()
    camera((1.7, -1.9, 0.85), (0.0, -0.3, 1.0), 30)
    tube.data.energy = 420
    if not only or "2" in only:
        render("2_awake")
    camera((0.25, -0.95, 1.52), (0.0, -0.05, 1.62), 55)
    if not only or "3" in only:
        render("3_face", 1000, 1000)
