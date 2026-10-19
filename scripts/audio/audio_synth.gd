class_name AudioSynth
extends RefCounted
## Procedural sound synthesis. Every sound in the game is generated here at
## startup, so the repository contains no audio files at all.

const RATE := 22050


static var _cache := {}
static var _cache_lock := Mutex.new()


## Returns a sound by synth function name, generating it only once. Ambience
## pre-warms these on a worker thread, so the game never synthesizes on the
## main thread mid-play (a door's draught took ~100+ ms: a visible hitch).
static func cached(fn: String) -> AudioStreamWAV:
	_cache_lock.lock()
	var s: AudioStreamWAV = _cache.get(fn)
	_cache_lock.unlock()
	if s == null:
		s = _make(fn)
		_cache_lock.lock()
		_cache[fn] = s
		_cache_lock.unlock()
	return s


static func _make(fn: String) -> AudioStreamWAV:
	match fn:
		"draught":
			return draught()
		"hum":
			return hum()
		"wind":
			return wind()
		"drip":
			return drip()
		"paper":
			return paper()
		"exhale":
			return exhale()
		"clack":
			return clack()
		"crack":
			return crack()
		"creak":
			return creak()
		"shriek":
			return shriek()
		"rasp":
			return rasp()
		"sting":
			return sting()
		"heartbeat":
			return heartbeat()
		"click":
			return click()
		"car_latch":
			return car_latch()
		"car_shut":
			return car_shut()
		"car_crank":
			return car_crank()
		"car_idle":
			return car_idle()
		"car_dead":
			return car_dead()
	if fn == "ding":
		return ding()
	if fn.begins_with("stalk_step"):
		return stalk_step(int(fn.trim_prefix("stalk_step")))
	push_error("AudioSynth.cached: unknown sound " + fn)
	return null


static func to_wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, clampi(int(s[i] * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


## Crossfades the tail of an over-long buffer into its head so it loops seamlessly.
static func _make_loop(s: PackedFloat32Array, length: int) -> PackedFloat32Array:
	var fade := s.size() - length
	var out := s.slice(0, length)
	for i in fade:
		var t := float(i) / fade
		out[i] = s[i] * t + s[length + i] * (1.0 - t)
	return out


static func _normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in s.size():
		s[i] *= k
	return s


## Fluorescent ballast hum: 120 Hz magnetostriction buzz with harmonics.
static func hum() -> AudioStreamWAV:
	var n := RATE * 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := TAU * 120.0 * t
		var v := 0.5 * sin(w) + 0.28 * sin(2.0 * w + 0.3) + 0.14 * sin(3.0 * w + 1.1) + 0.09 * sin(4.0 * w + 2.0) \
				+ 0.05 * sin(5.0 * w) + 0.04 * sin(7.0 * w + 0.7)
		var sq := signf(sin(w)) * 0.08
		lp += 0.15 * (sq - lp)
		var noise := rng.randf_range(-1.0, 1.0)
		lp2 += 0.3 * (noise - lp2)
		v += lp + lp2 * 0.035
		v *= 1.0 + 0.06 * sin(TAU * 0.5 * t)
		s[i] = v
	return to_wav(_normalize(s, 0.5), true)


## Deep room tone - the sound of a vast empty building.
static func drone() -> AudioStreamWAV:
	var length := RATE * 6
	var n := length + RATE / 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var b := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		b = (b + 0.02 * rng.randf_range(-1.0, 1.0)) * 0.998
		lp += 0.02 * (b - lp)
		var tone := 0.25 * sin(TAU * 41.0 * t) + 0.18 * sin(TAU * 55.0 * t + 0.4) * (0.6 + 0.4 * sin(TAU * 0.1667 * t))
		s[i] = lp * 3.0 + tone * 0.35
	return to_wav(_normalize(_make_loop(s, length), 0.6), true)


## Gentle lapping water for the Tiled Baths.
static func water_loop() -> AudioStreamWAV:
	var length := RATE * 6
	var n := length + RATE / 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var lp1 := 0.0
	var lp2 := 0.0
	var env := 0.0
	var target := 0.3
	for i in n:
		if i % 1800 == 0:
			target = rng.randf_range(0.1, 1.0)
		env += 0.0006 * (target - env)
		var x := rng.randf_range(-1.0, 1.0)
		lp1 += 0.12 * (x - lp1)
		lp2 += 0.012 * (lp1 - lp2)
		var band := lp1 - lp2
		var blip := 0.0
		if rng.randf() < 0.0004:
			blip = rng.randf_range(-1.0, 1.0)
		s[i] = band * env + blip * 0.3
	return to_wav(_normalize(_make_loop(s, length), 0.5), true)


## A single drop falling into water: a short "plip" whose pitch rises, as a
## real drop's air bubble resonance does.
static func drip() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 900.0 + 2400.0 * minf(t / 0.035, 1.0)
		ph += TAU * f / RATE
		var env := minf(t / 0.002, 1.0) * exp(-t * 38.0)
		s[i] = sin(ph) * env
	return to_wav(_normalize(s, 0.5), false)


## Electrical buzz of a failing tube.
static func buzz() -> AudioStreamWAV:
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / RATE
		var saw := fposmod(t * 120.0, 1.0) * 2.0 - 1.0
		var crackle := rng.randf_range(-1.0, 1.0) * (0.5 if rng.randf() < 0.02 else 0.05)
		s[i] = saw * 0.5 + 0.3 * sin(TAU * 240.0 * t) + crackle
	return to_wav(_normalize(s, 0.6), true)


## Footstep for a surface. Real steps are noise, not tones: a heel strike
## (a low "thump" of the floor and shoe), then the toe/sole a few tens of ms
## later, plus surface texture (carpet scuff, concrete grit, tile click).
## Built from noise through state-variable filters; no pure sine ringing,
## which is what made steps sound like a steel floor.
static func footstep(surface: int, variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + surface * 17 + variant * 3
	if surface == Player.SURF_WATER:
		return _water_step(rng, variant)
	if surface == Player.SURF_GRASS:
		return _grass_step(rng)
	var dur := 0.3
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	# Per surface: thump cutoff (Hz), thump level, click level, click decay,
	# scuff band centre, scuff level, toe delay (s).
	var thump_fc: float = [320.0, 650.0, 480.0][surface]
	var thump_amp: float = [1.0, 0.55, 0.8][surface]
	var click_amp: float = [0.04, 0.45, 0.35][surface]
	var click_decay: float = [400.0, 520.0, 260.0][surface]
	var scuff_fc: float = [850.0, 3200.0, 2400.0][surface]
	var scuff_amp: float = [0.15, 0.08, 0.2][surface]
	var toe := rng.randf_range(0.055, 0.085)
	var toe_amp := rng.randf_range(0.45, 0.7)
	var th := _Svf.new(thump_fc * rng.randf_range(0.85, 1.15), 0.9)
	var cl_lp := 0.0                      # one-pole low-pass; x - cl_lp = gentle high-pass
	var sc := _Svf.new(scuff_fc * rng.randf_range(0.8, 1.2), 1.4)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		# Envelopes: heel at 0, toe at `toe`, scuff spread over the roll.
		var heel := exp(-t * 55.0) * minf(t * RATE / 24.0, 1.0)
		var tt := t - toe
		var toe_env := 0.0 if tt < 0.0 else exp(-tt * 70.0) * minf(tt * RATE / 24.0, 1.0) * toe_amp
		var impact := heel + toe_env
		th.step(x)
		cl_lp += 0.45 * (x - cl_lp)
		sc.step(x)
		var v := th.low * impact * thump_amp * 4.0
		var ci := exp(-t * click_decay) + (0.0 if tt < 0.0 else exp(-tt * click_decay) * toe_amp * 0.7)
		v += (x - cl_lp) * ci * click_amp
		var scuff_env := exp(-pow((t - toe * 0.6) / 0.05, 2.0))
		v += sc.band * scuff_env * scuff_amp
		if surface == Player.SURF_CONCRETE and rng.randf() < 0.004:
			v += rng.randf_range(-1.0, 1.0) * 0.5 * exp(-t * 18.0)   # grit
		s[i] = v
	for i in 200:
		s[n - 1 - i] *= float(i) / 200.0
	return to_wav(_normalize(s, 0.8))


## Step on short grass: a soft, damped thump and a crisp rustle of blades.
static func _grass_step(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.32)
	var s := PackedFloat32Array()
	s.resize(n)
	var th := _Svf.new(220.0 * rng.randf_range(0.85, 1.15), 1.0)
	var ru := _Svf.new(4200.0 * rng.randf_range(0.8, 1.2), 1.6)
	var toe := rng.randf_range(0.06, 0.09)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		th.step(x)
		ru.step(x)
		var tt := t - toe
		var impact := exp(-t * 45.0) * minf(t * RATE / 40.0, 1.0) + (0.0 if tt < 0.0 else exp(-tt * 55.0) * 0.5)
		# Rustle: many tiny blade contacts, swelling and dying over the roll.
		var rustle := exp(-pow((t - 0.07) / 0.06, 2.0)) * (0.6 + 0.4 * rng.randf())
		s[i] = th.low * impact * 2.5 + ru.band * rustle * 0.5
	for i in 200:
		s[n - 1 - i] *= float(i) / 200.0
	return to_wav(_normalize(s, 0.7))


## Outdoor wind: broadband noise whose colour and level drift in slow gusts.
static func wind() -> AudioStreamWAV:
	var length := RATE * 12
	var n := length + RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lo := _Svf.new(380.0, 0.9)
	var hi := _Svf.new(1600.0, 2.5)
	var g := 0.4
	var gt := 0.5
	for i in n:
		if i % 4410 == 0:
			gt = rng.randf_range(0.15, 1.0)
		g += 0.00004 * (gt - g)
		var x := rng.randf_range(-1.0, 1.0)
		lo.f = 2.0 * sin(PI * (250.0 + 500.0 * g) / RATE)
		lo.step(x)
		hi.step(x)
		s[i] = lo.low * (0.4 + g) + hi.band * g * g * 0.12
	return to_wav(_normalize(_make_loop(s, length), 0.6), true)


## Wallpaper stretching: a slow papery groan with crackles as it strains
## (The Lining pressing through).
static func paper() -> AudioStreamWAV:
	var n := int(RATE * 1.8)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var groan := _Svf.new(320.0, 0.35)
	var crk := _Svf.new(2600.0, 1.2)
	var burst := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(1.1, 1.8, t))
		var x := rng.randf_range(-1.0, 1.0)
		groan.f = 2.0 * sin(PI * (240.0 + 120.0 * sin(t * 3.1) + 60.0 * t) / RATE)
		groan.step(x)
		# Crackles: random tiny bursts, denser in the middle of the strain.
		if rng.randf() < 0.0018 * env:
			burst = rng.randf_range(0.4, 1.0)
		burst *= 0.993
		crk.step(x * burst)
		s[i] = groan.band * env * 0.5 + crk.band * 1.4
	return to_wav(_normalize(s, 0.6))


## A long, low, breathy exhale far down a dark hall.
static func exhale() -> AudioStreamWAV:
	var n := int(RATE * 1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 92
	var f1 := _Svf.new(420.0, 0.6)
	var f2 := _Svf.new(1100.0, 0.9)
	for i in n:
		var t := float(i) / RATE
		var env := smoothstep(0.0, 0.25, t) * pow(1.0 - t / 1.6, 1.5)
		var x := rng.randf_range(-1.0, 1.0)
		# Formants sliding down a little, like air leaving a big chest.
		f1.f = 2.0 * sin(PI * (420.0 - 120.0 * t) / RATE)
		f1.step(x)
		f2.step(x)
		s[i] = (f1.band * 0.9 + f2.band * 0.25) * env
	return to_wav(_normalize(s, 0.5))


## Thin draught whistling through a door gap.
static func draught() -> AudioStreamWAV:
	var length := RATE * 6
	var n := length + RATE / 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 78
	var bp := _Svf.new(900.0, 0.12)
	var lo := _Svf.new(300.0, 1.0)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		bp.f = 2.0 * sin(PI * (820.0 + 90.0 * sin(t * 0.7) + 40.0 * sin(t * 2.3)) / RATE)
		bp.step(x)
		lo.step(x)
		s[i] = bp.band * (0.5 + 0.5 * sin(t * 0.9)) * 0.2 + lo.low * 0.6
	return to_wav(_normalize(_make_loop(s, length), 0.5), true)


static func _water_step(rng: RandomNumberGenerator, variant: int) -> AudioStreamWAV:
	var n := int(RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += 0.3 * (x - lp)
		lp2 += 0.03 * (lp - lp2)
		var env := (1.0 - exp(-t * 90.0)) * exp(-t * 7.0)
		# A second, smaller slosh as the water settles back (noise, no tones,
		# which rang like a 'twink' before).
		var t2 := t - (0.16 + variant * 0.015)
		var env2 := 0.0 if t2 < 0.0 else (1.0 - exp(-t2 * 60.0)) * exp(-t2 * 11.0) * 0.45
		s[i] = (lp - lp2) * (env + env2) * 2.2
	for i in 200:
		s[n - 1 - i] *= float(i) / 200.0
	return to_wav(_normalize(s, 0.8))


## Chamberlin state-variable filter (low / band / high outputs).
class _Svf:
	var f := 0.0                       # writable: callers may sweep the cutoff
	var q := 1.0
	var low := 0.0
	var band := 0.0
	var high := 0.0

	func _init(fc: float, damping: float) -> void:
		f = 2.0 * sin(PI * minf(fc, RATE * 0.16) / RATE)
		q = damping

	func step(x: float) -> void:
		low += f * band
		high = x - low - q * band
		band += f * high


static func click() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		var v := x * exp(-t * 400.0) + sin(TAU * 3200.0 * t) * exp(-t * 250.0) * 0.4
		var t2 := t - 0.05
		if t2 > 0.0:
			v += x * exp(-t2 * 500.0) * 0.6
		s[i] = v
	return to_wav(_normalize(s, 0.5))


# ------------------------------------------------------------- car park ---

## A car door unlatching and swinging open: a double click and a soft creak
## of the check strap.
static func car_latch() -> AudioStreamWAV:
	var n := int(RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 610
	var bp := _Svf.new(2600.0, 0.4)
	var body := _Svf.new(180.0, 0.15)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		var clicks := exp(-t * 300.0) + exp(-maxf(t - 0.035, 0.0) * 260.0) * float(t > 0.035) * 0.8
		bp.step(x * clicks)
		body.step(x * clicks * 2.0)
		var strap := sin(TAU * (240.0 + 60.0 * t) * t) * exp(-absf(t - 0.25) * 25.0) * 0.08
		s[i] = bp.band + body.band * 0.6 + strap
	return to_wav(_normalize(s, 0.6))


## A car door shutting: a deep, padded thump and the latch catching.
static func car_shut() -> AudioStreamWAV:
	var n := int(RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 611
	var lo := _Svf.new(110.0, 0.2)
	var panel := _Svf.new(380.0, 0.12)
	var hi := _Svf.new(3000.0, 0.5)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		var hit := exp(-t * 40.0) * (1.0 - exp(-t * 900.0))
		lo.step(x * hit * 4.0)
		panel.step(x * hit)
		hi.step(x * exp(-maxf(t - 0.02, 0.0) * 400.0) * float(t > 0.02))
		s[i] = lo.low * 1.4 + panel.band * 0.5 + hi.band * 0.3
	return to_wav(_normalize(s, 0.85))


## The starter turning the engine over (each compression a lurch), then it
## catches with a rev that settles.
static func car_crank() -> AudioStreamWAV:
	var n := int(RATE * 1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 612
	var whine := _Svf.new(420.0, 0.2)
	var body := _Svf.new(90.0, 0.25)
	var ph := 0.0
	var fire_ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		if t < 0.95:
			# Cranking: the starter's whine pulsing with each compression.
			ph += 5.5 / RATE
			var lurch := 0.55 + 0.45 * sin(TAU * ph)
			whine.step(x * lurch)
			v = whine.band * 1.6 * lurch * smoothstep(0.0, 0.05, t)
		var run := smoothstep(0.85, 1.0, t)
		if run > 0.0:
			# Firing: pulses at ~30 Hz, revving up and settling down.
			var rpm := 30.0 + 22.0 * exp(-(t - 1.0) * 5.0) * float(t > 1.0)
			fire_ph += rpm / RATE
			var pulse := pow(maxf(sin(TAU * fire_ph), 0.0), 6.0)
			body.step((pulse * 2.0 + x * 0.3) * run)
			v += body.low * 3.0
		s[i] = v
	return to_wav(_normalize(s, 0.8))


## A petrol engine idling, as a seamless loop.
static func car_idle() -> AudioStreamWAV:
	var n := int(RATE * 2.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 613
	var body := _Svf.new(85.0, 0.25)
	var hiss := _Svf.new(900.0, 0.6)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		# 30 firing pulses a second (a whole number per loop, so it loops).
		var pulse := pow(maxf(sin(TAU * 30.0 * t + 0.4 * sin(TAU * 1.5 * t)), 0.0), 6.0)
		body.step(pulse * 2.0 + x * 0.25)
		hiss.step(x * 0.1)
		s[i] = body.low * 3.0 + hiss.band * 0.4
	return to_wav(_make_loop(_normalize(s, 0.55), n - int(RATE * 0.1)), true)


## A flat battery: the starter solenoid clacking and nothing else.
static func car_dead() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 614
	var bp := _Svf.new(1800.0, 0.35)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		for k in 4:
			var kt := t - k * 0.13
			if kt > 0.0:
				v += x * exp(-kt * 220.0) * (1.0 - k * 0.15)
		bp.step(v)
		s[i] = bp.band
	return to_wav(_normalize(s, 0.6))


## Unsettling distant sounds: 0 thud, 1 metal creak, 2 knocking, 3 footsteps.
static func distant(kind: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + kind
	var dur: float = [3.0, 2.6, 2.0, 3.2][kind]
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lp += 0.03 * (x - lp)
		var v := 0.0
		match kind:
			0:
				v = (sin(TAU * 42.0 * t) * 0.8 + lp * 4.0) * exp(-t * 2.2) * (1.0 - exp(-t * 200.0))
			1:
				var f := 95.0 + 30.0 * sin(t * 3.1) + 15.0 * sin(t * 11.0)
				phase += f / RATE
				var saw := fposmod(phase, 1.0) * 2.0 - 1.0
				var env := sin(clampf(t / dur, 0.0, 1.0) * PI)
				v = saw * env * 0.35 * (0.6 + 0.4 * sin(t * 37.0)) + lp * env
			2:
				for k in 3:
					var kt := t - k * 0.38
					if kt > 0.0:
						v += (sin(TAU * 115.0 * kt) + lp * 3.0) * exp(-kt * 30.0)
			3:
				for k in 5:
					var kt := t - k * 0.62
					if kt > 0.0:
						v += (lp * 5.0 + sin(TAU * 70.0 * kt) * 0.6) * exp(-kt * 30.0)
		s[i] = v
	return to_wav(_normalize(s, 0.7))


# --------------------------------------------------------------- entities ---

## A hollow fibreglass foot on tile: a hard knock and a short boxy ring.
static func clack() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 501
	var bp := _Svf.new(1900.0, 0.35)
	var body := _Svf.new(430.0, 0.06)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0)
		bp.step(x)
		body.step(x * 3.0)
		s[i] = bp.band * 0.8 + body.band * exp(-t * 28.0) * 0.9
	return to_wav(_normalize(s, 0.8))


## The shell snapping as it wakes: a sharp crack and splintering crackle.
static func crack() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 502
	var hp := _Svf.new(2400.0, 0.5)
	var lo := _Svf.new(160.0, 0.4)
	var next := 0
	var amp := 0.0
	for i in n:
		var t := float(i) / RATE
		if i >= next:
			amp = rng.randf_range(0.3, 1.0) * exp(-t * 5.0)
			next = i + int(RATE * rng.randf_range(0.004, 0.04) * (1.0 + t * 4.0))
		var x := rng.randf_range(-1.0, 1.0)
		hp.step(x)
		lo.step(x)
		var bang := exp(-t * 60.0)
		s[i] = hp.high * (bang + amp * 0.35) + lo.low * bang * 2.5
	return to_wav(_normalize(s, 0.9))


## Stiff joints turning: a slow, stuttering creak.
static func creak() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 503
	var bp := _Svf.new(700.0, 0.05)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		# Stick-slip: a train of tiny clicks whose rate wanders.
		ph += (38.0 + 30.0 * sin(t * 9.0) + 15.0 * sin(t * 23.0)) / RATE
		var click := 1.0 if fposmod(ph, 1.0) < 0.06 else 0.0
		bp.f = 2.0 * sin(PI * (650.0 + 200.0 * sin(t * 3.0)) / RATE)
		bp.step(click + rng.randf_range(-0.05, 0.05))
		s[i] = bp.band * smoothstep(0.0, 0.05, t) * smoothstep(0.7, 0.45, t)
	return to_wav(_normalize(s, 0.6))


## The catch: a torn, rising shriek (noise and detuned saws, distorted).
## The Window Dresser's scream, right in your face. Layers: a sub-bass hit
## and a burst of noise (the startle); a voice gliding up into a howl,
## through vowel formants that slide from "ah" to "ee", ring-modulated so it
## sounds like it comes out of fibreglass rather than a throat; a second
## voice a tritone above and a third a quarter-tone flat, beating against
## it; a rising screech of filtered noise; crackling shell; and a wet
## gurgle as it dies away.
static func shriek() -> AudioStreamWAV:
	var dur := 2.4
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 504
	var f1 := _Svf.new(800.0, 0.18)
	var f2 := _Svf.new(1200.0, 0.14)
	var f3 := _Svf.new(2900.0, 0.12)
	var scr := _Svf.new(2500.0, 0.2)
	var hit := _Svf.new(90.0, 0.5)
	var ph := [0.0, 0.0, 0.0]
	var ratio := [1.0, 1.414, 0.971]
	var gain := [1.0, 0.55, 0.6]
	var ring := 0.0
	var sub := 0.0
	var jit := 0.0
	var next_click := 0
	var click := 0.0
	for i in n:
		var t := float(i) / RATE
		# Pitch: a lurch up, then a ragged, wavering howl, sagging at the end.
		jit = lerpf(jit, rng.randf_range(-1.0, 1.0), 0.002)
		var f := 260.0 + 880.0 * smoothstep(0.0, 0.14, t) - 220.0 * smoothstep(1.2, dur, t)
		f *= 1.0 + 0.05 * sin(TAU * 7.5 * t) * smoothstep(0.2, 0.5, t) + 0.06 * jit
		var voice := 0.0
		for k in 3:
			ph[k] = fposmod(ph[k] + f * ratio[k] / RATE, 1.0)
			voice += (ph[k] * 2.0 - 1.0) * gain[k]
		voice += rng.randf_range(-0.12, 0.12)                     # breath in the scream
		# Formants sliding from "ah" to "ee".
		var e := smoothstep(0.1, 0.9, t)
		f1.f = 2.0 * sin(PI * lerpf(820.0, 380.0, e) / RATE)
		f2.f = 2.0 * sin(PI * lerpf(1250.0, 2300.0, e) / RATE)
		f1.step(voice)
		f2.step(voice)
		f3.step(voice)
		var v := f1.band * 1.2 + f2.band * 1.0 + f3.band * 0.6
		ring = fposmod(ring + 233.0 / RATE, 1.0)
		v = lerpf(v, v * sin(TAU * ring) * 1.6, 0.4)
		# Screech: noise swept up behind the voice.
		scr.f = 2.0 * sin(PI * minf(lerpf(2000.0, 5200.0, smoothstep(0.0, 1.0, t)), RATE * 0.16) / RATE)
		scr.step(rng.randf_range(-1.0, 1.0))
		# Fibreglass cracking under it.
		if i >= next_click:
			click = rng.randf_range(0.4, 1.0)
			next_click = i + int(RATE * rng.randf_range(0.01, 0.07))
		click *= 0.993
		var crackle := rng.randf_range(-1.0, 1.0) * click * click
		# The hit: a falling sub thump and a noise burst.
		sub = fposmod(sub + lerpf(70.0, 32.0, minf(t * 2.5, 1.0)) / RATE, 1.0)
		hit.step(rng.randf_range(-1.0, 1.0))
		var thump := sin(TAU * sub) * exp(-t * 3.5) * 1.4 + hit.low * exp(-t * 18.0) * 3.0
		var env := smoothstep(0.0, 0.012, t) * (1.0 - smoothstep(1.7, dur, t))
		var gurgle := 1.0 - 0.6 * smoothstep(1.4, 1.9, t) * (0.5 + 0.5 * sin(TAU * 31.0 * t))
		var y := (v * 1.6 + scr.band * 0.22 * smoothstep(0.05, 0.4, t) + crackle * 0.25) * env * gurgle
		s[i] = tanh(y * 1.7) * 0.8 + thump * 0.6
	return to_wav(_normalize(s, 0.98))


## Its breathing while it hunts: a dry, rattling rasp in and out.
static func rasp() -> AudioStreamWAV:
	var dur := 1.1
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 611
	var a := _Svf.new(650.0, 0.35)
	var b := _Svf.new(1500.0, 0.3)
	var hp := _Svf.new(300.0, 0.7)
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		hp.step(x)
		a.step(hp.high)
		b.step(hp.high)
		# In (short) then out (longer), with a vocal-fry rattle.
		var env := sin(PI * clampf(t / 0.35, 0.0, 1.0)) * 0.6 + sin(PI * clampf((t - 0.4) / 0.7, 0.0, 1.0))
		var fry := 0.45 + 0.55 * pow(0.5 + 0.5 * sin(TAU * 38.0 * t + 2.0 * sin(TAU * 3.0 * t)), 3.0)
		s[i] = (a.band * 1.2 + b.band * 0.7) * env * fry
	return to_wav(_normalize(s, 0.7))


## The moment its face cracks open: a dissonant orchestral stab, a cluster
## of low brass-like tones and a smashed-glass top, ringing out.
static func sting() -> AudioStreamWAV:
	var dur := 2.6
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 712
	var freqs := [46.25, 49.0, 69.3, 98.0, 277.2, 293.7, 415.3]   # F#1 G1 C#2 G2 C#4 D4 G#4
	var ph := []
	for f in freqs:
		ph.append(rng.randf())
	var lp := _Svf.new(1800.0, 0.6)
	var hp := _Svf.new(3500.0, 0.4)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			var f: float = freqs[k] * (1.0 + 0.003 * sin(TAU * (0.7 + k * 0.3) * t))
			ph[k] = fposmod(ph[k] + f / RATE, 1.0)
			var saw: float = ph[k] * 2.0 - 1.0
			v += saw * (1.0 if k < 4 else 0.45)
		lp.f = 2.0 * sin(PI * lerpf(3000.0, 500.0, minf(t * 1.5, 1.0)) / RATE)
		lp.step(v)
		hp.step(rng.randf_range(-1.0, 1.0))
		var env := smoothstep(0.0, 0.01, t) * exp(-t * 1.4)
		var glass := hp.high * exp(-t * 7.0)
		s[i] = tanh(lp.low * 0.5 * env + glass * 0.8)
	return to_wav(_normalize(s, 0.95))


## One heartbeat (lub-dub), for the hunt; played faster as it gets closer.
## The Lobby's other walker: a heavy shoe on damp carpet, unlike your own
## soft steps: a deep heel thud, the sole rolling down a beat later, and
## a scuff of wet pile. Four variants (0..3).
static func stalk_step(variant: int) -> AudioStreamWAV:
	var n := int(RATE * 0.42)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var scuff := _Svf.new(rng.randf_range(700.0, 1000.0), 0.5)
	var knock := _Svf.new(rng.randf_range(260.0, 320.0), 0.12)
	var roll := rng.randf_range(0.06, 0.085)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		# Heel: a low thump falling in pitch.
		var f := 78.0 - 30.0 * minf(t * 12.0, 1.0)
		ph = fposmod(ph + f / RATE, 1.0)
		var heel := sin(TAU * ph) * exp(-t * 26.0) * smoothstep(0.0, 0.004, t)
		var t2 := t - roll
		var sole := sin(TAU * ph * 1.3) * exp(-maxf(t2, 0.0) * 34.0) * 0.55 if t2 > 0.0 else 0.0
		var x := rng.randf_range(-1.0, 1.0)
		knock.step(x * (exp(-t * 60.0) + (exp(-maxf(t2, 0.0) * 70.0) * 0.6 if t2 > 0.0 else 0.0)))
		scuff.step(x)
		var sc := scuff.band * 0.35 * smoothstep(0.02, 0.06, t) * exp(-maxf(t - 0.06, 0.0) * 14.0)
		s[i] = heel * 1.1 + sole + knock.band * 1.4 + sc
	return to_wav(_normalize(s, 0.95))


## A lift arriving: two soft chime tones, high then lower.
static func ding() -> AudioStreamWAV:
	var n := int(RATE * 1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for e in [[0.0, 1046.5], [0.32, 830.6]]:
			var tt: float = t - e[0]
			if tt > 0.0:
				var f: float = e[1]
				v += (sin(TAU * f * tt) + 0.3 * sin(TAU * f * 2.0 * tt) * exp(-tt * 6.0)) * exp(-tt * 3.2) * smoothstep(0.0, 0.004, tt)
		s[i] = v
	return to_wav(_normalize(s, 0.7))


static func heartbeat() -> AudioStreamWAV:
	var n := int(RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var e1 := exp(-maxf(t, 0.0) * 28.0) * smoothstep(0.0, 0.008, t)
		var t2 := t - 0.2
		var e2 := exp(-maxf(t2, 0.0) * 32.0) * smoothstep(0.0, 0.008, t2) * 0.7 if t2 > 0.0 else 0.0
		var f := 52.0 - 14.0 * minf(t * 4.0, 1.0)
		ph = fposmod(ph + f / RATE, 1.0)
		s[i] = sin(TAU * ph) * (e1 + e2)
	return to_wav(_normalize(s, 0.95))
