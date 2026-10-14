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


## Gentle lapping water for the Poolrooms.
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
