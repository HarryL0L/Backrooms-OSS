extends Node
# Dev harness for L.U.C.I.D. (docs/LUCID.md): the same Lobby views under the
# Realistic preset, for before / after sheets, plus the illuminance the bake
# computes on the floor under and between troffers, and frame cost.
# TAG=<file suffix> (default "after"), VIEWS=<comma list> (default all),
# PERF=1 also prints draw calls and the mean frame time over 60 frames per
# view (lavapipe: compare runs with each other only), PROBE=1 prints the
# probed illuminance (lux) and the camera's exposure. NOFIX=1: without the
# fixture highlight lights; FLASH=1: flashlight on.
# Stage 2 views: flicker_on / flicker_off (a flickering lamp by a wall, the
# world clock pinned to a moment it is on / off, so the shots show whether
# its bounce follows it), poolrooms, warehouse, pipes, unlit_flash, car_park,
# entity_lit / entity_shadow (the car park's Attendant under a lamp and away
# from the lamps, lit by the probe grid).
# Shots: user://photo/lucid_<view>_<tag>.png
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var g: WorldGen
var views := []
var vi := 0
var tag := "after"
var perf := false
var probe := false
var _frames := 0
var _sum_ms := 0.0
var _sum_dc := 0.0
var _last_us := 0

const ALL := ["spawn_hall", "corridor", "dark_corner", "dead_light", "flicker_on", "flicker_off",
		"poolrooms", "warehouse", "pipes", "unlit_flash", "car_park", "entity_lit", "entity_shadow"]
var _flick := Vector2i.ZERO        # the flickering lamp of flicker_on / _off
var _t_on := 0.0
var _t_off := 0.0
var _garage := false
var _aim := false                  # turn to the longest clear view once loaded (pipes)


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	if OS.get_environment("TAG") != "":
		tag = OS.get_environment("TAG")
	perf = OS.get_environment("PERF") == "1"
	probe = OS.get_environment("PROBE") == "1"
	var want: Array = ALL if OS.get_environment("VIEWS") == "" else Array(OS.get_environment("VIEWS").split(","))
	for v in ALL:
		if want.has(v):
			views.append(v)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)


func _lit(gx: int, gz: int) -> bool:
	var s := g.light_state(gx, gz, WorldGen.LOBBY)
	return s == WorldGen.L_ON or s == WorldGen.L_FLICKER


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * WorldGen.CELL, 0.05, (c.y + 0.5) * WorldGen.CELL)


## A Lobby cell nearest the spawn with walls on its west and north sides
## and no lit fixture in the 3 x 3 cells around it: a dark corner.
func _find_corner() -> Vector2i:
	var best := g.spawn_cell
	var best_n := 99
	for r in range(3, 40):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := g.spawn_cell + Vector2i(dx, dz)
				if g.biome_at(c.x, c.y) != WorldGen.LOBBY or g.is_solid(c.x, c.y, WorldGen.LOBBY):
					continue
				var e: Array = g._cell_edges(c.x, c.y)
				if e[0] != WorldGen.E_WALL or e[2] != WorldGen.E_WALL or e[1] == WorldGen.E_WALL or e[3] == WorldGen.E_WALL:
					continue
				var n := 0
				for j in range(-1, 2):
					for i in range(-1, 2):
						if _lit(c.x + i, c.y + j):
							n += 1
				if n < best_n:
					best_n = n
					best = c
		if best_n == 0:
			break
	return best


## A dead fixture in the Lobby (not at the spawn) with an open cell to its
## south to stand in.
func _find_dead() -> Vector2i:
	for r in range(3, 60):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := g.spawn_cell + Vector2i(dx, dz)
				if g.biome_at(c.x, c.y) != WorldGen.LOBBY or g.light_state(c.x, c.y, WorldGen.LOBBY) != WorldGen.L_DEAD:
					continue
				var s := c + Vector2i(0, 1)
				if g.is_solid(s.x, s.y, WorldGen.LOBBY) or g.biome_at(s.x, s.y) != WorldGen.LOBBY:
					continue
				var e: Array = g._cell_edges(s.x, s.y)
				if e[2] == WorldGen.E_OPEN:
					return c
	return g.spawn_cell


## A flickering Lobby lamp with a wall on its north side and two open cells
## south of it to stand in, and two moments of the world clock: one with it
## off and one with it on, the other flickering lamps near it steady.
func _find_flicker() -> void:
	for r in range(2, 60):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := g.spawn_cell + Vector2i(dx, dz)
				if g.biome_at(c.x, c.y) != WorldGen.LOBBY or g.light_state(c.x, c.y, WorldGen.LOBBY) != WorldGen.L_FLICKER:
					continue
				var e: Array = g._cell_edges(c.x, c.y)
				var e1: Array = g._cell_edges(c.x, c.y + 1)
				if e[2] != WorldGen.E_WALL or e[3] != WorldGen.E_OPEN or e1[3] != WorldGen.E_OPEN:
					continue
				if g.is_solid(c.x, c.y + 1, WorldGen.LOBBY) or g.is_solid(c.x, c.y + 2, WorldGen.LOBBY):
					continue
				_flick = c
				var others := []
				for j in range(-5, 6):
					for i in range(-5, 6):
						var o := c + Vector2i(i, j)
						if o != c and g.light_state(o.x, o.y, g.biome_at(o.x, o.y)) == WorldGen.L_FLICKER:
							others.append(g.light_seed(o.x, o.y))
				var sd := g.light_seed(c.x, c.y)
				for k in range(1, 200000):
					var tt := k / 14.0 + 0.035
					if WorldGen.flicker(sd, tt) > 0.0 or WorldGen.flicker(sd, tt + 1.0 / 14.0) < 1.0:
						continue
					var steady := true
					for os in others:
						if WorldGen.flicker(os, tt) < 1.0 or WorldGen.flicker(os, tt + 1.0 / 14.0) < 1.0:
							steady = false
							break
					if steady:
						_t_off = tt
						_t_on = tt + 1.0 / 14.0
						return
	return


## An open car park cell near the player with a lit lamp in it (lit) or with
## no lit lamp within two cells (shadow).
func _find_garage(lit: bool) -> Vector2i:
	var c0 := g.cell_of(game.player.global_position)
	for r in range(1, 30):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := c0 + Vector2i(dx, dz)
				if g.biome_at(c.x, c.y) != WorldGen.GARAGE or g.is_solid(c.x, c.y, WorldGen.GARAGE):
					continue
				var s := g.light_state(c.x, c.y, WorldGen.GARAGE)
				if lit and s == WorldGen.L_ON:
					return c
				if not lit:
					var n := 0
					for j in range(-2, 3):
						for i in range(-2, 3):
							var s2 := g.light_state(c.x + i, c.y + j, WorldGen.GARAGE)
							if s2 == WorldGen.L_ON or s2 == WorldGen.L_FLICKER:
								n += 1
					if n == 0:
						return c
	return c0


## The open cell nearest the spawn (in rings) in biome `b`, with the same
## biome `margin` cells around it (as in realistic_shots.gd).
func _find(b: int, margin := 3) -> Vector3:
	for r in range(4, 400, 2):
		for k in 24:
			var a := k * TAU / 24.0
			var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
			var ok := true
			for d in [Vector2i(margin, 0), Vector2i(-margin, 0), Vector2i(0, margin), Vector2i(0, -margin), Vector2i(0, 0)]:
				if g.biome_at(c.x + d.x, c.y + d.y) != b:
					ok = false
			if ok and not g.is_solid(c.x, c.y, b) and (b != WorldGen.POOL or not (g.gallery(c.x, c.y) or g.pool_noise(c.x, c.y))):
				return Vector3((c.x + 0.5) * WorldGen.CELL, 0.05, (c.y + 0.5) * WorldGen.CELL)
	return g.spawn_position()


## Turns the player to the longest clear view (as realistic_shots.gd).
func _aim_longest() -> void:
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	var eye: Vector3 = game.player.global_position + Vector3(0, 1.55, 0)
	var best := 0.0
	var best_yaw := 0.0
	for k in 32:
		var yaw := k * TAU / 32.0
		var dir := Vector3(-sin(yaw), 0, -cos(yaw))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 40.0)
		q.exclude = [game.player.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		var d: float = 40.0 if hit.is_empty() else eye.distance_to(hit.position)
		if d > best + 0.5:
			best = d
			best_yaw = yaw
	game.player.teleport(game.player.global_position, best_yaw, -0.04)


func _to_garage() -> void:
	if _garage:
		return
	_garage = true
	game._floor = -1
	game._use_gen(WorldGen.new(game.gen.seed_value, -1), true)
	g = game.gen
	game.player.teleport(_find(WorldGen.GARAGE, 4), 0.0)


func _place_entity(c: Vector2i) -> void:
	var at := _cell_pos(c)
	game.player.teleport(at + Vector3(0, 0, 4.2), 0.0, 0.08)
	var a: AttendantEntity = game.attendant
	a.debug_place(at, at + Vector3(0, 0, 4.2))
	a.global_position = at
	a.set_process(false)


func _go() -> void:
	var v: String = views[vi]
	# (The same moment of the flicker clock in every run, so before and
	# after shots have the same lamps on.)
	Ambience.fixed_clock = 1000.0
	game.player.set_flashlight(OS.get_environment("FLASH") == "1")
	if OS.get_environment("NOFIX") == "1":
		game.fixtures.max_lights = 0
	match v:
		"spawn_hall":
			game.player.teleport(g.spawn_position() + Vector3(0.6, 0, 0.6), 0.6, -0.03)
		"corridor":
			var hall := g.spawn_position()
			for r in range(4, 300, 2):
				var c: Vector2i = g.spawn_cell + Vector2i(0, r)
				if g.biome_at(c.x, c.y) == WorldGen.LOBBY and not g.open_hall(c.x, c.y):
					hall = _cell_pos(c)
					if r > 10:
						break
			game.player.teleport(hall, 0.0, -0.02)
		"dark_corner":
			var c := _find_corner()
			# From the far side of the cell, looking into the north-west corner.
			game.player.teleport(_cell_pos(c) + Vector3(1.0, 0, 1.0), PI * 0.25, -0.12)
		"dead_light":
			var c := _find_dead()
			game.player.teleport(_cell_pos(c + Vector2i(0, 1)) + Vector3(0, 0, 0.9), 0.0, 0.22)
		"flicker_on", "flicker_off":
			if _flick == Vector2i.ZERO:
				_find_flicker()
			Ambience.fixed_clock = _t_on if v == "flicker_on" else _t_off
			game.player.teleport(_cell_pos(_flick + Vector2i(0, 1)) + Vector3(0.3, 0, 0.9), 0.1, 0.3)
		"poolrooms":
			game.player.teleport(_find(WorldGen.POOL), 0.0)
		"warehouse":
			game.player.teleport(_find(WorldGen.CONCRETE), 0.0)
		"pipes":
			game.player.teleport(_find(WorldGen.PIPES, 2), 0.0)
			_aim = true
		"unlit_flash":
			game.player.teleport(_find(WorldGen.DARK), 0.0)
			game.player.set_flashlight(true)
		"car_park":
			_to_garage()
		"entity_lit":
			_to_garage()
			_place_entity(_find_garage(true))
		"entity_shadow":
			_to_garage()
			_place_entity(_find_garage(false))
	var cc := g.cell_of(game.player.global_position)
	game._biome = g.biome_at(cc.x, cc.y)


func _probe() -> void:
	if not probe:
		return
	var s := g.spawn_cell
	# The spawn hall is lit by every second row (gz even), every cell along it.
	var row := s.y - posmod(s.y, 2)
	var under := Vector3((s.x + 0.5) * WorldGen.CELL, 0.0, (row + 0.5) * WorldGen.CELL)
	var between_z := under + Vector3(0, 0, WorldGen.CELL)        # halfway to the next row
	var between_x := under + Vector3(WorldGen.CELL * 0.5, 0, 0)  # halfway along the row
	var ch: float = WorldGen.CEIL_H[0]
	var pts := [["floor under a troffer", under, Vector3.UP], ["floor between rows", between_z, Vector3.UP],
			["floor between along row", between_x, Vector3.UP], ["desk (0.75 m) under a troffer", under + Vector3.UP * 0.75, Vector3.UP],
			["vertical at eye height", under + Vector3(0, 1.5, 0), Vector3.FORWARD],
			["ceiling between rows", between_z + Vector3(0, ch - 0.05, 0), Vector3.DOWN]]
	var wall := _hall_wall()
	if wall.size() > 0:
		pts.append(["hall wall at 1.5 m", wall[0], wall[1]])
	# Expectation: direct light summed over every lit fixture within 30 m
	# that the point can see (physics rays against the built walls), and a
	# Monte Carlo gather of the bounce (_mc_bounce) on the same geometry.
	for pr in pts:
		var r: Dictionary = ChunkBuilder.probe(g, pr[1], pr[2])
		var ed := _analytic(pr[1] + pr[2] * 0.02, pr[2])
		var eb := _mc_bounce(pr[1] + pr[2] * 0.03, pr[2])
		print("PROBE %-30s E=%4.0f lux (direct %4.0f, indirect %3.0f)   expected direct %4.0f, bounce %3.0f, total %4.0f" % [pr[0], r.lux, r.direct, r.indirect, ed, eb, ed + eb])
	# A flickering lamp's share: a wall point beside it, with the lamp on and
	# off as the runtime slots give it, against an exact rebake without it.
	var cbs: Script = load("res://scripts/world/chunk_builder.gd")
	if cbs.get_script_constant_map().has("SLOTS"):
		_find_flicker()
		var wp := Vector3((_flick.x + 0.5) * WorldGen.CELL, 1.5, _flick.y * WorldGen.CELL + 0.16)
		for pt in [["wall beside the lamp", wp, Vector3.BACK], ["floor 2 cells away", _cell_pos(_flick + Vector2i(0, 2)), Vector3.UP],
				["ceiling 1 cell away", _cell_pos(_flick + Vector2i(1, 1)) + Vector3.UP * (ch - 0.1), Vector3.DOWN]]:
			var on: Dictionary = ChunkBuilder.probe(g, pt[1], pt[2])
			var off: Dictionary = cbs.call("probe", g, pt[1], pt[2], [_flick])
			cbs.set("kill_cells", [_flick])
			var ref: Dictionary = ChunkBuilder.probe(g, pt[1], pt[2])
			cbs.set("kill_cells", [])
			print("LAMP %-22s on %4.0f lux (direct %4.0f, bounce %3.0f) | off (slots) %4.0f (direct %4.0f, bounce %3.0f) | rebake without it %4.0f (direct %4.0f, bounce %3.0f)" % [
					pt[0], on.lux, on.direct, on.indirect, off.lux, off.direct, off.indirect, ref.lux, ref.direct, ref.indirect])


## A wall of the spawn hall (the first wall east of the spawn): [point, normal].
func _hall_wall() -> Array:
	var c := g.spawn_cell
	for i in 40:
		var e: Array = g._cell_edges(c.x + i, c.y)
		if e[1] == WorldGen.E_WALL:
			return [Vector3((c.x + i + 1) * WorldGen.CELL - 0.16, 1.5, (c.y + 0.5) * WorldGen.CELL), Vector3.LEFT]
	return []


## Reference bounce at p (lux): 160 cosine-weighted rays from p; at each
## hit, its albedo (the biome's floor, ceiling or wall) times the direct
## light there (_analytic) plus its own bounce, from 6 more rays each (with
## the further bounces as a geometric series of their mean albedo).
func _mc_bounce(p: Vector3, n: Vector3) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var sum := 0.0
	var k1 := 160
	for i in k1:
		var h := _cast(p, _cos_dir(n, rng))
		if h.is_empty():
			continue
		var e2 := 0.0
		var rs := 0.0
		var k2 := 6
		for j in k2:
			var h2 := _cast(h[0], _cos_dir(h[1], rng))
			if h2.is_empty():
				continue
			e2 += h2[2] * _analytic(h2[0], h2[1])
			rs += h2[2]
		e2 /= k2
		rs /= k2
		sum += h[2] * (_analytic(h[0], h[1]) + e2 / (1.0 - rs))
	return sum / k1


func _cos_dir(n: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var u := rng.randf()
	var phi := rng.randf() * TAU
	var r := sqrt(u)
	var t := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var bt := n.cross(t)
	return (t * (r * cos(phi)) + bt * (r * sin(phi)) + n * sqrt(1.0 - u)).normalized()


## The first wall, floor or ceiling along a ray: [point (lifted off it),
## normal, albedo], or [] if nothing within 40 m.
func _cast(p: Vector3, d: Vector3) -> Array:
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p, p + d * 40.0)
	q.exclude = [game.player.get_rid()]
	var hit := space.intersect_ray(q)
	# (The ceilings have no collision: they are the plane at the cell's
	# ceiling height.)
	var cc := g.cell_of(p)
	var ch: float = WorldGen.CEIL_H[g.biome_at(cc.x, cc.y)]
	var tc := (ch - p.y) / d.y if d.y > 0.0 else INF
	if (hit.is_empty() or p.distance_to(hit.position) > tc) and tc < 40.0:
		hit = {"position": p + d * tc, "normal": Vector3.DOWN}
	if hit.is_empty():
		return []
	var hn: Vector3 = hit.normal
	var hp: Vector3 = hit.position
	var c := g.cell_of(hp - hn * 0.05)
	var b := g.biome_at(c.x, c.y)
	var what := 1 if hn.y > 0.7 else (2 if hn.y < -0.7 else 0)
	var name: String = WorldGen.LUCID_ALBEDO[b][what]
	var alb := Lucid.lum(Lucid.ALBEDO[name]) if name != "" else 0.4
	return [hp + hn * 0.02, hn, alb]


var _lamps := []
var _lamps_at := Vector2i(1 << 30, 0)


func _analytic(p: Vector3, n: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	var c := g.cell_of(p)
	if (c - _lamps_at).length() > 6.0:
		# Lit fixtures within 20 cells: [position, I0 (cd), m].
		_lamps_at = c
		_lamps = []
		for dz in range(-20, 21):
			for dx in range(-20, 21):
				var gx := c.x + dx
				var gz := c.y + dz
				var b := g.biome_at(gx, gz)
				var st := g.light_state(gx, gz, b)
				if st != WorldGen.L_ON and st != WorldGen.L_FLICKER:
					continue
				var fx: Dictionary = Lucid.FIXTURES[WorldGen.LUCID_FIXTURE[b]]
				_lamps.append([Vector3((gx + 0.5) * WorldGen.CELL, WorldGen.CEIL_H[b] - 0.03, (gz + 0.5) * WorldGen.CELL),
						Lucid.peak_intensity(fx) * WorldGen.LUCID_LLF[b], float(fx.m)])
	var e := 0.0
	for l in _lamps:
		var to: Vector3 = l[0] - p
		var d := to.length()
		if d > 30.0 or n.dot(to) <= 0.0:
			continue
		var ee := Lucid.illuminance(l[1], l[2], to.y / d, n.dot(to) / d, d)
		if ee < 0.05:
			continue
		var q := PhysicsRayQueryParameters3D.create(p, l[0] - to / d * 0.06)
		q.exclude = [game.player.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		e += ee
	return e


func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				Settings.set_value("gameplay/entities", false)
				Settings.set_value("gameplay/jumpscares", false)
				Settings.is_mobile = true
				Settings.apply_preset(Settings.REALISTIC)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				g = game.gen
				game.hud.set_fade(0.0)
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				step = 2; t = 0
				if probe:
					step = 5
				_go()
		2:
			if views[vi].begins_with("entity"):
				game.attendant._update_light(1.0)
			if _aim and t > 4.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				_aim = false
				_aim_longest()
				t = 4.0
			if not _aim and t > 9.0 and game.chunks.is_area_ready(game.player.global_position, 2):
				game.hud.set_fade(0.0)
				game.hud._title.modulate.a = 0.0
				game.hud._subtitle.modulate.a = 0.0
				get_viewport().get_texture().get_image().save_png("%s/lucid_%s_%s.png" % [out, views[vi], tag])
				var info := ""
				if "lucid_cam" in game and game.lucid_cam != null:
					info = " EV100 %.2f WB %dK" % [game.lucid_cam.ev100, roundi(game.lucid_cam.wb_kelvin)]
				print("shot ", views[vi], " ", tag, " exposure ", game.world_env.environment.tonemap_exposure, info)
				step = 3; t = 0
				_frames = -5; _sum_ms = 0.0; _sum_dc = 0.0
				_last_us = Time.get_ticks_usec()
		5:
			if t > 6.0 and game.chunks.is_area_ready(game.player.global_position, 2):
				_probe()
				step = 2; t = 0
				_go()
		3:
			if perf:
				var now := Time.get_ticks_usec()
				if _frames >= 0:
					_sum_ms += (now - _last_us) / 1000.0
					_sum_dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				_last_us = now
				_frames += 1
				if _frames < 60:
					return
				print("PERF %s %s draw_calls=%d frame_ms=%.2f" % [views[vi], tag, roundi(_sum_dc / 60.0), _sum_ms / 60.0])
			vi += 1
			if vi >= views.size():
				get_tree().quit(); return
			step = 2; t = 0
			_go()
