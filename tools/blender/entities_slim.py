# Slims an Innerscene CC0 figure for phones: decimate, small textures,
# fewer clips. usage: python slim.py -- in.glb out.glb target_tris keep_clips(comma) [drop_names(comma)]
import bpy, sys
a = sys.argv[sys.argv.index('--') + 1:]
src, dst, target = a[0], a[1], int(a[2])
keep = a[3].split(',') if len(a) > 3 and a[3] else []
drop = ['Icosphere', 'Briefcase', 'teeth', 'eyelashes', 'Hairline', 'Ankle lining', 'ankle lining'] + (a[4].split(',') if len(a) > 4 else [])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and any(d in o.name for d in drop):
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
total = sum(len(o.data.polygons) for o in meshes)
print('tris before', total)
for o in meshes:
    n = len(o.data.polygons)
    if n < 400:
        continue
    r = min(1.0, target / total)
    m = o.modifiers.new('dec', 'DECIMATE')
    m.ratio = max(r, 300.0 / n)
    # Before the armature, so the weights carry over.
    bpy.context.view_layer.objects.active = o
    while o.modifiers.find('dec') > 0:
        bpy.ops.object.modifier_move_up(modifier='dec')
    bpy.ops.object.modifier_apply(modifier='dec')
print('tris after', sum(len(o.data.polygons) for o in meshes))
for ac in list(bpy.data.actions):
    if keep and ac.name not in keep:
        bpy.data.actions.remove(ac)
for im in bpy.data.images:
    if im.size[0] > 512:
        im.scale(512, 512)
# Normal maps aren't used (the figures are lit by our own shader).
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    for nd in list(mat.node_tree.nodes):
        if nd.type == 'NORMAL_MAP':
            mat.node_tree.nodes.remove(nd)
for im in list(bpy.data.images):
    if im.users == 0:
        bpy.data.images.remove(im)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=True,
        export_animation_mode='ACTIONS', export_image_format='JPEG', export_jpeg_quality=85,
        export_apply=False, export_yup=True)
print('wrote', dst)
