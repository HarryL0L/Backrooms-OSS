"""Dead Mall prop library (Blender, built in code).

Every function builds one prop as a joined mesh object at the origin (Z up,
front facing -Y) using the named materials below; the Godot side swaps each
material for the mall surface shader by name, so the names matter more than
the Blender colours (which only tint the light bounce in the bake).
"""
import math

import bpy  # noqa: I001
import bmesh
from mathutils import Matrix, Vector

# name: (base colour, roughness, emission strength)
MATS = {
    "terrazzo": ((0.52, 0.48, 0.42), 0.35, 0.0),
    "tile_white": ((0.78, 0.77, 0.73), 0.3, 0.0),
    "wall_paint": ((0.62, 0.55, 0.44), 0.8, 0.0),
    "ceiling_tile": ((0.7, 0.68, 0.62), 0.9, 0.0),
    "light_panel": ((1.0, 0.97, 0.9), 0.5, 9.0),
    "light_dead": ((0.55, 0.55, 0.52), 0.5, 0.0),
    "metal_frame": ((0.16, 0.13, 0.1), 0.45, 0.0),
    "metal_bright": ((0.62, 0.62, 0.6), 0.3, 0.0),
    "glass": ((0.25, 0.3, 0.3), 0.05, 0.0),
    "shutter": ((0.45, 0.45, 0.43), 0.55, 0.0),
    "sign_red": ((0.5, 0.08, 0.06), 0.5, 0.0),
    "sign_teal": ((0.1, 0.36, 0.36), 0.5, 0.0),
    "sign_cream": ((0.8, 0.74, 0.6), 0.5, 0.0),
    "concrete": ((0.5, 0.48, 0.44), 0.85, 0.0),
    "brick": ((0.45, 0.25, 0.18), 0.85, 0.0),
    "soil": ((0.12, 0.09, 0.06), 0.95, 0.0),
    "plant_dead": ((0.3, 0.24, 0.13), 0.8, 0.0),
    "wood": ((0.42, 0.27, 0.15), 0.6, 0.0),
    "stone": ((0.7, 0.66, 0.58), 0.5, 0.0),
    "water": ((0.08, 0.1, 0.09), 0.05, 0.0),
    "plastic_orange": ((0.75, 0.33, 0.08), 0.45, 0.0),
    "plastic_yellow": ((0.85, 0.7, 0.1), 0.45, 0.0),
    "fabric": ((0.35, 0.3, 0.32), 0.9, 0.0),
    "dark": ((0.02, 0.02, 0.02), 0.9, 0.0),
    "carpet": ((0.25, 0.18, 0.2), 0.95, 0.0),
    "screen": ((0.1, 0.25, 0.2), 0.3, 1.2),
}


def mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    col, rough, em = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    if em:
        b.inputs["Emission Color"].default_value = (*col, 1)
        b.inputs["Emission Strength"].default_value = em
    if name == "glass":
        b.inputs["Transmission Weight"].default_value = 0.9
        b.inputs["Alpha"].default_value = 0.35
    return m


class Builder:
    """Collects geometry into one bmesh with per-face materials."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def _mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def _add(self, tmp, m, matrix):
        mi = self._mi(m)
        bmesh.ops.transform(tmp, matrix=matrix, verts=tmp.verts)
        me = bpy.data.meshes.new("_t")
        tmp.to_mesh(me)
        tmp.free()
        for p in me.polygons:
            p.material_index = mi
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def box(self, size, loc, m, rot=(0, 0, 0), bevel=0.0):
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        bmesh.ops.scale(t, vec=Vector(size), verts=t.verts)
        if bevel > 0:
            bmesh.ops.bevel(t, geom=t.edges[:], offset=min(bevel, min(size) * 0.45), segments=2, affect="EDGES")
        self._add(t, m, Matrix.LocRotScale(Vector(loc), _eul(rot), None))

    def cyl(self, r1, r2, h, loc, m, segs=16, rot=(0, 0, 0), caps=True):
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=caps, segments=segs, radius1=r1, radius2=r2, depth=h)
        self._add(t, m, Matrix.LocRotScale(Vector(loc), _eul(rot), None))

    def sphere(self, r, loc, m, segs=12, rings=8, scale=(1, 1, 1)):
        t = bmesh.new()
        bmesh.ops.create_uvsphere(t, u_segments=segs, v_segments=rings, radius=r)
        bmesh.ops.scale(t, vec=Vector(scale), verts=t.verts)
        self._add(t, m, Matrix.Translation(Vector(loc)))

    def lathe(self, profile, loc, m, segs=24):
        """Surface of revolution from (radius, z) points."""
        t = bmesh.new()
        rings = []
        for r, z in profile:
            ring = [t.verts.new((r * math.cos(2 * math.pi * k / segs), r * math.sin(2 * math.pi * k / segs), z)) for k in range(segs)]
            rings.append(ring)
        for a, b in zip(rings, rings[1:]):
            for k in range(segs):
                k2 = (k + 1) % segs
                t.faces.new((a[k], a[k2], b[k2], b[k]))
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        self._add(t, m, Matrix.Translation(Vector(loc)))

    def tube(self, pts, r, m, segs=6):
        """Thin bent rod through points (wire, rails, branches)."""
        for a, b in zip(pts, pts[1:]):
            a, b = Vector(a), Vector(b)
            d = b - a
            q = d.to_track_quat("Z", "Y")
            t = bmesh.new()
            bmesh.ops.create_cone(t, cap_ends=False, segments=segs, radius1=r, radius2=r, depth=d.length)
            self._add(t, m, Matrix.LocRotScale((a + b) / 2, q, None))

    def quad(self, corners, m):
        t = bmesh.new()
        vs = [t.verts.new(c) for c in corners]
        t.faces.new(vs)
        self._add(t, m, Matrix.Identity(4))

    def place(self, other, matrix):
        """Merge another Builder's geometry, transformed."""
        me = other.to_mesh("_p")
        t = bmesh.new()
        t.from_mesh(me)
        bmesh.ops.transform(t, matrix=matrix, verts=t.verts)
        remap = [self._mi(n) for n in other.mats]
        for f in t.faces:
            f.material_index = remap[f.material_index]
        me2 = bpy.data.meshes.new("_t")
        t.to_mesh(me2)
        t.free()
        self.bm.from_mesh(me2)
        bpy.data.meshes.remove(me2)
        bpy.data.meshes.remove(me)

    def to_mesh(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        for n in self.mats:
            me.materials.append(mat(n))
        return me

    def to_object(self, name, coll=None):
        ob = bpy.data.objects.new(name, self.to_mesh(name))
        (coll or bpy.context.scene.collection).objects.link(ob)
        return ob


def _eul(rot):
    from mathutils import Euler
    return Euler(rot).to_quaternion()


# ---------------------------------------------------------------- props ---
def bench():
    """Mall bench: wooden slats on two cast-metal side frames, armrests."""
    b = Builder()
    L = 1.8
    for x in (-L / 2 + 0.12, L / 2 - 0.12):
        b.box((0.06, 0.5, 0.06), (x, 0, 0.03), "metal_frame", bevel=0.01)          # foot
        b.box((0.05, 0.06, 0.42), (x, 0.0, 0.24), "metal_frame", bevel=0.01)       # leg
        b.box((0.05, 0.42, 0.04), (x, 0.02, 0.43), "metal_frame", bevel=0.01)      # seat bearer
        b.box((0.05, 0.05, 0.4), (x, 0.22, 0.64), "metal_frame", (-0.25, 0, 0), bevel=0.01)  # back post
        b.box((0.07, 0.42, 0.04), (x, 0.0, 0.66), "metal_frame", bevel=0.015)      # armrest
        b.box((0.04, 0.04, 0.22), (x, -0.17, 0.55), "metal_frame", bevel=0.008)
    for k in range(5):
        b.box((L, 0.07, 0.03), (0, -0.16 + k * 0.08, 0.465), "wood", bevel=0.008)
    for k in range(3):
        b.box((L - 0.1, 0.03, 0.08), (0, 0.23 + 0.03 * k, 0.6 + k * 0.1), "wood", (-0.25, 0, 0), bevel=0.008)
    return b


def planter(dead_palm=True):
    """Octagonal concrete planter with a dead palm or dry shrub."""
    b = Builder()
    b.cyl(0.62, 0.58, 0.55, (0, 0, 0.275), "concrete", segs=8)
    b.cyl(0.66, 0.66, 0.06, (0, 0, 0.58), "concrete", segs=8)
    b.cyl(0.55, 0.55, 0.02, (0, 0, 0.56), "soil", segs=8)
    if dead_palm:
        pts = []
        for k in range(9):
            z = 0.56 + k * 0.32
            pts.append((0.02 * math.sin(k * 0.9) + 0.008 * k, 0.015 * k, z))
        for a, c in zip(pts, pts[1:]):
            b.cyl(0.09 - 0.004 * pts.index(a), 0.085 - 0.004 * pts.index(a), 0.33, ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2, (a[2] + c[2]) / 2), "plant_dead", segs=10)
            b.cyl(0.1, 0.1, 0.03, a, "plant_dead", segs=10)          # leaf-scar rings
        top = Vector(pts[-1])
        for k in range(9):
            ang = 2 * math.pi * k / 9 + 0.3
            droop = 0.5 + 0.5 * (k % 3) / 2
            frond = [top]
            for s in range(1, 6):
                t = s / 5
                frond.append(top + Vector((math.cos(ang) * 1.1 * t, math.sin(ang) * 1.1 * t, 0.35 * t - droop * 1.4 * t * t)))
            b.tube(frond, 0.012, "plant_dead", 5)
            for s in range(1, 5):
                p = frond[s]
                for side in (-1, 1):
                    q = p + Vector((-math.sin(ang) * side * 0.18, math.cos(ang) * side * 0.18, -0.25))
                    b.tube([p, q], 0.006, "plant_dead", 4)
    else:
        import random
        rnd = random.Random(4)
        for k in range(14):
            a = rnd.uniform(0, 2 * math.pi)
            r = rnd.uniform(0.0, 0.25)
            base = Vector((math.cos(a) * r, math.sin(a) * r, 0.57))
            tip = base + Vector((math.cos(a) * rnd.uniform(0.1, 0.4), math.sin(a) * rnd.uniform(0.1, 0.4), rnd.uniform(0.4, 0.9)))
            mid = base.lerp(tip, 0.5) + Vector((rnd.uniform(-0.08, 0.08), rnd.uniform(-0.08, 0.08), 0))
            b.tube([base, mid, tip], 0.008, "plant_dead", 4)
    return b


def trash_bin():
    b = Builder()
    for k in range(16):       # vertical slats
        a = 2 * math.pi * k / 16
        b.box((0.06, 0.02, 0.78), (math.cos(a) * 0.28, math.sin(a) * 0.28, 0.43), "metal_frame", (0, 0, a + math.pi / 2))
    b.cyl(0.3, 0.3, 0.05, (0, 0, 0.06), "metal_frame", 16)
    b.cyl(0.31, 0.31, 0.04, (0, 0, 0.82), "metal_frame", 16)
    b.lathe([(0.31, 0.84), (0.3, 0.9), (0.24, 0.98), (0.12, 1.02), (0.0, 1.03)], (0, 0, 0), "metal_frame", 16)
    b.box((0.2, 0.06, 0.08), (0, -0.27, 0.92), "dark")          # opening
    b.cyl(0.26, 0.26, 0.5, (0, 0, 0.32), "dark", 12)            # liner
    return b


def wet_floor_sign():
    b = Builder()
    for s in (-1, 1):
        b.box((0.32, 0.02, 0.62), (0, s * 0.11, 0.31), "plastic_yellow", (s * 0.2, 0, 0), bevel=0.01)
        b.box((0.22, 0.004, 0.08), (0, s * 0.125, 0.4), "dark", (s * 0.2, 0, 0))
    b.box((0.06, 0.06, 0.08), (0, 0, 0.64), "plastic_yellow", bevel=0.02)
    return b


def kiosk():
    """Cart kiosk with a canopy roof, counters and empty shelves."""
    b = Builder()
    b.box((2.4, 1.4, 0.95), (0, 0, 0.5), "wood", bevel=0.03)
    b.box((2.5, 1.5, 0.05), (0, 0, 1.0), "sign_cream", bevel=0.01)
    for x in (-1.15, 1.15):
        for y in (-0.65, 0.65):
            b.cyl(0.035, 0.035, 1.3, (x, y, 1.65), "metal_bright", 8)
    b.box((2.7, 1.7, 0.08), (0, 0, 2.32), "sign_teal", bevel=0.02)
    for k in range(6):       # striped canopy
        b.box((2.7 / 6 - 0.01, 1.9, 0.03), (-1.35 + 2.7 / 12 + k * 2.7 / 6, 0, 2.42 + 0.02 * (k % 2)), "sign_red" if k % 2 else "sign_cream", (0.08, 0, 0))
    b.box((1.6, 0.04, 0.3), (0, -0.86, 2.15), "sign_cream")          # name board (blank)
    for z in (1.25, 1.55, 1.85):
        b.box((2.2, 0.3, 0.02), (0, 0.45, z), "wood")
    b.box((2.3, 0.05, 1.1), (0, 0.66, 1.55), "dark")
    return b


def directory_sign():
    b = Builder()
    b.box((0.9, 0.25, 2.1), (0, 0, 1.05), "metal_frame", bevel=0.03)
    b.box((0.72, 0.02, 1.1), (0, -0.13, 1.3), "screen")
    for k in range(7):
        b.box((0.5 - 0.05 * (k % 3), 0.01, 0.035), (-0.05, -0.145, 1.75 - k * 0.07), "sign_cream")
    b.box((0.9, 0.3, 0.06), (0, 0, 2.13), "sign_red")
    return b


def table_set():
    """Food court table with four moulded chairs."""
    b = Builder()
    b.cyl(0.42, 0.42, 0.03, (0, 0, 0.74), "plastic_orange", 20)
    b.cyl(0.035, 0.035, 0.72, (0, 0, 0.37), "metal_bright", 8)
    b.cyl(0.25, 0.27, 0.03, (0, 0, 0.015), "metal_bright", 12)
    for k in range(4):
        a = math.pi / 2 * k + 0.25
        c = Vector((math.cos(a) * 0.68, math.sin(a) * 0.68, 0))
        ch = Builder()
        ch.box((0.42, 0.42, 0.04), (0, 0, 0.45), "plastic_orange", bevel=0.015)
        ch.box((0.42, 0.04, 0.4), (0, 0.2, 0.68), "plastic_orange", (-0.15, 0, 0), bevel=0.015)
        for x in (-0.18, 0.18):
            for y in (-0.18, 0.18):
                ch.cyl(0.012, 0.012, 0.44, (x, y, 0.22), "metal_bright", 6)
        b.place(ch, Matrix.LocRotScale(c, _eul((0, 0, a + math.pi / 2 + (0.3 if k == 2 else 0))), None))
    return b


def shopping_cart():
    b = Builder()
    L, W_, H = 0.9, 0.55, 0.5
    z0 = 0.45
    for i in range(10):
        x = -L / 2 + i * L / 9
        b.tube([(x, -W_ / 2, z0), (x, -W_ / 2, z0 + H)], 0.004, "metal_bright", 4)
        b.tube([(x, W_ / 2, z0), (x, W_ / 2, z0 + H)], 0.004, "metal_bright", 4)
        b.tube([(x, -W_ / 2, z0), (x, W_ / 2, z0)], 0.004, "metal_bright", 4)
    for z in (z0, z0 + H * 0.5, z0 + H):
        b.tube([(-L / 2, -W_ / 2, z), (L / 2, -W_ / 2, z), (L / 2, W_ / 2, z), (-L / 2, W_ / 2, z), (-L / 2, -W_ / 2, z)], 0.006, "metal_bright", 5)
    b.tube([(L / 2, -W_ / 2, z0 + H), (L / 2 + 0.15, -W_ / 2, z0 + H + 0.2), (L / 2 + 0.15, W_ / 2, z0 + H + 0.2), (L / 2, W_ / 2, z0 + H)], 0.012, "plastic_orange", 6)
    for x in (-L / 2 + 0.05, L / 2 - 0.05):
        for y in (-W_ / 2 + 0.05, W_ / 2 - 0.05):
            b.tube([(x, y, z0), (x * 0.9, y, 0.08)], 0.01, "metal_bright", 5)
            b.cyl(0.05, 0.05, 0.025, (x * 0.9, y, 0.05), "dark", 10, rot=(math.pi / 2, 0, 0))
    return b


def payphone():
    b = Builder()
    b.box((0.4, 0.25, 0.7), (0, 0, 1.4), "metal_bright", bevel=0.02)
    b.box((0.3, 0.02, 0.2), (0, -0.13, 1.55), "dark")
    for r in range(4):
        for c in range(3):
            b.box((0.04, 0.01, 0.03), (-0.05 + c * 0.05, -0.13, 1.35 - r * 0.045), "metal_frame")
    b.box((0.06, 0.07, 0.22), (0.15, -0.16, 1.4), "dark", bevel=0.02)
    b.tube([(0.15, -0.16, 1.29), (0.1, -0.2, 1.05), (0.12, -0.16, 0.95)], 0.005, "dark", 4)
    b.box((0.55, 0.38, 0.03), (0, 0.05, 1.8), "metal_bright")
    return b


def fountain():
    """Three tiers of terrazzo-clad bowls, long dry; a stagnant puddle and
    old coins in the bottom of the basin."""
    b = Builder()
    b.lathe([(3.0, 0.0), (3.0, 0.45), (2.85, 0.5), (2.75, 0.5), (2.75, 0.12), (0.0, 0.12)], (0, 0, 0), "stone", 48)
    b.lathe([(3.05, 0.45), (3.08, 0.52), (2.72, 0.52)], (0, 0, 0), "stone", 48)
    b.cyl(2.7, 2.7, 0.01, (0, 0, 0.14), "water", 40)
    b.lathe([(0.45, 0.12), (0.4, 1.1), (0.3, 1.2), (0.32, 1.3)], (0, 0, 0), "stone", 24)
    b.lathe([(0.32, 1.3), (1.4, 1.42), (1.6, 1.6), (1.55, 1.65), (1.35, 1.5), (0.3, 1.42)], (0, 0, 0), "stone", 36)
    b.lathe([(0.2, 1.6), (0.17, 2.3), (0.12, 2.35)], (0, 0, 0), "stone", 18)
    b.lathe([(0.12, 2.35), (0.7, 2.42), (0.82, 2.55), (0.76, 2.58), (0.62, 2.48), (0.12, 2.45)], (0, 0, 0), "stone", 28)
    b.lathe([(0.08, 2.5), (0.06, 2.8), (0.12, 2.86), (0.0, 3.0)], (0, 0, 0), "metal_bright", 12)
    import random
    rnd = random.Random(9)
    for k in range(60):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.6, 2.6)
        b.cyl(0.012, 0.012, 0.003, (math.cos(a) * r, math.sin(a) * r, 0.152), "metal_bright", 8)
    return b


def escalator(length=7.0, rise=4.2):
    """A dead escalator climbing into the dark."""
    b = Builder()
    steps = 22
    for k in range(steps):
        t = k / (steps - 1)
        y = t * length
        z = t * rise
        b.box((1.0, length / steps + 0.02, 0.06), (0, y, z + 0.1), "metal_bright")
        b.box((1.0, 0.03, rise / steps), (0, y - length / steps / 2, z + 0.1 - rise / steps / 2), "metal_frame")
    for x in (-0.62, 0.62):
        b.quad([(x, -0.6, 0.0), (x, length + 0.6, rise), (x, length + 0.6, rise + 1.0), (x, -0.6, 1.0)], "glass")
        b.box((0.14, length * 1.2, 0.5), (x, length / 2, rise / 2 - 0.1), "metal_frame", (math.atan2(rise, length), 0, 0))
        b.tube([(x, -0.8, 1.0), (x, -0.4, 1.0), (x, length + 0.4, rise + 1.0), (x, length + 0.8, rise + 1.0)], 0.04, "dark", 8)
    b.box((1.6, length * 1.15, 0.4), (0, length / 2, rise / 2 - 0.45), "metal_frame", (math.atan2(rise, length), 0, 0))
    return b


def clothes_rack():
    b = Builder()
    b.tube([(-0.6, 0, 0.05), (-0.6, 0, 1.5), (0.6, 0, 1.5), (0.6, 0, 0.05)], 0.015, "metal_bright", 8)
    for x in (-0.6, 0.6):
        b.box((0.06, 0.5, 0.03), (x, 0, 0.02), "metal_bright")
    import random
    rnd = random.Random(2)
    for k in range(9):
        x = -0.5 + k * 0.125 + rnd.uniform(-0.02, 0.02)
        b.tube([(x, 0, 1.5), (x, 0, 1.44)], 0.003, "metal_bright", 4)
        b.tube([(x, -0.2, 1.4), (x, 0, 1.44), (x, 0.2, 1.4)], 0.004, "metal_bright", 4)
        if rnd.random() < 0.45:
            b.box((0.04, 0.42, 0.7), (x, 0, 1.05), "fabric", bevel=0.01)
    return b


def shelving():
    b = Builder()
    b.box((1.2, 0.04, 2.0), (0, 0.18, 1.0), "metal_frame")
    for x in (-0.58, 0.58):
        b.box((0.03, 0.4, 2.0), (x, 0, 1.0), "metal_frame")
    for z in (0.1, 0.5, 0.9, 1.3, 1.7):
        b.box((1.15, 0.38, 0.025), (0, 0, z), "metal_bright")
    import random
    rnd = random.Random(5)
    for z in (0.1, 0.5, 0.9, 1.3, 1.7):
        for k in range(rnd.randint(0, 3)):
            b.box((rnd.uniform(0.08, 0.2), rnd.uniform(0.1, 0.25), rnd.uniform(0.08, 0.25)),
                  (rnd.uniform(-0.45, 0.45), rnd.uniform(-0.06, 0.06), z + 0.08), rnd.choice(["sign_cream", "sign_red", "sign_teal", "wood"]))
    return b


def counter():
    b = Builder()
    b.box((2.4, 0.7, 1.0), (0, 0, 0.5), "wood", bevel=0.02)
    b.box((2.5, 0.8, 0.04), (0, 0, 1.02), "stone", bevel=0.01)
    b.box((0.4, 0.35, 0.22), (-0.6, 0.0, 1.15), "dark", bevel=0.02)         # register
    b.box((0.36, 0.02, 0.15), (-0.6, -0.18, 1.2), "screen")
    return b


def mannequin_base():
    """An empty display stand: the rod torn out (the clue)."""
    b = Builder()
    b.cyl(0.2, 0.2, 0.012, (0, 0.12, 0.006), "metal_bright", 32)
    b.cyl(0.009, 0.009, 0.12, (0.104, 0.12, 0.07), "metal_bright", 8)
    b.tube([(0.104, 0.12, 0.13), (0.11, 0.1, 0.17), (0.09, 0.07, 0.18)], 0.009, "metal_bright", 6)
    return b


def round_rack():
    """Department-store round clothes rack, a few garments left on it."""
    b = Builder()
    b.cyl(0.32, 0.36, 0.04, (0, 0, 0.02), "metal_bright", 20)
    b.cyl(0.02, 0.02, 1.3, (0, 0, 0.67), "metal_bright", 8)
    b.lathe([(0.55, 1.3), (0.57, 1.3), (0.57, 1.33), (0.55, 1.33)], (0, 0, 0), "metal_bright", 24)
    for k in range(4):
        a = k * math.pi / 2
        b.tube([(0, 0, 1.3), (math.cos(a) * 0.56, math.sin(a) * 0.56, 1.31)], 0.01, "metal_bright", 6)
    import random
    rnd = random.Random(9)
    for k in range(22):
        if rnd.random() < 0.5:
            continue
        a = 2 * math.pi * k / 22
        b.box((0.42, 0.04, 0.75), (math.cos(a) * 0.56, math.sin(a) * 0.56, 0.92), "fabric", (0, 0, a + math.pi / 2), bevel=0.01)
    return b


def display_table():
    """Low display table with a few folded clothes and a price card."""
    b = Builder()
    b.box((1.6, 0.9, 0.06), (0, 0, 0.78), "wood", bevel=0.01)
    for x in (-0.72, 0.72):
        b.box((0.08, 0.8, 0.75), (x, 0, 0.375), "wood")
    b.box((1.4, 0.7, 0.03), (0, 0, 0.25), "wood")
    import random
    rnd = random.Random(13)
    for k in range(rnd.randint(2, 5)):
        b.box((0.32, 0.26, 0.05 * rnd.randint(1, 3)), (rnd.uniform(-0.55, 0.55), rnd.uniform(-0.2, 0.2), 0.83), rnd.choice(["fabric", "sign_cream", "sign_teal"]), (0, 0, rnd.uniform(-0.3, 0.3)))
    b.box((0.12, 0.02, 0.09), (0.6, -0.3, 0.86), "sign_cream", (-0.4, 0, 0))
    return b


def glass_case():
    """Cosmetics / jewellery counter: glass box on a dark base, a lit shelf."""
    b = Builder()
    b.box((1.8, 0.6, 0.55), (0, 0, 0.275), "metal_frame", bevel=0.01)
    b.box((1.8, 0.6, 0.03), (0, 0, 0.56), "stone")
    for x in (-0.89, 0.89):
        b.box((0.02, 0.6, 0.45), (x, 0, 0.8), "metal_bright")
    b.quad([(-0.88, -0.3, 0.58), (0.88, -0.3, 0.58), (0.88, -0.3, 1.02), (-0.88, -0.3, 1.02)], "glass")
    b.quad([(-0.88, 0.3, 0.58), (-0.88, -0.3, 1.02), (0.88, -0.3, 1.02), (0.88, 0.3, 0.58)], "glass")
    b.box((1.8, 0.6, 0.02), (0, 0, 1.03), "metal_bright")
    b.box((1.7, 0.4, 0.01), (0, 0, 0.6), "light_panel")
    import random
    rnd = random.Random(17)
    for k in range(6):
        b.cyl(0.03, 0.03, rnd.uniform(0.06, 0.14), (rnd.uniform(-0.75, 0.75), rnd.uniform(-0.15, 0.15), 0.66), rnd.choice(["sign_red", "sign_cream", "metal_bright"]), 8)
    return b


def fitting_rooms():
    """Three fitting-room booths with curtains (one torn half down)."""
    b = Builder()
    for k in range(4):
        b.box((0.05, 1.3, 2.2), (-1.5 + k * 1.0, 0, 1.1), "wall_paint")
    b.box((3.05, 0.05, 2.2), (0, 0.65, 1.1), "wall_paint")
    b.box((3.1, 1.35, 0.05), (0, 0, 2.22), "wall_paint")
    for k in range(3):
        x = -1.0 + k * 1.0
        b.tube([(x - 0.47, -0.62, 2.05), (x + 0.47, -0.62, 2.05)], 0.01, "metal_bright", 6)
        h = 1.9 if k != 1 else 1.1
        b.box((0.9 if k != 2 else 0.4, 0.02, h), (x if k != 2 else x - 0.25, -0.62, 2.05 - h / 2), "fabric")
        b.box((0.5, 0.02, 0.9), (x, 0.62, 1.4), "glass")       # mirror
        b.box((0.4, 0.3, 0.05), (x + 0.2, 0.45, 0.45), "wood")  # stool seat
    return b


def arcade_cabinet():
    """Upright arcade cabinet, its attract screen still glowing."""
    b = Builder()
    b.box((0.7, 0.75, 1.0), (0, 0, 0.5), "dark", bevel=0.02)
    b.box((0.7, 0.4, 0.8), (0, 0.17, 1.4), "dark", bevel=0.02)
    b.box((0.72, 0.5, 0.06), (0, -0.12, 1.02), "sign_red", (-0.25, 0, 0))     # control panel
    b.box((0.56, 0.02, 0.44), (0, -0.04, 1.4), "screen", (-0.15, 0, 0))
    b.box((0.7, 0.42, 0.22), (0, 0.15, 1.92), "sign_teal", bevel=0.01)         # marquee
    b.box((0.6, 0.02, 0.14), (0, -0.07, 1.92), "light_panel")
    for x in (-0.15, 0.15):
        b.cyl(0.025, 0.025, 0.08, (x, -0.2, 1.1), "sign_cream", 8)
    b.box((0.2, 0.02, 0.12), (0, -0.38, 0.55), "sign_cream")                    # coin slot plate
    return b


PROPS = {
    "bench": bench, "planter_palm": lambda: planter(True), "planter_shrub": lambda: planter(False),
    "trash_bin": trash_bin, "wet_floor_sign": wet_floor_sign, "kiosk": kiosk, "directory": directory_sign,
    "table_set": table_set, "shopping_cart": shopping_cart, "payphone": payphone, "fountain": fountain,
    "escalator": escalator, "clothes_rack": clothes_rack, "shelving": shelving, "counter": counter,
    "empty_stand": mannequin_base, "round_rack": round_rack, "display_table": display_table,
    "glass_case": glass_case, "fitting_rooms": fitting_rooms, "arcade_cabinet": arcade_cabinet,
}
