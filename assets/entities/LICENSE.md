# Entity figures

From the Innerscene Free Parts Library (https://www.innerscene.com/tools/library/3d-parts),
each marked "Public domain (CC0)": CC0 1.0 Universal, "adapted from MakeHuman
CC0 assets" (MakeHuman/MPFB CC0 body, rig and skin). Library terms:
https://www.innerscene.com/tools/library/terms ("The dedication cannot be
withdrawn once the file is published"). Downloaded 2026-10-19.

- `crawler.glb`: "Human base mesh with editable 53-bone rig",
  https://www.innerscene.com/tools/library/3d-parts/human-base-mesh-with-editable-53-bone-rig-8e7c8ab1
  Both the crawler (posed on all fours in code, `EntityBody.pose_crawl`) and
  the car park's tall one (pitch black, limbs and neck stretched in code).
  Decimated to 16k triangles with `tools/blender/entities_slim.py`.
- `motion.glb`: the skeleton and the Idle_Standing, Walk_Relaxed, Walk_Brisk
  and Run clips of "Locomotion collection - Jordan 3D Person, Animated",
  https://www.innerscene.com/tools/library/3d-parts/locomotion-collection-jordan-3d-person-animated-911f1584
  (same rig family; no meshes), extracted with `tools/blender/entities_motion.py`.
  The tall one walks and runs with these.
