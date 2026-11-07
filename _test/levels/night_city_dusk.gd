extends "res://scripts/world/levels/night_city_level.gd"
## The Blue Hour shown in its dusk light state (L.U.C.I.D. stage 3's second
## baked state), for the harness:
##   level_shots.tscn -- night_city --script res://_test/levels/night_city_dusk.gd


func build(p_seed: int) -> void:
	force_blend = 1.0
	super(p_seed)


func shots() -> Array:
	var out := []
	for s in super():
		if s.name in ["arrival", "roof_north", "roof_skyline", "avenue_south", "street_corner", "plaza_tower"]:
			s.name = "dusk_" + s.name
			out.append(s)
	return out


func on_leave() -> void:
	force_blend = -1.0
	super()
