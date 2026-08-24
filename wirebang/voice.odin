package wirebang

import "core:math"
import "core:math/rand"

DEFAULT_SAMPLE_RATE :: 48000
CHANNELS :: 2

Auto_Kind :: enum {
	Set,
	Lin,
	Exp,
}

Auto_Event :: struct {
	time:  f32,
	value: f32,
	kind:  Auto_Kind,
}

Voice_Node :: struct {
	id:         string,
	kind:       Node_Kind,
	osc_type:   Osc_Type,
	phase:      f32,
	freq:       [dynamic]Auto_Event,
	gain:       [dynamic]Auto_Event,
	start_time: f32,
	stop_time:  f32,
	has_window: bool,
	noise:      []f32,
	noise_pos:  int,
	filter:     Filter_Type,
	q:          f32,
	z1, z2:     f32,
	b0, b1, b2: f32,
	a1, a2:     f32,
	last_freq:  f32,
	amount:     f32,
	pan:        f32,
	inputs:     [dynamic]int,
	to_out:     bool,
	mono:       f32,
	left:       f32,
	right:      f32,
}

Voice :: struct {
	sample_rate: f32,
	frame:       u64,
	length:      u64,
	nodes:       []Voice_Node,
	ended:       bool,
}

destroy_voice :: proc(v: ^Voice) {
	if v == nil {
		return
	}
	for &n in v.nodes {
		delete(n.freq)
		delete(n.gain)
		delete(n.noise)
		delete(n.inputs)
	}
	delete(v.nodes)
	v^ = {}
}

@(private)
eval_param :: proc(events: []Auto_Event, t: f32, fallback: f32) -> f32 {
	if len(events) == 0 {
		return fallback
	}
	last_value := fallback
	last_time: f32 = 0
	last_set := false
	for e in events {
		if e.time > t {
			if !last_set {
				return e.kind == .Set ? fallback : e.value
			}
			span := e.time - last_time
			if span <= 0 {
				return last_value
			}
			x := (t - last_time) / span
			switch e.kind {
			case .Set:
				return last_value
			case .Lin:
				return last_value + (e.value - last_value) * x
			case .Exp:
				a := max(last_value, 0.001)
				b := max(e.value, 0.001)
				return a * math.pow(b / a, x)
			}
		}
		last_value = e.value
		last_time = e.time
		last_set = true
	}
	return last_value
}

@(private)
osc_sample :: proc(type: Osc_Type, phase: f32) -> f32 {
	switch type {
	case .Sine:
		return math.sin(phase * math.TAU)
	case .Square:
		return 1 if phase < 0.5 else -1
	case .Sawtooth:
		return 2 * phase - 1
	case .Triangle:
		if phase < 0.5 {
			return 4 * phase - 1
		}
		return 3 - 4 * phase
	}
	return 0
}

@(private)
set_biquad :: proc(n: ^Voice_Node, freq, sample_rate: f32) {
	f := clamp(freq, 10, sample_rate * 0.45)
	w := math.TAU * f / sample_rate
	sin_w := math.sin(w)
	cos_w := math.cos(w)
	q := max(n.q, 0.0001)
	alpha := sin_w / (2 * q)
	b0, b1, b2, a0, a1, a2: f32
	switch n.filter {
	case .Lowpass:
		b0 = (1 - cos_w) * 0.5
		b1 = 1 - cos_w
		b2 = (1 - cos_w) * 0.5
		a0 = 1 + alpha
		a1 = -2 * cos_w
		a2 = 1 - alpha
	case .Highpass:
		b0 = (1 + cos_w) * 0.5
		b1 = -(1 + cos_w)
		b2 = (1 + cos_w) * 0.5
		a0 = 1 + alpha
		a1 = -2 * cos_w
		a2 = 1 - alpha
	case .Bandpass:
		b0 = alpha
		b1 = 0
		b2 = -alpha
		a0 = 1 + alpha
		a1 = -2 * cos_w
		a2 = 1 - alpha
	case .Notch:
		b0 = 1
		b1 = -2 * cos_w
		b2 = 1
		a0 = 1 + alpha
		a1 = -2 * cos_w
		a2 = 1 - alpha
	}
	n.b0 = b0 / a0
	n.b1 = b1 / a0
	n.b2 = b2 / a0
	n.a1 = a1 / a0
	n.a2 = a2 / a0
	n.last_freq = f
}

@(private)
biquad_tick :: proc(n: ^Voice_Node, x: f32) -> f32 {
	y := n.b0 * x + n.z1
	n.z1 = n.b1 * x - n.a1 * y + n.z2
	n.z2 = n.b2 * x - n.a2 * y
	return y
}

distortion_curve :: proc(k: f32, x: f32) -> f32 {
	return ((math.PI + k) * x) / (math.PI + k * abs(x))
}

make_noise_buffer :: proc(duration, sample_rate: f32, allocator := context.allocator) -> []f32 {
	length := max(1, int(math.ceil(f64(sample_rate * duration))))
	data := make([]f32, length, allocator)
	for i in 0 ..< length {
		data[i] = rand.float32() * 2 - 1
	}
	return data
}

voice_from_patch :: proc(patch: Patch, sample_rate: f32 = DEFAULT_SAMPLE_RATE, allocator := context.allocator) -> Voice {
	plan := plan_patch(patch, context.temp_allocator)
	v: Voice
	v.sample_rate = sample_rate
	v.length = u64(math.ceil(f64(patch_duration(patch) * sample_rate)))
	v.nodes = make([]Voice_Node, len(plan.nodes), allocator)

	index_of := make(map[string]int, context.temp_allocator)
	for planned, i in plan.nodes {
		index_of[planned.id] = i
		n := &v.nodes[i]
		n.id = planned.id
		n.inputs = make([dynamic]int, allocator)
		switch planned.create.kind {
		case .Osc:
			n.kind = .Osc
			n.osc_type = planned.create.osc
			n.has_window = true
		case .Noise:
			n.kind = .Noise
			n.noise = make_noise_buffer(planned.create.duration, sample_rate, allocator)
			n.has_window = true
		case .Filter:
			n.kind = .Filter
			n.filter = planned.create.filter
			n.q = planned.create.q
		case .Gain:
			n.kind = .Gain
		case .Shaper:
			n.kind = .Shaper
			n.amount = planned.create.amount
		case .Panner:
			n.kind = .Panner
			n.pan = planned.create.pan
		}
		n.freq = make([dynamic]Auto_Event, allocator)
		n.gain = make([dynamic]Auto_Event, allocator)
		for a in planned.actions {
			switch a.kind {
			case .Set:
				ev := Auto_Event{time = a.time, value = eval_num(a.value), kind = .Set}
				if a.param == .Frequency {
					append(&n.freq, ev)
				} else {
					append(&n.gain, ev)
				}
			case .Ramp:
				ev := Auto_Event {
					time  = a.time,
					value = eval_num(a.value),
					kind  = a.curve == .Lin ? .Lin : .Exp,
				}
				if a.param == .Frequency {
					append(&n.freq, ev)
				} else {
					append(&n.gain, ev)
				}
			case .Start:
				n.start_time = a.time
			case .Stop:
				n.stop_time = a.time
			}
		}
		if n.kind == .Filter {
			set_biquad(n, eval_param(n.freq[:], 0, 1000), sample_rate)
		}
	}

	for e in plan.edges {
		if e.to == "out" {
			if i, ok := index_of[e.from]; ok {
				v.nodes[i].to_out = true
			}
			continue
		}
		from_i, fok := index_of[e.from]
		to_i, tok := index_of[e.to]
		if fok && tok {
			append(&v.nodes[to_i].inputs, from_i)
		}
	}

	// Process sources before processors: plan already ranks that way.
	return v
}

@(private)
mix_inputs :: proc(v: ^Voice, n: Voice_Node) -> f32 {
	if len(n.inputs) == 0 {
		return 0
	}
	sum: f32
	for i in n.inputs {
		in_n := v.nodes[i]
		sum += (in_n.left + in_n.right) * 0.5
	}
	return sum
}

voice_tick :: proc(v: ^Voice) -> (left, right: f32, ok: bool) {
	if v.ended || v.frame >= v.length {
		v.ended = true
		return 0, 0, false
	}
	t := f32(v.frame) / v.sample_rate
	for &n in v.nodes {
		n.mono = 0
		n.left = 0
		n.right = 0
		switch n.kind {
		case .Osc:
			if t + 1e-9 < n.start_time || t >= n.stop_time {
				break
			}
			freq := eval_param(n.freq[:], t, 440)
			n.mono = osc_sample(n.osc_type, n.phase)
			n.phase += freq / v.sample_rate
			n.phase -= math.floor(n.phase)
			n.left = n.mono
			n.right = n.mono
		case .Noise:
			if t + 1e-9 < n.start_time || t >= n.stop_time {
				break
			}
			if n.noise_pos < len(n.noise) {
				n.mono = n.noise[n.noise_pos]
				n.noise_pos += 1
			}
			n.left = n.mono
			n.right = n.mono
		case .Filter:
			x := mix_inputs(v, n)
			freq := eval_param(n.freq[:], t, n.last_freq)
			if abs(freq - n.last_freq) > 0.5 {
				set_biquad(&n, freq, v.sample_rate)
			}
			n.mono = biquad_tick(&n, x)
			n.left = n.mono
			n.right = n.mono
		case .Gain:
			x := mix_inputs(v, n)
			g := eval_param(n.gain[:], t, 1)
			n.mono = x * g
			n.left = n.mono
			n.right = n.mono
		case .Shaper:
			x := mix_inputs(v, n)
			n.mono = distortion_curve(n.amount, clamp(x, -1, 1))
			n.left = n.mono
			n.right = n.mono
		case .Panner:
			x := mix_inputs(v, n)
			angle := (n.pan + 1) * (math.PI * 0.25)
			n.left = x * math.cos(angle)
			n.right = x * math.sin(angle)
		case .Out:
		}
	}
	for n in v.nodes {
		if n.to_out {
			left += n.left
			right += n.right
		}
	}
	v.frame += 1
	if v.frame >= v.length {
		v.ended = true
	}
	return left, right, true
}

render_frames :: proc(v: ^Voice, frames: []f32) -> int {
	wrote := 0
	for i := 0; i + 1 < len(frames); i += 2 {
		l, r, ok := voice_tick(v)
		if !ok {
			break
		}
		frames[i] = l
		frames[i + 1] = r
		wrote += 1
	}
	return wrote
}
