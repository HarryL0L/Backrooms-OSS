extends LevelEntrance
## The Endless Stairwell's B2 door (the way you came in, and the way back
## out): the stair's own 3070 hollow-metal fire door, in the kit's frame
## (stair_top has the frame and the dark opening; this is the leaf that
## moves): blue-grey enamel, a 10 x 10 in wired-glass vision panel, a lever
## on the latch side, a kick plate. Hinged on its local +X side (the
## stair's west).

const W := 0.9144
const H := 2.1336
const VISION := 0.254

var leaf_mats: Array[StandardMaterial3D] = []


func _build() -> void:
	var paint := mat(Color(0.16, 0.19, 0.21), 0.5, 0.2)
	var steel := mat(Color(0.55, 0.55, 0.52), 0.3, 0.9)
	var glass := mat(Color(0.004, 0.004, 0.005), 0.05, 0.0)
	var frame := mat(Color(0.10, 0.11, 0.12), 0.5, 0.3)
	make_void(Vector2(W, H), Vector3(0.0, H * 0.5, -0.16))
	var piv := Node3D.new()
	piv.position = Vector3(W * 0.5, 0.0, -0.06)
	add_child(piv)
	box(paint, Vector3(W - 0.006, H - 0.006, 0.045), Vector3(-W * 0.5, H * 0.5, -0.0225), piv)
	# vision panel (latch side, 60 in up), lever, rose, kick plate
	box(frame, Vector3(VISION + 0.04, VISION + 0.04, 0.012), Vector3(-W * 0.5 - 0.12, 1.524, 0.006), piv)
	box(glass, Vector3(VISION, VISION, 0.004), Vector3(-W * 0.5 - 0.12, 1.524, 0.013), piv)
	box(steel, Vector3(0.06, 0.06, 0.012), Vector3(-W + 0.075, 1.0, 0.006), piv)
	box(steel, Vector3(0.13, 0.018, 0.02), Vector3(-W + 0.135, 1.0, 0.04), piv)
	box(steel, Vector3(0.016, 0.016, 0.04), Vector3(-W + 0.075, 1.0, 0.025), piv)
	box(steel, Vector3(W - 0.06, 0.25, 0.003), Vector3(-W * 0.5, 0.14, 0.0015), piv)
	parts["leaf"] = piv
	for k in _mats:
		leaf_mats.append(_mats[k])


## Opens it a crack wider than shut: the leaf at `angle` (radians, the way
## open() swings it).
func set_open(angle: float) -> void:
	(parts["leaf"] as Node3D).rotation.y = angle


## Its parts lit by `l` (0..1) as the place round it is (the landing's lamp).
func set_light(l: float) -> void:
	for m in leaf_mats:
		m.emission = m.albedo_color * l * 0.9
