# Keeps only the armature and its walk/run clips from an Innerscene
# locomotion figure: python motion.py -- in.glb out.glb
import bpy, sys
a = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
for o in list(bpy.data.objects):
    if o.type == 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)
keep = ['Idle_Standing', 'Walk_Relaxed', 'Walk_Brisk', 'Run']
for ac in list(bpy.data.actions):
    if ac.name not in keep:
        bpy.data.actions.remove(ac)
bpy.ops.export_scene.gltf(filepath=a[1], export_format='GLB', export_animations=True,
        export_animation_mode='ACTIONS', export_yup=True)
print('wrote', a[1])
