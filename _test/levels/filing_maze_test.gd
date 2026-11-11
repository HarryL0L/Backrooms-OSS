extends Node
# The Stacks' maze is fair. Runs the floor's real shelving logic (the
# level's own sim_step: the scheduler, the stand-in-an-aisle closes, the
# first-time events, the cart) for several minutes with several seeds and a
# walker who wanders the floor, stops in aisles (so they shut on it), and
# walks out of a closing aisle REACT s after its warning starts. On a grid of
# GRID m cells (where a 0.3 m radius person fits, the level's grid_free) it
# checks:
#  1. pockets: every spot a person can stand is joined to the exit door
#     except for short spells while a range is rolling: no spot is ever cut
#     off for longer than CUT_MAX s (a flood fill from the exit every 0.5 s);
#  2. bounded time: from the arrival and from 40 random spots at random
#     moments, the exit is reached within EXIT_MAX s at a walk, waiting where
#     needed (the reachable set swept forward through the shelving states);
#  3. fair closes: at the moment every close starts warning, from every spot
#     in the closing aisle a person who reacts after REACT s and walks at
#     WALK m/s is out of it before it is narrower than CRUSH_GAP;
#  4. the walker is never crushed.
#   ... res://_test/levels/filing_maze_test.tscn [-- seeds=5 minutes=5]
# Prints PASS / FAIL lines and "filing_maze_test: N failed".

const L := preload("res://scripts/world/levels/filing_level.gd")
const LAYOUT := preload("res://scripts/world/levels/filing_layout.gd")

var game
var fails := 0
const WALK := 2.6
const REACT := 1.5
const DT := 0.1
const SNAP := 0.5
const CUT_MAX := 20.0
const EXIT_MAX := 150.0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > limit:
			return false
	return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var seeds := int(args.get("seeds", "5"))
	var minutes := float(args.get("minutes", "5"))
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING and not game._transition, 120.0)
	game.hud.set_fade(0.0)
	game.debug_enter_side("filing")
	if not await _until(func() -> bool: return game._in_side and not game._transition and game.side_id == "filing", 90.0):
		check(false, "into the Stacks")
		_quit()
		return
	var lv = game.side
	lv.sim = true
	lv._events = true
	game.player.controls_enabled = false
	RenderingServer.render_loop_enabled = false
	var worst := {"cut": 0.0, "exit": 0.0, "margin": INF, "crush": 0, "events": 0, "route": 0.0}
	var first := int(args.get("first", "0"))
	for s in range(first, first + seeds):
		var r: Dictionary = await _seed(lv, 1000 + s * 7919, minutes)
		print("seed %d: %d closes (fair-warning margin min %.2f s), walker crushed %d, longest cut-off %.1f s, longest route %.0f m, exit reached in max %.0f s (median %.0f s, from the arrival %.0f s) from %d starts; %d aisle-free cells never reachable" % [
				s, r.events, r.margin, r.crush, r.cut, r.route, r.exit, r.median, r.arrival, r.starts, r.never])
		worst.cut = maxf(worst.cut, r.cut)
		worst.exit = maxf(worst.exit, r.exit)
		worst.margin = minf(worst.margin, r.margin)
		worst.crush += r.crush
		worst.events += r.events
		worst.route = maxf(worst.route, r.route)
		await get_tree().process_frame
	RenderingServer.render_loop_enabled = true
	check(worst.cut <= CUT_MAX, "no pocket: every spot rejoins the exit within %.0f s (longest cut-off %.1f s, %d seeds x %.0f min)" % [
			CUT_MAX, worst.cut, seeds, minutes])
	check(worst.exit <= EXIT_MAX, "bounded: the exit reached within %.0f s from every sampled spot and moment (worst %.0f s)" % [
			EXIT_MAX, worst.exit])
	check(worst.margin >= 0.0 and worst.events > 0, "fair closes: out of every closing aisle at a walk after %.1f s of reaction (%d closes, min margin %.2f s)" % [
			REACT, worst.events, worst.margin])
	check(worst.crush == 0, "the walker (reacts in %.1f s, walks out) was never crushed (%d)" % [REACT, worst.crush])
	print("filing_maze_test: %d failed" % fails)
	_quit()


func _quit() -> void:
	game.queue_free()
	for k in 4:
		await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)


## The slot a closing bank is closing (Blender rect), or an empty rect.
func _closing_slot(lv, bk) -> Rect2:
	var w: Vector2 = lv._gap(bk, bk.close_gap)
	return lv._rect_b(bk.cell, (w.x + w.y) * 0.5, (bk.z0 + bk.z1) * 0.5, maxf(w.y - w.x, 0.0), bk.L)


func _seed(lv, sd: int, minutes: float) -> Dictionary:
	lv.sim_reset(sd)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd + 1
	var size: Vector2i = lv.grid_size()
	var gw := size.x
	var ncell := size.x * size.y
	var free: PackedByteArray = lv.grid_free()
	var free0 := free.duplicate()
	var static_free: PackedByteArray = lv._grid_static
	var bank_rects: Array = []
	for bk in lv.banks():
		bank_rects.append(lv.bank_rect(bk))
	# cells inside a bank's footprint (the aisles) and outside them all
	var in_bank := PackedByteArray()
	in_bank.resize(ncell)
	var aisle_cells := PackedInt32Array()
	for i in ncell:
		if static_free[i] == 0:
			continue
		var p: Vector2 = lv.grid_pos(i)
		for r in bank_rects:
			if (r as Rect2).has_point(p):
				in_bank[i] = 1
				aisle_cells.append(i)
				break
	var walk_cells := PackedInt32Array()
	for i in ncell:
		if static_free[i] == 1:
			walk_cells.append(i)
	var pos: int = lv.grid_index(Vector2(LAYOUT.DATA.arrival[0], LAYOUT.DATA.arrival[1]))
	var target := -1
	var wait := 0.0
	var field := PackedInt32Array()
	var field_t := -10.0
	var flee := {}             # event index -> flee field
	var cut := PackedFloat32Array()
	cut.resize(ncell)
	var maxrun := PackedFloat32Array()
	maxrun.resize(ncell)
	var ever := PackedByteArray()
	ever.resize(ncell)
	var wasfree := PackedByteArray()
	wasfree.resize(ncell)
	var max_cut := 0.0
	var max_route := 0
	var changes: Array = []
	var prev := free.duplicate()
	var need := {}             # event index -> seconds needed to walk out
	var ev_seen := 0
	var n_steps := int(minutes * 60.0 / DT)
	var per_snap := int(round(SNAP / DT))
	for k in n_steps:
		var t := k * DT
		var bp: Vector2 = lv.grid_pos(pos)
		var cr0: int = lv.sim_crushes
		lv.sim_step(Vector3(bp.x, SideLevel.LEVEL_Y, -bp.y), DT)
		if lv.sim_crushes > cr0 and OS.get_environment("TRACE") != "" and cr0 < 3:
			var info := []
			for b in lv.banks():
				if b.state != 0:
					var e: Dictionary = lv.events_log[b.log_i]
					info.append("%s%s st %d c %d t0 %.1f warn %.1f gap %s slot %s" % [b.cell.id, b.name, b.state, b.close_gap,
							e.t0, e.warn, lv._gap(b, b.close_gap), _closing_slot(lv, b)])
			print("TRACE crush t %.1f at %s target %d wait %.1f ; %s" % [t, bp, target, wait, info])
		# 3. every new close: how long the walk out of its aisle takes
		while ev_seen < lv.events_log.size():
			var e: Dictionary = lv.events_log[ev_seen]
			var bk = lv.banks()[int(e.b)]
			var f: PackedByteArray = lv.grid_free()
			var slot := _closing_slot(lv, bk)
			var own: Rect2 = bank_rects[int(e.b)]
			var esc := PackedInt32Array()
			for i in walk_cells:
				if f[i] == 1 and not own.has_point(lv.grid_pos(i)):
					esc.append(i)
			var d: PackedInt32Array = lv.grid_bfs(f, esc)
			var far := 0
			var stuck := false
			for i in aisle_cells:
				if f[i] == 1 and slot.has_point(lv.grid_pos(i)):
					if d[i] < 0:
						stuck = true
					far = maxi(far, d[i])
			need[ev_seen] = INF if stuck else REACT + far * L.GRID / WALK
			flee[ev_seen] = [d, f]
			ev_seen += 1
		# the walker
		var fnow: PackedByteArray = lv.grid_free()
		var danger := -1
		for ei in range(maxi(0, lv.events_log.size() - 12), lv.events_log.size()):
			var e: Dictionary = lv.events_log[ei]
			var bk = lv.banks()[int(e.b)]
			if (bk.state == 1 or bk.state == 2) and bk.log_i == ei and _closing_slot(lv, bk).grow(0.05).has_point(bp):
				danger = ei
		if danger >= 0:
			if t - float(lv.events_log[danger].t0) >= REACT:
				# (along the way out as it was when the warning began: the grid
				# loses the narrowing aisle's cells long before a person can't fit)
				var d: PackedInt32Array = flee[danger][0]
				pos = _descend(lv, d, pos, gw, flee[danger][1])
			target = -1
		elif wait > 0.0:
			wait -= DT
		else:
			if target < 0 or pos == target:
				if target >= 0 and in_bank[target] == 1:
					wait = rng.randf_range(1.0, 7.0)
				target = aisle_cells[rng.randi() % aisle_cells.size()] if rng.randf() < 0.4 \
						else walk_cells[rng.randi() % walk_cells.size()]
				field_t = -10.0
			if t - field_t >= 1.0:
				var f := fnow.duplicate()
				# a sensible walker never steps into an aisle that is closing
				for b in lv.banks():
					if b.state == 1 or b.state == 2:
						var sl := _closing_slot(lv, b)
						for i in aisle_cells:
							if sl.has_point(lv.grid_pos(i)):
								f[i] = 0
				field = lv.grid_bfs(f, PackedInt32Array([target]))
				field_t = t
				if field[pos] < 0:
					target = -1
			if target >= 0 and field[pos] > 0:
				pos = _descend(lv, field, pos, gw, fnow)
		# 1. snapshots: cut-off spells, route lengths, the changes
		if k % per_snap == 0:
			free = fnow
			var d: PackedInt32Array = lv.grid_bfs(free, lv.grid_exit(free))
			var ch := PackedInt32Array()
			for i in walk_cells:
				var fr := free[i]
				if fr != prev[i]:
					ch.append(i if fr == 1 else -1 - i)
				if fr == 1:
					wasfree[i] = 1
					if d[i] < 0:
						cut[i] += SNAP
						maxrun[i] = maxf(maxrun[i], cut[i])
					else:
						cut[i] = 0.0
						ever[i] = 1
						max_route = maxi(max_route, d[i])
				else:
					cut[i] = 0.0
			changes.append(ch)
			prev = free
			if OS.get_environment("TRACE") != "":
				var ai: int = lv.grid_index(Vector2(4.0, 8.43))
				if d[ai] < 0:
					var bb = lv.banks()[1]
					print("TRACE t %.1f cut; R1B state %d open %s cx0 %.2f ; bankA state %d open %s" % [t, bb.state, lv.open_gaps(bb), bb.cx[0], lv.banks()[0].state, lv.open_gaps(lv.banks()[0])])
			if k == 0 and OS.get_environment("DUMP") != "":
				var img := Image.create(gw, size.y, false, Image.FORMAT_RGB8)
				for i in ncell:
					var col := Color(0.1, 0.1, 0.1)
					if static_free[i] == 1:
						col = Color(0.3, 0.3, 0.5)
					if free[i] == 1:
						col = Color(0.2, 0.8, 0.2) if d[i] >= 0 else Color(1, 0.1, 0.1)
					img.set_pixel(i % gw, size.y - 1 - i / gw, col)
				img.save_png(OS.get_environment("DUMP"))
		if k % 300 == 0:
			await get_tree().process_frame
	# a spot nobody can ever get to (never joined to the exit, e.g. Bay 1's
	# south rear aisle behind the cart) is no place you can be
	var never := 0
	for i in walk_cells:
		if ever[i] == 1:
			max_cut = maxf(max_cut, maxrun[i])
		elif wasfree[i] == 1:
			never += 1
	if OS.get_environment("DUMP") != "":
		var img := Image.create(gw, size.y, false, Image.FORMAT_RGB8)
		for i in ncell:
			var col := Color(0.1, 0.1, 0.1)
			if static_free[i] == 1:
				col = Color(0.25, 0.25, 0.4) if in_bank[i] == 1 else Color(1, 0.1, 0.1)
				if ever[i] == 1:
					col = Color(0.2, 0.8, 0.2) if maxrun[i] <= CUT_MAX else Color(1.0, 0.6, 0.0)
			img.set_pixel(i % gw, size.y - 1 - i / gw, col)
		img.save_png(OS.get_environment("DUMP").replace(".png", "_end.png"))
	var reachable := PackedInt32Array()
	for i in walk_cells:
		if ever[i] == 1:
			reachable.append(i)
	# 3. margins
	var margin := INF
	var nev := 0
	for ei in need:
		var e: Dictionary = lv.events_log[ei]
		if e.has("tc"):
			nev += 1
			margin = minf(margin, float(e.tc) - float(e.t0) - float(need[ei]))
	# 2. earliest arrival from sampled starts, swept forward through the states
	var starts: Array = [[lv.grid_index(Vector2(LAYOUT.DATA.arrival[0], LAYOUT.DATA.arrival[1])), 0]]
	var nsnap := changes.size()
	for j in 40:
		starts.append([reachable[rng.randi() % reachable.size()], rng.randi_range(0, nsnap / 2)])
	var arrivals: Array = await _sweep(lv, free0, changes, starts, gw)
	var worst := 0.0
	var ok_starts := 0
	var times: Array = []
	for a in arrivals:
		if a < -1.5:
			continue           # (started where nobody can stand)
		ok_starts += 1
		var tt: float = a if a >= 0.0 else INF
		times.append(tt)
		worst = maxf(worst, tt)
	times.sort()
	return {"events": nev, "margin": margin, "crush": lv.sim_crushes, "cut": max_cut, "route": max_route * L.GRID,
			"exit": worst, "median": times[times.size() / 2] if not times.is_empty() else INF, "starts": ok_starts,
			"never": never, "arrival": times[0] if false else (arrivals[0] if arrivals[0] >= 0.0 else INF)}


## One cell downhill on a distance field (staying where it is if none).
func _descend(lv, d: PackedInt32Array, pos: int, gw: int, f: PackedByteArray) -> int:
	var best := pos
	var bd := d[pos] if d[pos] >= 0 else 1 << 30
	for nb in [pos - 1, pos + 1, pos - gw, pos + gw]:
		if nb >= 0 and nb < d.size() and f[nb] == 1 and d[nb] >= 0 and d[nb] < bd:
			best = nb
			bd = d[nb]
	return best


## For each start [cell, snapshot]: seconds until a person who walks at WALK
## (GRID-cell steps, 4 neighbours: no faster than that) can be at the exit,
## waiting wherever they like, through the recorded shelving states; -1 if
## never, -2 if the start isn't free.
func _sweep(lv, free0: PackedByteArray, changes: Array, starts: Array, gw: int) -> Array:
	var free := free0.duplicate()
	var ncell := free.size()
	var steps := int(floor(SNAP * WALK / L.GRID))
	var exit_mask := PackedByteArray()
	exit_mask.resize(ncell)
	var out: Array = []
	var reach: Array = []
	var front: Array = []
	var done: Array = []
	for s in starts:
		out.append(-1.0)
		var r := PackedByteArray()
		r.resize(ncell)
		reach.append(r)
		front.append(PackedInt32Array())
		done.append(false)
	for k in changes.size():
		var ch: PackedInt32Array = changes[k]
		for c in ch:
			if c >= 0:
				free[c] = 1
			else:
				free[-1 - c] = 0
		var ex: PackedInt32Array = lv.grid_exit(free)
		exit_mask.fill(0)
		for e in ex:
			exit_mask[e] = 1
		for si in starts.size():
			if done[si] or k < int(starts[si][1]):
				continue
			var r: PackedByteArray = reach[si]
			var fr: PackedInt32Array = front[si]
			if k == int(starts[si][1]):
				var st: int = starts[si][0]
				if free[st] == 0:
					out[si] = -2.0
					done[si] = true
					reach[si] = PackedByteArray()
					continue
				r[st] = 1
				fr = PackedInt32Array([st])
			else:
				for c in ch:
					if c < 0:
						r[-1 - c] = 0
					else:
						# a spot that just opened next to where you could be
						for nb in [c - 1, c + 1, c - gw, c + gw]:
							if nb >= 0 and nb < ncell and r[nb] == 1:
								fr.append(nb)
								break
			var hit := false
			for layer in steps:
				var nf := PackedInt32Array()
				for i in fr:
					if r[i] == 0:
						continue
					if exit_mask[i] == 1:
						hit = true
					for nb in [i - 1, i + 1, i - gw, i + gw]:
						if nb >= 0 and nb < ncell and free[nb] == 1 and r[nb] == 0:
							r[nb] = 1
							nf.append(nb)
							if exit_mask[nb] == 1:
								hit = true
				fr = nf
				if hit:
					break
			front[si] = fr
			reach[si] = r
			if hit:
				out[si] = (k - int(starts[si][1])) * SNAP
				done[si] = true
				reach[si] = PackedByteArray()
		if k % 100 == 0:
			await get_tree().process_frame
	return out
