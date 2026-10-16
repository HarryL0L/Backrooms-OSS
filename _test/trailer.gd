extends Node
# Trailer recorder. Plays a list of scripted camera shots through the real
# game and saves every frame of each shot as JPEG into
# user://trailer/<nn>_<name>/, plus shots.json (name, frames). Run with a
# fixed frame rate so game time is deterministic, e.g.
#   godot --path . --fixed-fps 30 --resolution 1280x720 res://_test/trailer.tscn
# then tools/trailer/edit.py cuts it together with cards, music and sound.
# `-- only=name1,name2` records just those shots (for checking framing).

const FPS := 30.0
const SEED := "4242"

var game
var g: WorldGen
var out := OS.get_user_data_dir() + "/trailer"
var shots := []
var si := -1
var cur: Dictionary
var S := {}                  # scratch for the current shot
var step := 0
var frame := 0
var n := 0
var rec_dir := ""
var rec_frame := -1
var vclock := 200.0
var wait_from := 0
var only := []
var done_log := []


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000          # after the game, so our camera wins
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
		if a.begins_with("sfx="):
			# Just write the game's procedural sounds out as WAVs for the edit.
			var d := a.substr(4)
			DirAccess.make_dir_recursive_absolute(d)
			for nm in ["hum", "wind", "crack", "shriek", "clack", "creak", "draught", "drip"]:
				AudioSynth.cached(nm).save_to_wav("%s/%s.wav" % [d, nm])
			AudioSynth.buzz().save_to_wav(d + "/buzz.wav")
			AudioSynth.drone().save_to_wav(d + "/drone.wav")
			print("sfx written")
			get_tree().quit()
			return
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	RenderingServer.frame_post_draw.connect(_grab)


func _grab():
	if rec_frame >= 0:
		var img := get_viewport().get_texture().get_image()
		img.save_jpg("%s/%04d.jpg" % [rec_dir, rec_frame], 0.93)
		rec_frame = -1


func _process(_delta):
	vclock += 1.0 / FPS
	Ambience.fixed_clock = vclock
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.apply_preset(3)
				Settings.set_value("graphics/auto_quality", false)
				Settings.set_value("graphics/render_scale", 1.0)
				Settings.set_value("gameplay/entities", true)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = SEED
				game.new_game()
				step = 1
		1:
			if game.state == game.State.PLAYING:
				g = game.gen
				_build_shots()
				step = 2
				_next()
		2:
			# Preparing: wait for the world to load around the start pose.
			_hold()
			if Time.get_ticks_msec() - wait_from > int(cur.get("wait", 4.0) * 1000.0) and _ready_now():
				if cur.has("setup"):
					cur.setup.call()
				frame = 0
				n = int(cur.secs * FPS)
				rec_dir = "%s/%02d_%s" % [out, si, cur.name]
				DirAccess.make_dir_recursive_absolute(rec_dir)
				for f in DirAccess.get_files_at(rec_dir):
					DirAccess.remove_absolute(rec_dir + "/" + f)
				step = 3
		3:
			var f := float(frame) / maxf(n - 1, 1)
			if cur.has("clock"):
				Ambience.fixed_clock = cur.clock.call(f)
			_pose(cur.pose.call(f))
			if cur.has("tick"):
				cur.tick.call(f, frame)
			game.hud.set_fade(S.get("fade", 0.0))
			rec_frame = frame
			frame += 1
			if frame >= n:
				done_log.append({"name": cur.name, "dir": rec_dir.get_file(), "frames": n})
				_next()


func _hold():
	if cur.has("at"):
		_pose(cur.at.call())


func _ready_now() -> bool:
	if game._in_field or game._in_mall:
		return true
	return game.chunks.is_area_ready(game.player.global_position, 1)


func _pose(p: Array):
	game.player.teleport(p[0], p[1], p[2])
	if not (game._in_field or game._in_mall):
		var c: Vector2i = g.cell_of(p[0])
		var b := g.biome_at(c.x, c.y)
		if game._biome != b:
			game._set_biome(b, false)
	game.hud._title_t = 0.0


func _next():
	si += 1
	while si < shots.size() and not only.is_empty() and not (shots[si].name in only) and not shots[si].get("always", false):
		si += 1
	if si >= shots.size():
		var fa := FileAccess.open(out + "/shots.json", FileAccess.WRITE)
		fa.store_string(JSON.stringify(done_log, "  "))
		fa.close()
		print("trailer: recorded ", done_log.size(), " shots")
		get_tree().quit()
		return
	cur = shots[si]
	S = {}
	game.hud.set_fade(0.0)
	if cur.has("prep"):
		cur.prep.call()
	print("shot ", si, " ", cur.name)
	wait_from = Time.get_ticks_msec()
	step = 2


# ----------------------------------------------------------------- helpers ---
func cpos(c: Vector2i, y := 0.05) -> Vector3:
	return Vector3((c.x + 0.5) * WorldGen.CELL, y, (c.y + 0.5) * WorldGen.CELL)


func fwd(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func yaw_to(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func sm(f: float) -> float:
	return f * f * (3.0 - 2.0 * f)


func clear_dist(p: Vector3, dir: Vector3, maxd: float) -> float:
	var space = game.player.get_world_3d().direct_space_state
	var a := p + Vector3(0, 1.4, 0)
	var q := PhysicsRayQueryParameters3D.create(a, a + dir * maxd)
	q.exclude = [game.player.get_rid()]
	var hit = space.intersect_ray(q)
	return maxd if hit.is_empty() else a.distance_to(hit.position)


## The direction with the longest view from p.
func longest_yaw(p: Vector3) -> float:
	var best := 0.0
	var by := 0.0
	for k in 16:
		var y := k * TAU / 16.0
		var d := clear_dist(p, fwd(y), 40.0)
		if d > best:
			best = d
			by = y
	return by


func find_cell(pred: Callable, from := Vector2i.ZERO) -> Vector2i:
	var o: Vector2i = g.spawn_cell if from == Vector2i.ZERO else from
	for r in range(4, 500, 2):
		for k in 32:
			var a := k * TAU / 32.0
			var c := o + Vector2i(int(cos(a) * r), int(sin(a) * r))
			if pred.call(c):
				return c
	return o


func biome_block(c: Vector2i, b: int, r: int) -> bool:
	if g.is_solid(c.x, c.y, b):
		return false
	for d in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r), Vector2i.ZERO]:
		if g.biome_at(c.x + d.x, c.y + d.y) != b:
			return false
	return true


## A dolly shot: from p along the longest view, `dist` metres.
func dolly(name: String, p: Vector3, secs: float, dist: float, pitch := 0.0, sway := 0.06) -> Dictionary:
	return {"name": name, "secs": secs,
		"at": func(): return [p, S.get("yaw", 0.0), pitch],
		"setup": func():
			S.yaw = longest_yaw(p)
			S.dist = minf(dist, clear_dist(p, fwd(S.yaw), dist + 2.0) - 2.0),
		"pose": func(f: float):
			var y: float = S.yaw + sin(f * PI) * sway
			return [p + fwd(S.yaw) * S.dist * sm(f), y, pitch + 0.02 * sin(f * 5.0)]}


func door_of(want_mall: bool) -> Dictionary:
	for rx in range(-12, 13):
		for rz in range(-12, 13):
			var d: Dictionary = game.odd_doors.door_in_region(Vector2i(rx, rz))
			if not d.is_empty() and d.mall == want_mall:
				d.region = Vector2i(rx, rz)
				return d
	return {}


# ------------------------------------------------------------------- shots ---
func _build_shots():
	var sp: Vector3 = g.spawn_position()
	shots.append(dolly("lobby", sp, 6.5, 5.0, -0.07))

	# A flickering tube, looked up at, through one of its bursts.
	var lamp: Array = g.nearest_flicker(sp, 24)
	var lp: Vector3 = lamp[0]
	shots.append({"name": "flicker", "secs": 4.5,
		"at": func(): return [Vector3(lp.x + 3.0, 0.05, lp.z), PI * 0.5, 0.3],
		"setup": func():
			S.stand = Vector3(lp.x + 3.0, 0.05, lp.z)
			for o: Vector3 in [Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3), Vector3(2.4, 0, 2.4), Vector3(-2.4, 0, -2.4)]:
				var e := Vector3(lp.x, 0.05, lp.z) + o
				if clear_dist(e, (Vector3(lp.x, 0, lp.z) - e).normalized(), 2.6) > 2.5:
					S.stand = e
					break
			var tt := 100.0
			while tt < 3000.0:
				var ok := true
				for k in 24:
					if WorldGen.flicker(lamp[1], tt + k * 0.05) < 0.99:
						ok = false
						break
				var offs := 0
				for k in 46:
					if WorldGen.flicker(lamp[1], tt + 1.2 + k * 0.05) < 0.5:
						offs += 1
				if ok and offs > 10:
					break
				tt += 0.1
			S.t0 = tt,
		"clock": func(f: float): return S.t0 + f * 4.5,
		"pose": func(f: float):
			var e: Vector3 = S.stand + (Vector3(lp.x, 0, lp.z) - S.stand) * 0.12 * f
			var d := Vector3(lp.x, 0, lp.z) - Vector3(e.x, 0, e.z)
			var pitch := atan2(lp.y - 1.62, d.length()) * 0.8
			return [e, yaw_to(d) + 0.05 * f, pitch]})

	# Level 37: the sun gallery's god rays, then the water.
	var gc := find_cell(func(c: Vector2i):
		var y0: int = c.y - posmod(c.y, 5) + 1
		for dx in range(-6, 7):
			for dz in range(-1, 5):
				if g.biome_at(c.x + dx, y0 + dz) != WorldGen.POOL or not g.gallery(c.x + dx, y0 + dz):
					return false
		return true)
	gc.y = gc.y - posmod(gc.y, 5) + 1
	var gp := cpos(gc, -0.75) + Vector3(0, 0, 6.0)
	shots.append({"name": "gallery", "secs": 5.5,
		"at": func(): return [gp, 0.35, 0.12],
		"pose": func(f: float): return [gp + Vector3(0.0, 0, -1.2 * sm(f)), lerpf(0.3, 0.8, sm(f)), 0.12]})
	var pc := find_cell(func(c: Vector2i):
		return g.biome_at(c.x, c.y) == WorldGen.POOL and g.pool_noise(c.x, c.y) and biome_block(c, WorldGen.POOL, 2))
	var pp := cpos(pc) + Vector3(0, 0, 4.0)
	shots.append({"name": "pool", "secs": 4.5,
		"at": func(): return [pp, 0.0, -0.45],
		"pose": func(f: float): return [pp + Vector3(0, 0, -1.6 * sm(f)), 0.1 * f, -0.45 + 0.15 * f]})

	# Pipe Dreams, the Habitable Zone, the Unlit Halls.
	var pdc := find_cell(func(c: Vector2i): return g.biome_at(c.x, c.y) == 4 and posmod(c.x, 4) == 0 and biome_block(c, 4, 3) and not g.is_solid(c.x, c.y - 1, 4))
	shots.append(dolly("pipes", cpos(pdc), 4.5, 3.5, 0.08))
	var hc := find_cell(func(c: Vector2i): return biome_block(c, 2, 3))
	shots.append(dolly("habitable", cpos(hc), 4.0, 3.5, -0.06))
	var uc := find_cell(func(c: Vector2i): return biome_block(c, 3, 4))
	var ud := dolly("unlit", cpos(uc), 5.5, 3.0, -0.08, 0.15)
	ud.prep = func(): game.player.set_flashlight(true)
	shots.append(ud)

	# The trail of arrows, and the doors.
	var md := door_of(true)
	var fd := door_of(false)
	var mpos: Vector3 = md.pos
	var fpos: Vector3 = fd.pos
	shots.append({"name": "arrow", "secs": 4.0, "wait": 5.0,
		"prep": func(): game.player.set_flashlight(false),
		"at": func(): return [mpos + Vector3(1.5, 0.05, 0), PI * 0.5, 0.0],
		"setup": func():
			var tr = game.odd_doors._trails.get(md.region)
			var best := INF
			S.xf = Transform3D(Basis(), mpos + Vector3(3, 1.2, 0))
			if tr and tr._arrow_mm:
				var mm: MultiMesh = tr._arrow_mm
				for i in mm.instance_count:
					var xf := mm.get_instance_transform(i)
					var dd := xf.origin.distance_to(mpos)
					if xf.basis.x.length() > 0.1 and dd > 5.0 and absf(dd - 9.0) < best:
						var st := xf.origin + xf.basis.z.normalized() * 1.9
						if clear_dist(Vector3(st.x, 0.05, st.z), -xf.basis.z.normalized(), 2.0) > 1.6:
							best = absf(dd - 9.0)
							S.xf = xf
			var xf: Transform3D = S.xf
			S.stand = xf.origin + xf.basis.z.normalized() * 1.35
			S.stand.y = 0.05
			S.y0 = yaw_to(xf.origin - S.stand)
			S.y1 = yaw_to(xf.basis.x.normalized()),
		"pose": func(f: float):
			var xf: Transform3D = S.xf
			var p: Vector3 = S.stand.lerp(Vector3(xf.origin.x, 0.05, xf.origin.z), 0.3 * sm(f))
			return [p, S.y0 + 0.04 * sin(f * 2.0), -0.12]})
	shots.append({"name": "mall_door", "secs": 4.5, "wait": 3.0,
		"at": func(): return [mpos + Vector3(5.0, 0.05, 0), PI * 0.5, 0.0],
		"setup": func(): S.d0 = minf(6.0, clear_dist(mpos + Vector3(1.6, 0.05, 0), Vector3.RIGHT, 7.0) - 0.4),
		"pose": func(f: float): return [mpos + Vector3(lerpf(S.d0, 1.7, sm(f)), 0.05, 0), PI * 0.5, 0.02 * sin(f * 3.0)]})
	shots.append({"name": "field_door", "secs": 4.0, "wait": 5.0,
		"at": func(): return [fpos + Vector3(3.5, 0.05, 0), PI * 0.5, 0.0],
		"setup": func():
			S.door = game.odd_doors._doors.get(fd.region)
			S.opened = false
			game.hud.set_fade_color(Color(1, 1, 1)),
		"tick": func(f: float, _i: int):
			if f > 0.3 and not S.opened and S.door:
				S.opened = true
				S.door.open()
			S.fade = clampf((f - 0.72) / 0.28, 0, 1),
		"pose": func(f: float): return [fpos + Vector3(lerpf(3.4, 1.3, sm(f)), 0.05, 0), PI * 0.5, 0.0]})

	# Level 10: the Field.
	shots.append({"name": "field", "secs": 6.5, "wait": 4.0,
		"prep": func():
			game._enter_field()
			game.hud.set_fade_color(Color(1, 1, 1)),
		"at": func(): return [game.field.arrival(), 0.0, 0.05],
		"setup": func(): S.p = game.field.arrival(),
		"tick": func(f: float, _i: int): S.fade = clampf(1.0 - f / 0.25, 0, 1),
		"pose": func(f: float): return [S.p, -0.35 + 0.7 * sm(f), lerpf(0.02, 0.32, sm(f))]})
	shots.append({"name": "field_exit", "secs": 4.5,
		"prep": func(): game.hud.set_fade_color(Color(0, 0, 0)),
		"at": func(): return [game.field.arrival(), 0.0, 0.0],
		"setup": func():
			var ep: Vector3 = game.field.exit_pos
			var to := Vector3(-ep.x, 0, -ep.z).normalized()
			S.a = Vector3(ep.x + to.x * 14.0, 0, ep.z + to.z * 14.0)
			S.b = Vector3(ep.x + to.x * 9.0, 0, ep.z + to.z * 9.0)
			S.yaw = yaw_to(-to),
		"pose": func(f: float):
			var q: Vector3 = S.a.lerp(S.b, f)
			return [FieldLevel.ground_at(q.x, q.z) + Vector3(0, 0.1, 0), S.yaw, 0.0]})

	# The Dead Mall.
	var Y := MallLevel.MALL_Y + 0.05
	shots.append({"name": "mall", "secs": 5.5, "wait": 8.0,
		"prep": func():
			game._leave_field()
			game._enter_mall(),
		"at": func(): return [Vector3(16, Y, 3.0), -PI * 0.5, 0.05],
		"pose": func(f: float): return [Vector3(lerpf(16, 23, f), Y, 3.0), -PI * 0.5 + 0.12 * sin(f * PI), 0.05]})
	shots.append({"name": "court", "secs": 5.0,
		"at": func(): return [Vector3(62, Y, -9), -PI * 0.62, 0.12],
		"pose": func(f: float): return [Vector3(lerpf(62, 64.5, f), Y, -9), lerpf(-PI * 0.64, -PI * 0.5, sm(f)), 0.12]})
	# A mannequin in a shop window (one of the decoys), pushed in on.
	shots.append({"name": "window", "secs": 3.5,
		"at": func(): return [Vector3(31, Y, 2.5), 0.4, 0.0],
		"setup": func():
			# From the middle of the concourse, looking into the window.
			var best := INF
			S.p = Vector3(31, Y, 2.5)
			S.t = Vector3(33, Y + 1.5, 4.5)
			for d: WindowDresser in game.mall.decoys:
				var dp := d.global_position
				if absf(dp.z) < 3.0 or dp.x < 12.0 or dp.x > 110.0:
					continue
				var score := absf(dp.x - 40.0)
				if score < best:
					best = score
					S.p = Vector3(dp.x - 0.8, Y, clampf(dp.z - signf(dp.z) * 3.2, -3.0, 3.0))
					S.t = dp + Vector3(0, 1.45, 0)
			print("window mannequin at ", S.t, " from ", S.p),
		"pose": func(f: float):
			var p: Vector3 = S.p.lerp(Vector3(S.t.x, Y, S.t.z), 0.3 * sm(f))
			var d: Vector3 = S.t - (p + Vector3(0, 1.62, 0))
			return [p, yaw_to(Vector3(d.x, 0, d.z)), atan2(d.y, Vector2(d.x, d.z).length())]})
	# The Window Dresser, staged by hand (its brain switched off).
	var dz := 1.0
	shots.append({"name": "dresser_still", "secs": 3.5,
		"at": func(): return [Vector3(22, Y, dz), -PI * 0.5, 0.0],
		"setup": func():
			game.player.camera.fov = 50.0     # a longer lens: it fills the frame
			var ai = game.mall.ai
			ai.set_physics_process(false)
			ai.set_process(false)
			S.body = ai.body
			S.body.set_awake(false)
			S.body.set_pose("dormant")
			S.body.global_position = Vector3(29.5, MallLevel.MALL_Y, dz)
			S.body.rotation.y = -PI * 0.5,
		"pose": func(f: float): return [Vector3(lerpf(24.0, 26.6, sm(f)), Y, dz), -PI * 0.5, 0.1]})
	shots.append({"name": "dresser_wake", "secs": 2.0,
		"at": func(): return [Vector3(25.3, Y, dz), -PI * 0.5, -0.02],
		"setup": func():
			S.body = game.mall.ai.body
			S.body.set_awake(true)
			S.body.set_pose("dormant")       # upright, face to camera
			S.body.global_position = Vector3(27.6, MallLevel.MALL_Y, dz),
		"pose": func(f: float):
			var shake := 0.012 * sin(f * 90.0) * (1.0 - f)
			return [Vector3(25.3 + 0.15 * f, Y, dz), -PI * 0.5 + shake, 0.0 + shake]})
	shots.append({"name": "dresser_run", "secs": 2.4,
		"at": func(): return [Vector3(22, Y, dz), -PI * 0.5, 0.06],
		"setup": func():
			S.body = game.mall.ai.body
			S.body.set_awake(true)
			S.body.play_run(1.6)
			S.step = -1,
		"tick": func(f: float, _i: int):
			var k := int(f * 2.4 * 9.0)        # stop-motion: 9 poses a second
			if k != S.step:
				S.step = k
				S.body.global_position = Vector3(lerpf(33.0, 22.9, float(k) / (2.4 * 9.0)), MallLevel.MALL_Y, dz),
		"pose": func(f: float): return [Vector3(21.6 - 0.4 * f, Y, dz), -PI * 0.5 + 0.01 * sin(f * 40.0), 0.06]})
	shots.append({"name": "dresser_lunge", "secs": 0.9,
		"at": func(): return [Vector3(22, Y, dz), -PI * 0.5, 0.06],
		"setup": func(): game.mall.ai.lunge_at(game.player.camera),
		"pose": func(f: float):
			var s := 0.03 * sin(f * 140.0)
			return [Vector3(22, Y, dz), -PI * 0.5 + s, 0.06 + s * 0.7]})
