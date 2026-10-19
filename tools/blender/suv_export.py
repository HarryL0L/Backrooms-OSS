"""Builds assets/garage/suv.glb and suv_damaged.glb from "Generic SUV ZYX0"
by 1DInc (CC0, https://www.blendswap.com/blend/29795; the
"snow covered and wrecked" .blend, which holds a clean and a damaged car).

Drops the driver figure and the snow, applies the modifiers, joins
everything but the four doors (kept as DoorFL/FR/RL/RR, origin at the
hinge), decimates for phones, and replaces the materials with flat colours
the game's shader reads by name. Front is -X, left (driver) is -Y.

    python suv_export.py -- <source.blend> clean 0.15 ../../assets/garage/suv.glb
    python suv_export.py -- <source.blend> damaged 0.15 ../../assets/garage/suv_damaged.glb
"""
import bpy, bmesh, sys, math
from mathutils import Vector, Matrix
args = sys.argv[sys.argv.index("--") + 1:]
src, variant, ratio, out = args[0], args[1], float(args[2]), args[3]   # variant: clean | damaged
bpy.ops.wm.open_mainfile(filepath=src)
sc = bpy.context.scene
def centre(o):
    bb=[o.matrix_world@Vector(c) for c in o.bound_box]; return sum(bb,Vector())/8
for o in list(bpy.data.objects):
    if o.type!="MESH" or "_MAN" in o.name or "_SNOW" in o.name:
        bpy.data.objects.remove(o); continue
    dmg = centre(o).x > 3.0
    if dmg != (variant=="damaged"):
        bpy.data.objects.remove(o)
off = 6.0 if variant=="damaged" else 0.0
GROUND = -0.125
dg = bpy.context.evaluated_depsgraph_get()
# flat colours (linear) the game shader reads; names kept
COL = {"X_UCR_CARPAINT":(0.32,0.29,0.25),"X_UCR_CHROME":(0.8,0.79,0.74),"X_UCR_GLASS":(0.05,0.06,0.06),
 "X_UCR_GLASS_RED":(0.58,0.02,0.02),"X_UCR_GREY":(0.21,0.21,0.21),"X_UCR_LEATHER":(0.48,0.43,0.36),
 "X_UCR_LIGHT":(0.85,0.85,0.8),"X_UCR_PLASTIC_BLACK":(0.03,0.03,0.03),"X_UCR_PLASTIC_GREY":(0.06,0.06,0.06),
 "X_UCR_TIRES":(0.025,0.025,0.025),"X_UCR_WHITE":(0.36,0.36,0.36)}
mats={}
for n,c in COL.items():
    m=bpy.data.materials.new("car_"+n[6:].lower()); m.use_nodes=True
    b=m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value=(*c,1)
    mats[n]=m
def bake(o):
    ev=o.evaluated_get(dg); me=bpy.data.meshes.new_from_object(ev, depsgraph=dg)
    me.transform(o.matrix_world)
    me.transform(Matrix.Translation((-off,0,-GROUND)))
    for i,m in enumerate(me.materials):
        me.materials[i]=mats.get(m.name if m else "", mats["X_UCR_PLASTIC_BLACK"])
    return me
doors={}; body=[]
for o in list(bpy.data.objects):
    n=o.name.replace("DMG_","")
    if any(n.startswith("UCR_GENSUV_ZYX0_2SBD.00"+k) for k in "2345"):
        doors[o]=n
    else: body.append(o)
meshes=[bake(o) for o in body]
dlist=[(doors[o],bake(o)) for o in doors]
for o in list(bpy.data.objects): bpy.data.objects.remove(o)
def new_obj(name, me):
    ob=bpy.data.objects.new(name, me); sc.collection.objects.link(ob); return ob
bm=bmesh.new()
allmats=list(mats.values())
bodyme=bpy.data.meshes.new("suv_body")
for m in allmats: bodyme.materials.append(m)
for me in meshes:
    remap=[allmats.index(m) for m in me.materials]
    for p in me.polygons: p.material_index=remap[p.material_index] if remap else 0
    bm.from_mesh(me)
bm.to_mesh(bodyme); bm.free()
bodyo=new_obj("Body", bodyme)
def decimate(ob, r):
    if r>=1: return
    md=ob.modifiers.new("d","DECIMATE"); md.ratio=r; md.use_collapse_triangulate=True
    bpy.context.view_layer.objects.active=ob; ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="d")
decimate(bodyo, ratio)
names={"2":"DoorFL","4":"DoorFR","3":"DoorRL","5":"DoorRR"}
for n,me in dlist:
    xs=[v.co.x for v in me.vertices]; ys=[v.co.y for v in me.vertices]; zs=[v.co.z for v in me.vertices]
    side = -1 if sum(ys)<0 else 1
    # hinge: front edge (-X), inner face of the door
    hinge=Vector((min(xs)+0.04, (min(ys) if side>0 else max(ys)), (min(zs)+max(zs))/2))
    me.transform(Matrix.Translation(-hinge))
    ob=new_obj(names[n[-1]], me); ob.location=hinge
    decimate(ob, ratio)
# markers
for n,p in (("Cabin",(-0.25,0,1.45)),("HeadL",(-2.05,-0.62,0.93)),("HeadR",(-2.05,0.62,0.93)),("TailL",(2.2,-0.68,1.12)),("TailR",(2.2,0.68,1.12))):
    e=bpy.data.objects.new(n,None); sc.collection.objects.link(e); e.location=Vector(p)-Vector((0,0,GROUND))
tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in sc.objects if o.type=="MESH")
print("TRIS", tris)
for o in sc.objects:
    if o.type=="MESH":
        for p in o.data.polygons: p.use_smooth=True
        bpy.context.view_layer.objects.active=o
        for x in sc.objects: x.select_set(x==o)
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_yup=True, export_materials="EXPORT", export_normals=True, export_texcoords=False)
