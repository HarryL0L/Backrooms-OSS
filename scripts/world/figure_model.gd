class_name FigureModel
extends HazmatModel
## The people (and things) in the Backrooms, built from code on the hazmat
## suit's skeleton, so they share its walk, run, crouch and sit poses:
##
## COPY       an office worker, copied by something that has seen people but
##            got them slightly wrong: arms a little long, neck too long, a
##            smooth blank face. Clothes and hair vary (style_seed).
## ATTENDANT  the car park's attendant: far too tall, stooped, in a stained
##            hi-vis vest over dark overalls, arms hanging past its knees,
##            two dark sockets for a face.
## CRAWLER    pale, emaciated, hairless and faceless; moves on all fours
##            (pose_crawl).

enum { COPY, ATTENDANT, CRAWLER }

var kind := COPY
var style_seed := 0
## How much bigger than the 1.8 m suit (uniform; ATTENDANT is 1.27).
var size := 1.0


func _ready() -> void:
	scale = Vector3.ONE * size
	_build()


func _build() -> void:
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	for b in BONES:
		var i := skeleton.add_bone(b[0])
		var par: int = b[1]
		var gpos: Vector3 = b[2]
		if par >= 0:
			skeleton.set_bone_parent(i, par)
			gpos -= BONES[par][2]
		skeleton.set_bone_rest(i, Transform3D(Basis(), gpos))
	skeleton.reset_bone_poses()
	var rng := RandomNumberGenerator.new()
	rng.seed = style_seed
	var top := "shirt"
	var legs := "trousers"
	var skin := "skin"
	var thin := 1.0
	match kind:
		COPY:
			top = ["shirt", "shirt_blue", "shirt_cream", "shirt"][rng.randi() % 4]
			legs = ["trousers", "trousers_navy", "trousers_khaki"][rng.randi() % 3]
			skin = "skin_wax"
		ATTENDANT:
			top = "overall"
			legs = "overall"
			skin = "skin_wax"
			thin = 0.82
		CRAWLER:
			top = "crawler"
			legs = "crawler"
			skin = "crawler"
			thin = 0.62
	_torso(top, legs, thin)
	for side in [-1.0, 1.0]:
		_arm(side, top if kind != CRAWLER else skin, skin, thin)
		_leg(side, legs, thin)
	var head := _attach(NECK)
	head.position = Vector3(0, -0.01, 0)
	_head(head, skin, rng)
	if kind == COPY and rng.randf() < 0.6:
		# A tie, a little too long.
		var c := _attach(CHEST)
		_part(c, loft([Vector3(0, 0.17, 0.142), Vector3(0, 0.0, 0.15), Vector3(0, -0.24, 0.158), Vector3(0, -0.3, 0.156)],
				[0.012, 0.03, 0.036, 0.003], [0.004, 0.006, 0.006, 0.004], 8), "tie")
	if kind == ATTENDANT:
		_vest()
	_proportions(rng)
	pose_idle(0.0)


## Wrong in small ways: a copy's arms and neck are a bit long (different
## for each), the attendant's very; the crawler's limbs are long and thin.
func _proportions(rng: RandomNumberGenerator) -> void:
	var arm := 1.0
	var neck := 1.0
	match kind:
		COPY:
			arm = rng.randf_range(1.06, 1.16)
			neck = rng.randf_range(1.25, 1.7)
		ATTENDANT:
			arm = 1.38
			neck = 1.9
		CRAWLER:
			arm = 1.3
			neck = 1.5
	for b in [UARM_L, UARM_R, FARM_L, FARM_R]:
		skeleton.set_bone_pose_scale(b, Vector3(1, arm, 1))
	skeleton.set_bone_pose_scale(NECK, Vector3(1, neck, 1))
	if kind == CRAWLER:
		for b in [THIGH_L, THIGH_R, SHIN_L, SHIN_R]:
			skeleton.set_bone_pose_scale(b, Vector3(1, 1.12, 1))


func _torso(mat: String, lower: String, thin: float) -> void:
	# Pelvis in the trousers' material, then the shirt from the waist up
	# (overlapping a little, like a tucked-in shirt).
	var tb := [
		[0.74, 0.12, 0.1, [[HIPS, 1.0]]], [0.8, 0.165, 0.115, [[HIPS, 1.0]]], [0.88, 0.18, 0.125, [[HIPS, 1.0]]],
		[0.97, 0.172, 0.122, [[HIPS, 0.7], [SPINE, 0.3]]], [1.0, 0.17, 0.12, [[HIPS, 0.5], [SPINE, 0.5]]],
		[0.96, 0.174, 0.124, [[HIPS, 0.7], [SPINE, 0.3]]], [1.06, 0.17, 0.12, [[SPINE, 1.0]]],
		[1.16, 0.185, 0.128, [[SPINE, 0.5], [CHEST, 0.5]]], [1.26, 0.2, 0.13, [[CHEST, 1.0]]],
		[1.35, 0.205, 0.126, [[CHEST, 1.0]]], [1.42, 0.185, 0.11, [[CHEST, 1.0]]],
		[1.47, 0.1, 0.08, [[CHEST, 0.5], [NECK, 0.5]]], [1.52, 0.055, 0.055, [[NECK, 1.0]]]]
	for part in [[0, 5, lower], [5, tb.size(), mat]]:
		var pts := []; var rx := []; var rz := []; var ws := []
		for i in range(part[0], part[1]):
			var r: Array = tb[i]
			pts.append(Vector3(0, r[0], 0.0)); ws.append(r[3])
			# Skinny things are thin at the waist, not the shoulders.
			var t: float = lerpf(thin, 1.0, clampf((float(r[0]) - 1.2) / 0.25, 0.0, 1.0))
			rx.append(float(r[1]) * t); rz.append(float(r[2]) * t)
		_skin_part(skinned_loft(pts, rx, rz, ws, 22), part[2])
	# Collar.
	if kind == COPY:
		var c := _attach(CHEST)
		_part(c, loft([Vector3(0, 0.17, -0.005), Vector3(0, 0.2, -0.003)], [0.07, 0.065], [0.068, 0.062], 14, [], false), mat)


func _arm(side: float, sleeve: String, skin: String, thin: float) -> void:
	var L := side < 0.0
	var ua: int = UARM_L if L else UARM_R
	var fa: int = FARM_L if L else FARM_R
	var hd: int = HAND_L if L else HAND_R
	var r0 := 0.06 * thin
	var ab := [
		[0.15, 1.42, r0 * 1.1, [[CHEST, 1.0]]], [0.2, 1.38, r0 * 1.15, [[CHEST, 0.5], [ua, 0.5]]],
		[0.21, 1.3, r0, [[ua, 1.0]]], [0.215, 1.21, r0 * 0.9, [[ua, 1.0]]],
		[0.22, 1.145, r0 * 0.85, [[ua, 0.7], [fa, 0.3]]], [0.222, 1.1, r0 * 0.82, [[ua, 0.3], [fa, 0.7]]],
		[0.225, 1.0, r0 * 0.78, [[fa, 1.0]]], [0.228, 0.93, r0 * 0.68, [[fa, 1.0]]], [0.23, 0.88, r0 * 0.58, [[fa, 0.8], [hd, 0.2]]]]
	var pts := []; var rx := []; var rz := []; var ws := []
	for r in ab:
		pts.append(Vector3(side * r[0], r[1], 0.0)); rx.append(r[2]); rz.append(float(r[2]) * 0.95); ws.append(r[3])
	_skin_part(skinned_loft(pts, rx, rz, ws, 14, [0.2, 0.3, 0.1, 0.1, 0.5, 0.6, 0.1, 0.2, 0.3]), sleeve)
	_hand(_attach(hd), side, skin, thin)


func _hand(h: Node3D, side: float, skin: String, thin: float) -> void:
	var k := 0.85 if kind == CRAWLER else 0.78
	_part(h, loft([Vector3(0, 0.02, 0), Vector3(0, -0.03, 0.003), Vector3(0, -0.07, 0.004)],
			[0.022 * thin + 0.004, 0.02, 0.017], [0.036, 0.04, 0.036], 10), skin)
	var inward := -side
	for f in 4:
		var z := 0.026 - f * 0.017
		var ln: float = [0.075, 0.085, 0.08, 0.065][f] * (1.5 if kind == CRAWLER else 1.0) * k / 0.78
		var base := Vector3(0, -0.065, z)
		var path := [base, base + Vector3(inward * 0.006, -ln * 0.5, 0), base + Vector3(inward * 0.018, -ln * 0.92, 0)]
		_part(h, loft(path, [0.0085, 0.0075, 0.0062], [0.0085, 0.0075, 0.0062], 6), skin)
	var tb := Vector3(inward * 0.008, -0.02, 0.028)
	_part(h, loft([tb, tb + Vector3(inward * 0.01, -0.026, 0.008), tb + Vector3(inward * 0.016, -0.05, 0.004)],
			[0.01, 0.009, 0.008], [0.01, 0.009, 0.008], 6), skin)


func _leg(side: float, mat: String, thin: float) -> void:
	var L := side < 0.0
	var th: int = THIGH_L if L else THIGH_R
	var sh: int = SHIN_L if L else SHIN_R
	var ft: int = FOOT_L if L else FOOT_R
	var r0 := 0.085 * thin
	var lb := [
		[0.07, 0.93, r0, [[HIPS, 1.0]]], [0.1, 0.84, r0 * 1.05, [[HIPS, 0.4], [th, 0.6]]], [0.1, 0.74, r0, [[th, 1.0]]],
		[0.1, 0.62, r0 * 0.9, [[th, 1.0]]], [0.1, 0.52, r0 * 0.8, [[th, 0.75], [sh, 0.25]]], [0.1, 0.45, r0 * 0.78, [[th, 0.25], [sh, 0.75]]],
		[0.1, 0.34, r0 * 0.72, [[sh, 1.0]]], [0.1, 0.22, r0 * 0.6, [[sh, 1.0]]], [0.1, 0.1, r0 * 0.5, [[sh, 0.7], [ft, 0.3]]]]
	var pts := []; var rx := []; var rz := []; var ws := []
	for r in lb:
		pts.append(Vector3(side * r[0], r[1], 0.0)); rx.append(r[2]); rz.append(r[2]); ws.append(r[3])
	_skin_part(skinned_loft(pts, rx, rz, ws, 14, [0.2, 0.3, 0.1, 0.1, 0.5, 0.6, 0.1, 0.2, 0.3]), mat)
	var f := _attach(ft)
	if kind == CRAWLER:
		# Bare, long feet.
		_part(f, loft([Vector3(0, -0.04, -0.06), Vector3(0, -0.06, 0.04), Vector3(0, -0.075, 0.16)],
				[0.035, 0.038, 0.02], [0.03, 0.022, 0.01], 10), "crawler")
	else:
		var fp := [Vector3(0, -0.04, -0.07), Vector3(0, -0.045, 0.0), Vector3(0, -0.055, 0.1), Vector3(0, -0.06, 0.16)]
		_part(f, loft(fp, [0.045, 0.05, 0.046, 0.022], [0.04, 0.04, 0.03, 0.016], 12), "shoe")


func _head(head: Node3D, skin: String, rng: RandomNumberGenerator) -> void:
	# Neck, then a smooth skull: no eyes, no mouth (a copy hasn't got the
	# face right). The attendant has two dark sockets; the crawler less.
	_part(head, loft([Vector3(0, -0.02, 0), Vector3(0, 0.08, 0.005)], [0.05, 0.048], [0.05, 0.048], 12), skin)
	var hr := Vector3(0.088, 0.115, 0.1)
	if kind == CRAWLER:
		hr = Vector3(0.075, 0.1, 0.11)
	_part(head, ellipsoid(hr, 18, 12), skin, Vector3(0, 0.16, 0.01))
	# Jaw and brow: just enough shape to read as a head, not a ball.
	_part(head, ellipsoid(Vector3(0.07, 0.05, 0.075), 14, 8), skin, Vector3(0, 0.09, 0.03))
	_part(head, ellipsoid(Vector3(0.075, 0.025, 0.04), 14, 6), skin, Vector3(0, 0.19, 0.075))
	if kind != CRAWLER:
		for sgn in [-1.0, 1.0]:
			_part(head, ellipsoid(Vector3(0.012, 0.026, 0.018), 8, 6), skin, Vector3(sgn * 0.088, 0.15, 0.0))
	match kind:
		COPY:
			var r := rng.randf()
			if r < 0.75:
				var hair := "hair" if r < 0.5 else "hair_grey"
				_part(head, ellipsoid(Vector3(0.092, 0.07, 0.105), 18, 10), hair, Vector3(0, 0.215, -0.008))
		ATTENDANT:
			for sgn in [-1.0, 1.0]:
				_part(head, ellipsoid(Vector3(0.022, 0.016, 0.01), 10, 6), "socket", Vector3(sgn * 0.035, 0.175, 0.098))
			# A peaked cap, pulled down.
			_part(head, ellipsoid(Vector3(0.096, 0.05, 0.106), 18, 8), "overall", Vector3(0, 0.235, 0.0))
			_part(head, BoxMesh.new(), "overall", Vector3(0, 0.205, 0.11), Vector3(-0.25, 0, 0)).scale = Vector3(0.16, 0.012, 0.07)


func _vest() -> void:
	# Hi-vis vest over the overalls, with two reflective bands.
	var c := _attach(CHEST)
	var y0 := -0.32
	var pts := [Vector3(0, y0, 0), Vector3(0, y0 + 0.15, 0), Vector3(0, y0 + 0.3, 0)]
	_part(c, loft(pts, [0.185, 0.18, 0.212], [0.135, 0.13, 0.136], 18, [], false), "vest")
	for y in [y0 + 0.08, y0 + 0.22]:
		_part(c, loft([Vector3(0, y, 0), Vector3(0, y + 0.035, 0)], [0.2, 0.2], [0.142, 0.142], 18, [], false), "vest_strip")


## On all fours: hips low, back level, head up looking ahead, limbs
## stepping in diagonal pairs. phase in radians (a full stride per TAU),
## amount 0 (still) .. 1.
func pose_crawl(phase: float, amount: float) -> void:
	_off.clear()
	skeleton.set_bone_pose_position(HIPS, BONES[HIPS][2] + Vector3(0, -0.42, -0.05))
	var pitch := 1.32
	_rot(HIPS, Vector3(pitch, 0, 0))
	_rot(SPINE, Vector3(0.05 + 0.04 * sin(phase * 2.0) * amount, 0.06 * sin(phase) * amount, 0))
	_rot(CHEST, Vector3(0.05, -0.05 * sin(phase) * amount, 0))
	_rot(NECK, Vector3(-1.2, 0, 0))
	for L in [true, false]:
		var s := -1.0 if L else 1.0
		var ph := phase + (0.0 if L else PI)
		var arm_swing := sin(ph) * 0.45 * amount
		var lift := maxf(0.0, cos(ph)) * 0.5 * amount
		# Arms reach down to the floor in front of the shoulders.
		_rot(UARM_L if L else UARM_R, Vector3(-pitch - 0.25 - arm_swing, 0, s * 0.18))
		_rot(FARM_L if L else FARM_R, Vector3(-0.35 - lift, 0, 0))
		_rot(HAND_L if L else HAND_R, Vector3(0.9, 0, 0))
		# Legs: knees on the floor under the hips, shins trailing.
		var leg_ph := ph + PI
		_rot(THIGH_L if L else THIGH_R, Vector3(-pitch + 0.15 + sin(leg_ph) * 0.35 * amount, 0, s * 0.12))
		_rot(SHIN_L if L else SHIN_R, Vector3(1.62 + maxf(0.0, cos(leg_ph)) * 0.4 * amount, 0, 0))
		_rot(FOOT_L if L else FOOT_R, Vector3(0.5, 0, 0))
