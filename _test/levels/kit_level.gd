extends SideLevel
# Test-only level: the worked example kit (tools/blender/levels/_example.py)
# through load_kit, with its two light groups.

const DIR := "res://assets/levels/_example/"


func build(p_seed: int) -> void:
	seed_value = p_seed
	load_kit(DIR + "example_room.glb", DIR + "lightmaps/example_room.png", "", {
		"floor_tile": {"color": Color(0.42, 0.41, 0.39), "roughness": 0.6},
		"wall_paint": {"color": Color(0.66, 0.64, 0.58)},
		"ceiling_tile": {"color": Color(0.75, 0.74, 0.7)},
		"bank_a": {"color": Color(1.0, 0.97, 0.9), "emit": 1.6, "group": 0},
		"bank_b": {"color": Color(1.0, 0.97, 0.9), "emit": 1.6, "group": 1},
		"exit_sign": {"color": Color(0.2, 1.0, 0.3), "emit": 2.0},
	}, DIR + "lightmaps/example_room_groups.png")
	environment = make_environment({"fog_density": 0.01})
	add_exit(spots["spot_exit"], "door", "")


func arrival() -> Transform3D:
	return spots["spot_arrival"]
