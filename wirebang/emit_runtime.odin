package wirebang

import "core:strings"

@(private)
Helper_Need :: struct {
	noise:      bool,
	osc:        bool,
	filter:     bool,
	gain:       bool,
	shaper:     bool,
	panner:     bool,
	delay:      bool,
	mix:        bool,
	add_mono:   bool,
	add_stereo: bool,
	downmix:    bool,
}

@(private)
write_helpers :: proc(b: ^strings.Builder, need: Helper_Need) {
	if need.osc {
		strings.write_string(b, HELPER_RAMP)
		strings.write_string(b, HELPER_WAVEFORM)
	}
	if need.noise {
		strings.write_string(b, HELPER_NOISE)
	}
	if need.filter {
		strings.write_string(b, HELPER_BIQUAD)
	}
	if need.gain {
		strings.write_string(b, HELPER_GAIN)
	}
	if need.shaper {
		strings.write_string(b, HELPER_SHAPER)
	}
	if need.panner {
		strings.write_string(b, HELPER_PAN)
	}
	if need.delay {
		strings.write_string(b, HELPER_DELAY)
	}
	if need.mix {
		strings.write_string(b, HELPER_MIX)
	}
	if need.downmix {
		strings.write_string(b, HELPER_DOWNMIX)
	}
	if need.add_mono {
		strings.write_string(b, HELPER_ADD_MONO)
	}
	if need.add_stereo {
		strings.write_string(b, HELPER_ADD_STEREO)
	}
	strings.write_string(b, HELPER_SUBMIT)
}

@(private)
HELPER_RAMP :: `

@(private="file")
Ramp :: enum {
	lin,
	exp,
}
`

@(private)
HELPER_WAVEFORM :: `
@(private="file")
read_waveform_ramp :: proc(w: ^ma.waveform, out: []f32, sr: u32, f0, f1, start, stop: f32, curve: Ramp) {
	n := len(out)
	i0 := clamp(int(start * f32(sr)), 0, n)
	i1 := clamp(int(stop * f32(sr)), 0, n)
	if i1 <= i0 {
		return
	}
	span := stop - start
	if f0 == f1 || span <= 0 {
		ma.waveform_set_frequency(w, f64(f0))
		ma.waveform_read_pcm_frames(w, raw_data(out[i0:i1]), u64(i1 - i0), nil)
		return
	}
	for i in i0 ..< i1 {
		x := (f32(i) / f32(sr) - start) / span
		f: f32
		if curve == .exp {
			a := max(f0, 0.001)
			b := max(f1, 0.001)
			f = a * math.pow(b / a, x)
		} else {
			f = f0 + (f1 - f0) * x
		}
		ma.waveform_set_frequency(w, f64(f))
		ma.waveform_read_pcm_frames(w, &out[i], 1, nil)
	}
}
`

@(private)
HELPER_NOISE :: `
@(private="file")
read_noise_window :: proc(src: ^ma.noise, out: []f32, sr: u32, start, stop: f32) {
	n := len(out)
	i0 := clamp(int(start * f32(sr)), 0, n)
	i1 := clamp(int(stop * f32(sr)), 0, n)
	if i1 <= i0 {
		return
	}
	ma.noise_read_pcm_frames(src, raw_data(out[i0:i1]), u64(i1 - i0), nil)
}
`

@(private)
HELPER_BIQUAD :: `
@(private="file")
Biquad_Kind :: enum {
	lowpass,
	highpass,
	bandpass,
	notch,
}

@(private="file")
rbj_config :: proc(sr: u32, kind: Biquad_Kind, freq, q: f32) -> ma.biquad_config {
	f := clamp(freq, 10, f32(sr) * 0.45)
	w := math.TAU * f / f32(sr)
	sin_w := math.sin(w)
	cos_w := math.cos(w)
	qq := max(q, 0.0001)
	alpha := sin_w / (2 * qq)
	b0, b1, b2, a0, a1, a2: f32
	switch kind {
	case .lowpass:
		b0 = (1 - cos_w) * 0.5
		b1 = 1 - cos_w
		b2 = (1 - cos_w) * 0.5
		a0 = 1 + alpha
		a1 = -2 * cos_w
		a2 = 1 - alpha
	case .highpass:
		b0 = (1 + cos_w) * 0.5
		b1 = -(1 + cos_w)
		b2 = (1 + cos_w) * 0.5
		a0 = 1 + alpha
		a1 = -2 * cos_w
		a2 = 1 - alpha
	case .bandpass:
		b0 = alpha
		b1 = 0
		b2 = -alpha
		a0 = 1 + alpha
		a1 = -2 * cos_w
		a2 = 1 - alpha
	case .notch:
		b0 = 1
		b1 = -2 * cos_w
		b2 = 1
		a0 = 1 + alpha
		a1 = -2 * cos_w
		a2 = 1 - alpha
	}
	return ma.biquad_config_init(.f32, 1, f64(b0 / a0), f64(b1 / a0), f64(b2 / a0), 1, f64(a1 / a0), f64(a2 / a0))
}

@(private="file")
biquad_init_rbj :: proc(bq: ^ma.biquad, sr: u32, kind: Biquad_Kind, freq, q: f32) -> bool {
	cfg := rbj_config(sr, kind, freq, q)
	return ma.biquad_init(&cfg, nil, bq) == .SUCCESS
}

@(private="file")
biquad_sweep :: proc(bq: ^ma.biquad, in_buf, out_buf: []f32, sr: u32, kind: Biquad_Kind, q, f0, f1, ramp_time: f32) {
	n := min(len(in_buf), len(out_buf))
	last := f0
	cfg := rbj_config(sr, kind, f0, q)
	ma.biquad_reinit(&cfg, bq)
	for i in 0 ..< n {
		f := f0
		if ramp_time > 0 && f1 != f0 {
			x := clamp((f32(i) / f32(sr)) / ramp_time, 0, 1)
			a := max(f0, 0.001)
			b := max(f1, 0.001)
			f = a * math.pow(b / a, x)
		}
		if abs(f - last) > 0.5 {
			cfg = rbj_config(sr, kind, f, q)
			ma.biquad_reinit(&cfg, bq)
			last = f
		}
		x := in_buf[i]
		ma.biquad_process_pcm_frames(bq, &out_buf[i], &x, 1)
	}
}
`

@(private)
HELPER_GAIN :: `
@(private="file")
gain_env :: proc(in_buf, out_buf: []f32, sr: u32, peak, start, stop: f32) {
	n := min(len(in_buf), len(out_buf))
	span := stop - start
	for i in 0 ..< n {
		t := f32(i) / f32(sr)
		g: f32 = 0
		if t >= start && t < stop && span > 0 {
			x := (t - start) / span
			a := max(peak, 0.001)
			g = a * math.pow(f32(0.001) / a, x)
		}
		out_buf[i] = in_buf[i] * g
	}
}
`

@(private)
HELPER_SHAPER :: `
@(private="file")
waveshape :: proc(in_buf, out_buf: []f32, amount: f32) {
	n := min(len(in_buf), len(out_buf))
	for i in 0 ..< n {
		x := clamp(in_buf[i], -1, 1)
		out_buf[i] = ((math.PI + amount) * x) / (math.PI + amount * abs(x))
	}
}
`

@(private)
HELPER_PAN :: `
@(private="file")
pan_to_stereo :: proc(in_buf, out_buf: []f32, pan: f32) {
	angle := (pan + 1) * (math.PI * 0.25)
	l := math.cos(angle)
	r := math.sin(angle)
	n := min(len(in_buf), len(out_buf) / 2)
	for i in 0 ..< n {
		out_buf[i * 2] = in_buf[i] * l
		out_buf[i * 2 + 1] = in_buf[i] * r
	}
}
`

@(private)
HELPER_DELAY :: `
@(private="file")
delay_line :: proc(in_buf, out_buf: []f32, sr: u32, time, mix, feedback: f32) {
	n := min(len(in_buf), len(out_buf))
	buf_len := int(math.ceil_f64(f64(sr) * f64(time))) + 1
	delay_buf := make([]f32, buf_len)
	defer delete(delay_buf)
	pos := 0
	for i in 0 ..< n {
		tap := delay_buf[pos]
		delay_buf[pos] = in_buf[i] + tap * feedback
		pos = (pos + 1) % buf_len
		out_buf[i] = in_buf[i] * (1 - mix) + tap * mix
	}
}
`

@(private)
HELPER_MIX :: `
@(private="file")
mix_mono :: proc(bufs: ..[]f32) -> []f32 {
	n := 0
	for buf in bufs {
		n = max(n, len(buf))
	}
	out := make([]f32, n)
	for buf in bufs {
		for i in 0 ..< len(buf) {
			out[i] += buf[i]
		}
	}
	return out
}
`

@(private)
HELPER_DOWNMIX :: `
@(private="file")
downmix :: proc(stereo: []f32, frames: int) -> []f32 {
	out := make([]f32, frames)
	n := min(frames, len(stereo) / 2)
	for i in 0 ..< n {
		out[i] = (stereo[i * 2] + stereo[i * 2 + 1]) * 0.5
	}
	return out
}
`

@(private)
HELPER_ADD_MONO :: `
@(private="file")
add_mono_to_stereo :: proc(out, mono: []f32) {
	n := min(len(mono), len(out) / 2)
	for i in 0 ..< n {
		out[i * 2] += mono[i]
		out[i * 2 + 1] += mono[i]
	}
}
`

@(private)
HELPER_ADD_STEREO :: `
@(private="file")
add_stereo :: proc(out, stereo: []f32) {
	n := min(len(out), len(stereo))
	for i in 0 ..< n {
		out[i] += stereo[i]
	}
}
`

@(private)
HELPER_SUBMIT :: `
@(private="file")
MAX_PLAYING :: 8

@(private="file")
Playing :: struct {
	used:   bool,
	buffer: ma.audio_buffer,
	sound:  ma.sound,
}

@(private="file")
g_playing: [MAX_PLAYING]Playing

@(private="file")
reap_playing :: proc() {
	for &slot in g_playing {
		if slot.used && bool(ma.sound_at_end(&slot.sound)) {
			ma.sound_uninit(&slot.sound)
			ma.audio_buffer_uninit(&slot.buffer)
			slot.used = false
		}
	}
}

@(private="file")
submit_pcm :: proc(engine: ^ma.engine, frames: []f32, sr: u32) {
	if engine == nil || len(frames) < 2 {
		return
	}
	reap_playing()
	slot: ^Playing
	for &s in g_playing {
		if !s.used {
			slot = &s
			break
		}
	}
	if slot == nil {
		slot = &g_playing[0]
		ma.sound_uninit(&slot.sound)
		ma.audio_buffer_uninit(&slot.buffer)
		slot.used = false
	}
	nframes := u64(len(frames) / 2)
	cfg := ma.audio_buffer_config_init(.f32, 2, nframes, raw_data(frames), nil)
	cfg.sampleRate = sr
	if ma.audio_buffer_init_copy(&cfg, &slot.buffer) != .SUCCESS {
		return
	}
	flags := ma.sound_flags{.NO_PITCH, .NO_SPATIALIZATION}
	if ma.sound_init_from_data_source(engine, cast(^ma.data_source)&slot.buffer, flags, nil, &slot.sound) != .SUCCESS {
		ma.audio_buffer_uninit(&slot.buffer)
		return
	}
	if ma.sound_start(&slot.sound) != .SUCCESS {
		ma.sound_uninit(&slot.sound)
		ma.audio_buffer_uninit(&slot.buffer)
		return
	}
	slot.used = true
}
`
