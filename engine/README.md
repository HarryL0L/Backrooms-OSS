# Engine patches (the Experimental Android build)

The main Android APK uses Godot's **Mobile** renderer, as the Godot docs
recommend ("Forward+ … Supported, but poorly optimized. Use Mobile or
Compatibility instead."). Desktop builds use Forward+ on the stock engine.

The **Experimental** APK (`Backrooms-OSS-Experimental.apk`, package
`io.github.backroomsoss.experimental`, installs next to the normal one) runs
Forward+ on phones using an Android template built in CI with these patches
(the `engine-template` job in `.github/workflows/build.yml`). It's for trying
Forward+-only features such as VoxelGI (Settings → Graphics → Experimental).
Expect a low frame rate: on the Mali-G77 test phone Forward+ ran at ~18 FPS
before any GI.

## 0001-cluster-builder-optional-msaa.patch (Godot 4.7-stable)

On a Mali-G77 MC9 (driver r32p1, `variableMultisampleRate = false`), any
Light3D under Forward+ corrupts every render target: each 8-pixel row strip is
duplicated. Forward+'s light cluster builder rasterizes light volumes into an
attachment-less framebuffer with a hardcoded 4x MSAA pipeline.

Diagnostics with 8 real lights, toggling cluster MSAA live in one session:

| Cluster MSAA | Result |
|---|---|
| on  | corrupted (duplication score 1.000), twice |
| off | clean (0.001), twice |
| no lights | clean |

The patch adds the project setting `rendering/limits/cluster_builder/use_msaa`
(default `true`, read with feature-tag overrides). When it is `false`, the
cluster pass runs without MSAA, and light culling volumes are grown by 15% so
tiles that a light only partly covers aren't missed. Godot 4.8-dev7 does not
change this code.

To use it again:
1. Build the Android template from `${GODOT_VERSION}-stable` with the patch
   applied. Run `misc/scripts/install_swappy_android.py`, then
   `scons platform=android target=template_debug arch=arm64 production=yes`,
   then `./gradlew generateGodotTemplates` in `platform/android/java`.
2. Point an arm64-only Android preset's `custom_template/debug` at the
   resulting `bin/android_debug.apk`.
3. Set `rendering/limits/cluster_builder/use_msaa=false` for that build.

CI does all of this (feature tag `patched` sets the project setting).
`scripts/debug/diagnostics.gd` (feature tag `diag`) has the A/B test.
