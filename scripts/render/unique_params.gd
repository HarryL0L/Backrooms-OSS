class_name UniqueParams
extends RefCounted
## Per-object shader values without per-instance uniforms. Some older phone
## GPU drivers (Mali Midgard, e.g. Galaxy J7 Prime, on the Compatibility
## renderer) don't pass `instance uniform`s through, leaving them at zero: a
## suit lit by its env_light comes out black. Instead each object gets its own
## copies of its shader materials (made once, on first use) and the values
## are ordinary material uniforms. Only for the handful of objects that need
## them (players, cars, stairwells), so the extra materials don't matter.


## Sets uniform `param` on all of gi's shader materials (its own copies).
static func set_param(gi: GeometryInstance3D, param: StringName, value: Variant) -> void:
	for m in own_materials(gi):
		(m as ShaderMaterial).set_shader_parameter(param, value)


## gi's shader materials, duplicated for it the first time.
static func own_materials(gi: GeometryInstance3D) -> Array:
	if gi.has_meta(&"own_mats"):
		return gi.get_meta(&"own_mats")
	var mats := []
	if gi.material_override is ShaderMaterial:
		gi.material_override = gi.material_override.duplicate()
		mats.append(gi.material_override)
	elif gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				if m == null:
					m = mi.mesh.surface_get_material(i)
				if m is ShaderMaterial:
					var d: ShaderMaterial = m.duplicate()
					mi.set_surface_override_material(i, d)
					mats.append(d)
	gi.set_meta(&"own_mats", mats)
	return mats
