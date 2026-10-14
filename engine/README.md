# Engine patches (not used by the current builds)

Android builds use Godot's **Mobile** renderer, as the Godot docs recommend
("Forward+ … Supported, but poorly optimized. Use Mobile or Compatibility
instead."). Desktop builds use Forward+ on the stock engine. These patches are
kept for a possible future Android Forward+ ("Ultra") build.

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

The old CI job for this is in the git history (commit `51a53e8`).
`scripts/debug/diagnostics.gd` (feature tag `diag`) has the A/B test.
