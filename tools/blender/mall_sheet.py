"""Renders every Dead Mall prop on a contact sheet: python mall_sheet.py <out.png> [--fast]"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402,I001
import mall_props as P  # noqa: E402
from mathutils import Vector  # noqa: E402

OUT = sys.argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
names = [n for n in P.PROPS if n not in ("fountain", "escalator")]
cols = 5
cell = 3.2
for i, n in enumerate(names):
    ob = P.PROPS[n]().to_object(n)
    ob.location = ((i % cols) * cell, -(i // cols) * cell * 0.9, 0)
    for p in ob.data.polygons:
        p.use_smooth = False
big = [("fountain", (cell * 5.8, -2.6, 0)), ("escalator", (cell * 5.8, -11.0, 0))]
for n, loc in big:
    ob = P.PROPS[n]().to_object(n)
    ob.location = loc
    if n == "escalator":
        ob.rotation_euler = (0, 0, math.radians(-25))
fl = P.Builder()
fl.box((60, 40, 0.02), (7, -7, -0.01), "terrazzo")
fl.to_object("floor")
bpy.ops.object.light_add(type="SUN", location=(0, 0, 10))
sun = bpy.context.object
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(30))
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.27, 0.3, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
scene.world = w
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = 25
cam.location = Vector((9.5, -24, 18))
cam.rotation_euler = (Vector((9.5, -6.5, 0.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 24 if "--fast" in sys.argv else 64
scene.cycles.use_denoising = True
scene.render.resolution_x = 2000
scene.render.resolution_y = 1300
scene.view_settings.view_transform = "AgX"
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("rendered", OUT, "props", len(names) + 2)
