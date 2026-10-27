"""Side level kit helpers (Blender 5.x, `bpy` as a module), made from what
mall_kit.py / mall_props.py do for the Dead Mall: build a level section in
code, unwrap it, bake its light in Cycles, export a GLB for
SideLevel.load_kit().

A level's own script (tools/blender/levels/<id>.py) does:

    import os, sys
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import level_kit as K

    K.reset()
    K.material("concrete", (0.5, 0.48, 0.44), rough=0.85)
    K.material("paint", (0.7, 0.68, 0.6), rough=0.9)
    K.material("lamp", (1.0, 0.97, 0.9), emit=8.0)               # always on
    K.material("bank_a", (1.0, 0.97, 0.9), emit=8.0, group=0)    # light group 0
    kit = K.Kit("hall")
    b = kit.b                                     # a Builder (geometry)
    K.room(b, (-6, -4, 0), (6, 4, 3), floor="concrete", wall="paint", ceiling="paint")
    b.box((1.2, 0.6, 0.02), (0, 0, 2.99), "bank_a")
    K.point_light(kit, (0, 0, 2.7), 40.0, group=0)               # a real lamp in the bank
    kit.col((12, 8, 0.2), (0, 0, -0.1))           # collision boxes
    kit.spot("spot_arrival", (-5, 0, 0), math.pi / 2)
    kit.export("assets/levels/<id>", lm=1024, samples=96)

which writes, under the out dir:
  <name>.glb                   the mesh (UV = texture coordinates, UV2 =
                               lightmap), "-colonly" collision boxes,
                               "spot_*" empties; materials by name
  lightmaps/<name>.png         the colour bake (static lights only), stored
                               as sqrt(light / LM_SCALE)
  lightmaps/<name>_groups.png  if any light groups: R, G, B, A = groups 0..3
                               baked alone, grey, sqrt(light / GROUP_SCALE)
  and .import files for both (lossless, no mipmaps, and no alpha border
  fix: Godot's default would overwrite R, G, B wherever group 3 is dark).

Coordinates are Blender's (Z up); glTF turns them into Godot's (Y up):
Godot (x, y, z) = Blender (x, z, -y). Faces need their normals pointing
into the room (box() and room() do; for quads use oquad()).

Lighting model (match the Godot shader, level_lit.gdshaderinc): the colour
lightmap is irradiance (DIFFUSE bake, direct + indirect, no colour pass);
the shader multiplies it by the surface colour. Lamps you can see are
emissive materials (their glow is the shader's `emit`, so give the Godot
surface the same group). Light groups bake the same way, one at a time,
with everything else dark, so a group's map holds its own light and bounce;
the game multiplies each by its colour * intensity (SideLevel
.set_light_group). The colour bake holds only what's always on.

Run:  /tmp/claude-0/bpyenv/bin/python tools/blender/levels/<id>.py [--fast]
"""
import math
import os
import sys

import bpy  # noqa: I001  (bmesh only exists once bpy is imported)
import bmesh
import numpy as np
from mathutils import Euler, Matrix, Vector

LM_SCALE = 4.0          # colour lightmap stores sqrt(light / LM_SCALE)  (SideLevel: lm_scale)
GROUP_SCALE = 4.0       # group lightmap stores sqrt(light / GROUP_SCALE) (SideLevel: group_scale)
FAST = "--fast" in sys.argv

# name -> dict(color, rough, emit, group, metal)
MATS = {}
_LIGHTS = []            # (object, group)


def reset():
    """An empty scene (call first)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    _LIGHTS.clear()


def material(name, color, rough=0.7, emit=0.0, group=-1, metal=0.0):
    """Declares a material. `name` is what the Godot side looks the surface
    up by (load_kit's surfaces table, textures <name>_diff.jpg...). `color`
    tints the light bounce in the bake (use the texture's average colour).
    emit: lamp strength (W/m2-ish, 5..12 for a fluorescent diffuser);
    group: the light group (0..3) the lamp belongs to, -1 always on."""
    MATS[name] = {"color": color, "rough": rough, "emit": emit, "group": group, "metal": metal}
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


def _mat(name):
    if name not in MATS:
        material(name, (0.6, 0.6, 0.6))
    return bpy.data.materials[name]


def _eul(rot):
    return Euler(rot).to_quaternion()


class Builder:
    """Collects geometry into one bmesh with per-face materials (as
    mall_props.Builder)."""

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
        """A box (size x, y, z; centre loc), normals out."""
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

    def tube(self, pts, r, m, segs=6):
        """A thin rod through points (pipes, rails, handrails)."""
        for a, b in zip(pts, pts[1:]):
            a, b = Vector(a), Vector(b)
            d = b - a
            t = bmesh.new()
            bmesh.ops.create_cone(t, cap_ends=False, segments=segs, radius1=r, radius2=r, depth=d.length)
            self._add(t, m, Matrix.LocRotScale((a + b) / 2, d.to_track_quat("Z", "Y"), None))

    def quad(self, corners, m):
        t = bmesh.new()
        t.faces.new([t.verts.new(c) for c in corners])
        self._add(t, m, Matrix.Identity(4))

    def oquad(self, corners, m, toward):
        """A one-sided quad facing the point `toward` (into the room)."""
        a, c1, c2 = (Vector(v) for v in corners[:3])
        if (c1 - a).cross(c2 - a).dot(Vector(toward) - a) < 0:
            corners = list(reversed(corners))
        self.quad(corners, m)

    def wall(self, a, b, z0, z1, thick, m):
        """A wall from 2D point a to b (its centre line), z0..z1 high."""
        a, b = Vector((*a, 0)), Vector((*b, 0))
        d = b - a
        self.box((d.length, thick, z1 - z0), ((a + b) / 2) + Vector((0, 0, (z0 + z1) / 2)), m,
                 rot=(0, 0, math.atan2(d.y, d.x)))

    def slab(self, x0, y0, x1, y1, z, thick, m):
        """A floor / ceiling slab, its top at z."""
        self.box((x1 - x0, y1 - y0, thick), ((x0 + x1) / 2, (y0 + y1) / 2, z - thick / 2), m)

    def place(self, other, matrix):
        """Merges another Builder's geometry, transformed (props)."""
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
            me.materials.append(_mat(n))
        return me


def room(b, lo, hi, floor, wall, ceiling, thick=0.2):
    """A closed box room seen from inside (inner faces only): floor, four
    walls, ceiling; lo/hi are its inner corners. Cut doorways by building
    walls yourself instead (b.wall)."""
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    b.oquad([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], floor, c)
    b.oquad([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], ceiling, c)
    b.oquad([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], wall, c)
    b.oquad([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], wall, c)
    b.oquad([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], wall, c)
    b.oquad([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], wall, c)


def point_light(kit, loc, watts, color=(1.0, 0.95, 0.85), radius=0.1, group=-1):
    """A Blender point light (baked only; add a real light in Godot for
    things that move through it)."""
    return _light(kit, "POINT", loc, watts, color, group, radius=radius)


def area_light(kit, loc, size, watts, color=(1.0, 0.95, 0.85), group=-1, rot=(0, 0, 0)):
    """A rectangular area light facing down (-Z) unless rotated."""
    return _light(kit, "AREA", loc, watts, color, group, size=size, rot=rot)


def spot_light(kit, loc, watts, angle_deg=60.0, color=(1.0, 0.95, 0.85), group=-1, rot=(0, 0, 0)):
    return _light(kit, "SPOT", loc, watts, color, group, angle=angle_deg, rot=rot)


def _light(kit, kind, loc, watts, color, group, radius=0.1, size=(1.0, 1.0), angle=60.0, rot=(0, 0, 0)):
    ld = bpy.data.lights.new(f"L{len(_LIGHTS)}", kind)
    ld.energy = watts
    ld.color = color
    if kind == "POINT":
        ld.shadow_soft_size = radius
    elif kind == "AREA":
        ld.shape = "RECTANGLE"
        ld.size, ld.size_y = size
    elif kind == "SPOT":
        ld.spot_size = math.radians(angle)
    ob = bpy.data.objects.new(ld.name, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    ob.rotation_euler = rot
    _LIGHTS.append((ob, group))
    return ob


class Kit:
    """One exported section: geometry (self.b), collision boxes, spots."""

    def __init__(self, name):
        self.name = name
        self.b = Builder()
        self.cols = []          # (size, loc, rot_z)
        self.spots = []         # (name, loc, rot_z)
        self.sky = None         # (colour, strength) world light, or None for dark

    def col(self, size, loc, rz=0.0):
        """A collision box (Godot: StaticBody3D). Keep them simple; the
        visual mesh has no collision of its own."""
        self.cols.append((size, loc, rz))

    def spot(self, name, loc, rz=0.0):
        """A named empty ("spot_*"): SideLevel.spots[name] in Godot."""
        self.spots.append((name, loc, rz))

    def export(self, out, lm=1024, samples=96, uv_scale=1.0, margin=0.003, texel_check=True):
        """Unwraps, bakes and exports into `out` (see the module doc).
        uv_scale: metres per texture repeat for the box-projected UVs."""
        os.makedirs(os.path.join(out, "lightmaps"), exist_ok=True)
        scene = bpy.context.scene
        vis = bpy.data.objects.new(self.name, self.b.to_mesh(self.name))
        scene.collection.objects.link(vis)
        for p in vis.data.polygons:
            p.use_smooth = False
        box_uvs(vis, uv_scale)
        lightmap_uvs(vis, margin)
        print(self.name, "tris", sum(len(p.vertices) - 2 for p in vis.data.polygons))
        if FAST:
            lm = min(lm, 512)
            samples = min(samples, 24)
        groups = sorted({g for (_o, g) in _LIGHTS if g >= 0} | {d["group"] for d in MATS.values() if d["emit"] and d["group"] >= 0})
        w = bpy.data.worlds.new("w")
        w.use_nodes = True
        bg = w.node_tree.nodes["Background"]
        col, strength = self.sky if self.sky else ((0, 0, 0), 0.0)
        bg.inputs["Color"].default_value = (*col, 1)
        bg.inputs["Strength"].default_value = strength
        scene.world = w
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = samples
        scene.render.bake.margin = 4
        scene.render.bake.use_selected_to_active = False
        bpy.context.view_layer.objects.active = vis
        for o in bpy.data.objects:
            o.select_set(o == vis)
        # The colour bake: only what's always on.
        rgb = bake(vis, lm, lambda g: g < 0)
        _save_png(np.sqrt(np.clip(rgb / LM_SCALE, 0, 1)), os.path.join(out, "lightmaps", self.name + ".png"), alpha=False)
        if groups:
            if len(groups) > 4 or max(groups) > 3:
                raise ValueError("at most four light groups, 0..3")
            gm = np.zeros((lm, lm, 4))
            for g in groups:
                px = bake(vis, lm, lambda k, g=g: k == g)
                lum = px[:, :, 0] * 0.3 + px[:, :, 1] * 0.59 + px[:, :, 2] * 0.11
                gm[:, :, g] = np.sqrt(np.clip(lum / GROUP_SCALE, 0, 1))
                print(self.name, "group", g, "baked")
            _save_png(gm, os.path.join(out, "lightmaps", self.name + "_groups.png"), alpha=True)
        _restore_emission()
        export_glb(self, vis, out)

    def preview(self, path, cam_loc, look_at, lens=18, samples=32):
        """A quick Cycles render to check the lighting (not the game look)."""
        scene = bpy.context.scene
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scene.collection.objects.link(cam)
        scene.camera = cam
        cam.data.lens = lens
        cam.location = cam_loc
        cam.rotation_euler = (Vector(look_at) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
        for o in bpy.data.objects:
            if o.name.endswith("-colonly"):
                o.hide_render = True
        scene.cycles.samples = samples
        scene.render.resolution_x, scene.render.resolution_y = 1280, 720
        scene.view_settings.view_transform = "AgX"
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)


def box_uvs(ob, scale=1.0):
    """UV map 0 ("uv"): each face projected along its main axis, in metres
    / scale (world-scale tiling for textures; SideLevel uv 0)."""
    me = ob.data
    uv = me.uv_layers.new(name="uv")
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in p.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if ax == 2:
                u, w = v.x, v.y
            elif ax == 0:
                u, w = v.y, v.z
            else:
                u, w = v.x, v.z
            uv.data[li].uv = (u / scale, w / scale)


def lightmap_uvs(ob, margin=0.003):
    """UV map 1 ("lightmap"): a smart unwrap packed into 0..1 (Godot UV2)."""
    me = ob.data
    lmuv = me.uv_layers.new(name="lightmap")
    me.uv_layers.active = lmuv
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, area_weight=1.0)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=margin, rotate=True, shape_method="CONCAVE", scale=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    me.uv_layers.active = me.uv_layers["uv"]
    me.uv_layers["uv"].active_render = True


def _set_emitters(keep):
    """Only lamps (materials and lights) whose group passes keep(group)."""
    for name, d in MATS.items():
        m = bpy.data.materials.get(name)
        if not m or not d["emit"]:
            continue
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Emission Strength"].default_value = d["emit"] if keep(d["group"]) else 0.0
    for ob, g in _LIGHTS:
        ob.hide_render = not keep(g)


def _restore_emission():
    _set_emitters(lambda g: True)


def bake(ob, size, keep):
    """Bakes the light reaching each texel of UV map "lightmap" (DIFFUSE,
    direct + indirect: irradiance) with only the lamps keep(group) passes,
    lightly denoised. Returns float RGB (size x size x 3)."""
    _set_emitters(keep)
    img = bpy.data.images.new(ob.name + "_bake", size, size, alpha=False, float_buffer=True)
    nodes = []
    for m in ob.data.materials:
        nd = m.node_tree.nodes.new("ShaderNodeTexImage")
        nd.image = img
        m.node_tree.nodes.active = nd
        nodes.append((m, nd))
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, uv_layer="lightmap")
    for m, nd in nodes:
        m.node_tree.nodes.remove(nd)
    px = np.array(img.pixels[:]).reshape(size, size, 4)[:, :, :3]
    bpy.data.images.remove(img)
    return _denoise(px)


def _denoise(px):
    """Blurs a little, inside the filled texels only (as mall_kit)."""
    mask = (px.sum(axis=2) > 1e-6).astype(np.float32)
    k = np.array([1, 4, 6, 4, 1], np.float32)
    k /= k.sum()

    def blur(a):
        for ax in (0, 1):
            pad = [(0, 0)] * a.ndim
            pad[ax] = (2, 2)
            ap = np.pad(a, pad, mode="edge")
            a = sum(k[i] * np.take(ap, range(i, i + a.shape[ax]), axis=ax) for i in range(5))
        return a
    num = blur(px * mask[:, :, None])
    den = blur(mask)[:, :, None]
    return np.where(den > 1e-4, num / np.maximum(den, 1e-4), px)


def _save_png(enc, path, alpha):
    """Writes encoded 0..1 values as they are (no colour management) and a
    Godot .import beside it: lossless, no mipmaps, no alpha border fix."""
    h, w = enc.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=alpha)
    img.colorspace_settings.name = "Non-Color"
    if enc.shape[2] == 3:
        enc = np.concatenate([enc, np.ones((h, w, 1))], axis=2)
    img.pixels[:] = enc.ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    if alpha:
        img.alpha_mode = "STRAIGHT"
    img.save()
    bpy.data.images.remove(img)
    write_import(path, lightmap=True)


def write_import(path, lightmap=False, normal=False):
    """A Godot .import for a texture (commit it with the texture): lightmaps
    lossless without mipmaps or alpha border fix; textures VRAM compressed
    with mipmaps (normal maps flagged as such). Godot fills in the rest on
    import."""
    params = {
        "compress/mode": 0 if lightmap else 2,
        "compress/normal_map": 1 if normal else 0,
        "mipmaps/generate": "false" if lightmap else "true",
        "process/fix_alpha_border": "false" if lightmap else "true",
        "detect_3d/compress_to": 0,
    }
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n')
        for k, v in params.items():
            f.write(f"{k}={v}\n")


def export_glb(kit, vis, out):
    """The visual mesh, "-colonly" collision boxes and "spot_*" empties."""
    scene = bpy.context.scene
    objs = [vis]
    for i, (size, loc, rz) in enumerate(kit.cols):
        cb = Builder()
        cb.box(size, (0, 0, 0), next(iter(MATS)) if MATS else "concrete")
        co = bpy.data.objects.new(f"col{i}-colonly", cb.to_mesh(f"col{i}"))
        scene.collection.objects.link(co)
        co.location = loc
        co.rotation_euler = (0, 0, rz)
        objs.append(co)
    for name, loc, rz in kit.spots:
        e = bpy.data.objects.new(name, None)
        scene.collection.objects.link(e)
        e.location = loc
        e.rotation_euler = (0, 0, rz)
        objs.append(e)
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, kit.name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="EXPORT", export_image_format="NONE",
                              export_texcoords=True, export_normals=True)
    print("exported", kit.name, "cols", len(kit.cols), "spots", len(kit.spots))
