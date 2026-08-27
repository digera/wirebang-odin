package wirebang

import "core:strconv"
import "core:strings"
import "core:unicode"

parse_code :: proc(src: string, allocator := context.allocator) -> (Patch, bool) {
	fn := extract_fn_name(src)
	body, body_ok := extract_play_body(src, fn)
	if !body_ok {
		return {}, false
	}

	p := empty_patch(allocator)
	delete(p.name)
	delete(p.fn_name)
	p.fn_name = strings.clone(fn, allocator)
	stem := strings.trim_prefix(fn, "play_")
	if stem == "" || stem == fn {
		stem = "sound"
	}
	p.name = strings.clone(title_stem(stem, context.temp_allocator), allocator)

	taken := taken_ids(p, context.temp_allocator)
	name_to_id := make(map[string]string, context.temp_allocator)
	name_to_id["out"] = "out"
	buf_to_id := make(map[string]string, context.temp_allocator)
	mix_ids := make(map[string][dynamic]string, context.temp_allocator)
	drafts := make(map[string]Draft, context.temp_allocator)

	lines := strings.split_lines(body, context.temp_allocator)
	for raw in lines {
		line := strip_comment(strings.trim_space(raw))
		if line == "" {
			continue
		}
		if skip_line(line) {
			continue
		}
		if name, type, ok := parse_typed_decl(line); ok {
			kind, kok := ma_type_kind(type)
			if !kok {
				continue
			}
			ensure_node(&p, &taken, &name_to_id, &drafts, &buf_to_id, kind, name, allocator)
			continue
		}
		if lhs, rhs, ok := split_assign(line); ok {
			if apply_assign(&p, &taken, &name_to_id, &drafts, &buf_to_id, &mix_ids, lhs, rhs, allocator) {
				continue
			}
		}
		if callee, args, ok := parse_call(line); ok {
			if !apply_call(&p, &taken, &name_to_id, &drafts, &buf_to_id, &mix_ids, callee, args, allocator) {
				destroy_patch(&p)
				return {}, false
			}
		}
	}

	for _, d in drafts {
		if n := find_node_ptr(&p, d.id); n != nil {
			apply_draft(n, d)
		}
	}

	layout_parsed(&p)
	if !is_patch(p) {
		destroy_patch(&p)
		return {}, false
	}
	return p, true
}

@(private)
Draft :: struct {
	id, name:             string,
	kind:                 Node_Kind,
	osc:                  Osc_Type,
	filter:               Filter_Type,
	ramp:                 Ramp_Curve,
	freq, freq_end:       f32,
	q, peak, amount, pan: f32,
	duration, delay:      f32,
	ramp_time, jitter:    f32,
	start, stop:          f32,
	has_start, has_stop:  bool,
	has_ramp:             bool,
	time, mix, feedback:  f32,
}

@(private)
title_stem :: proc(stem: string, allocator := context.allocator) -> string {
	if len(stem) == 0 {
		return strings.clone("Sound", allocator)
	}
	b := strings.builder_make(allocator)
	cap_next := true
	for r in stem {
		if r == '_' {
			strings.write_rune(&b, ' ')
			cap_next = true
			continue
		}
		if cap_next {
			strings.write_rune(&b, unicode.to_upper(r))
			cap_next = false
		} else {
			strings.write_rune(&b, r)
		}
	}
	return strings.to_string(b)
}

@(private)
extract_fn_name :: proc(src: string) -> string {
	idx := 0
	for idx < len(src) {
		i := strings.index(src[idx:], "play_")
		if i < 0 {
			break
		}
		i += idx
		j := i
		for j < len(src) && is_ident_byte(src[j]) {
			j += 1
		}
		name := src[i:j]
		rest := strings.trim_left_space(src[j:])
		if strings.has_prefix(rest, "::") {
			return name
		}
		idx = j
	}
	return "play_sound"
}

@(private)
is_ident_byte :: proc(b: u8) -> bool {
	return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_'
}

@(private)
extract_play_body :: proc(src: string, fn: string) -> (string, bool) {
	needle := strings.concatenate({fn, " :: proc"}, context.temp_allocator)
	i := strings.index(src, needle)
	if i < 0 {
		return "", false
	}
	rest := src[i:]
	brace := strings.index_byte(rest, '{')
	if brace < 0 {
		return "", false
	}
	depth := 0
	for j in brace ..< len(rest) {
		c := rest[j]
		if c == '{' {
			depth += 1
		} else if c == '}' {
			depth -= 1
			if depth == 0 {
				return rest[brace + 1:j], true
			}
		}
	}
	return "", false
}

@(private)
strip_comment :: proc(line: string) -> string {
	in_str := false
	for i in 0 ..< len(line) {
		if line[i] == '"' {
			in_str = !in_str
		}
		if !in_str && i + 1 < len(line) && line[i] == '/' && line[i + 1] == '/' {
			return strings.trim_space(line[:i])
		}
	}
	return line
}

@(private)
skip_line :: proc(line: string) -> bool {
	if strings.has_prefix(line, "if ") || strings.has_prefix(line, "defer ") {
		return true
	}
	if line == "return" || strings.has_prefix(line, "return ") {
		return true
	}
	if strings.has_prefix(line, "submit_pcm(") {
		return true
	}
	return false
}

@(private)
split_args :: proc(s: string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	start := 0
	depth := 0
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case '(', '{', '[':
			depth += 1
		case ')', '}', ']':
			depth -= 1
		case ',':
			if depth == 0 {
				append(&out, strings.trim_space(s[start:i]))
				start = i + 1
			}
		}
	}
	tail := strings.trim_space(s[start:])
	if tail != "" {
		append(&out, tail)
	}
	return out[:]
}

@(private)
parse_typed_decl :: proc(line: string) -> (name, type: string, ok: bool) {
	if strings.contains(line, ":=") {
		return
	}
	colon := strings.index_byte(line, ':')
	if colon <= 0 {
		return
	}
	name = strings.trim_space(line[:colon])
	type = strings.trim_space(line[colon + 1:])
	if name == "" || !strings.has_prefix(type, "ma.") {
		return
	}
	ok = true
	return
}

@(private)
ma_type_kind :: proc(type: string) -> (Node_Kind, bool) {
	switch strings.trim_space(type) {
	case "ma.waveform":
		return .Osc, true
	case "ma.noise":
		return .Noise, true
	case "ma.biquad":
		return .Filter, true
	}
	return .Osc, false
}

@(private)
split_assign :: proc(line: string) -> (lhs, rhs: string, ok: bool) {
	eq := strings.index(line, ":=")
	if eq < 0 {
		return
	}
	lhs = strings.trim_space(line[:eq])
	rhs = strings.trim_space(line[eq + 2:])
	ok = lhs != "" && rhs != ""
	return
}

@(private)
parse_call :: proc(line: string) -> (callee: string, args: []string, ok: bool) {
	if strings.contains(line, ":=") {
		return
	}
	paren := strings.index_byte(line, '(')
	if paren < 0 || !strings.has_suffix(line, ")") {
		return
	}
	callee = strings.trim_space(line[:paren])
	args = split_args(line[paren + 1:len(line) - 1])
	ok = callee != ""
	return
}

@(private)
parse_call_expr :: proc(expr: string) -> (callee: string, args: []string, ok: bool) {
	expr := strings.trim_space(expr)
	paren := strings.index_byte(expr, '(')
	if paren < 0 || !strings.has_suffix(expr, ")") {
		return
	}
	callee = strings.trim_space(expr[:paren])
	args = split_args(expr[paren + 1:len(expr) - 1])
	ok = callee != ""
	return
}

@(private)
strip_ref :: proc(s: string) -> string {
	s := strings.trim_space(s)
	return strings.trim_prefix(s, "&")
}

@(private)
stem_suffix :: proc(s, suffix: string) -> (string, bool) {
	if strings.has_suffix(s, suffix) && len(s) > len(suffix) {
		return s[:len(s) - len(suffix)], true
	}
	return "", false
}

@(private)
buf_stem :: proc(s: string) -> string {
	s := strip_ref(s)
	if stem, ok := stem_suffix(s, "_buf"); ok {
		return stem
	}
	if stem, ok := stem_suffix(s, "_in"); ok {
		return stem
	}
	return s
}

@(private)
parse_enum_token :: proc(s: string) -> string {
	s := strings.trim_space(s)
	s = strings.trim_prefix(s, ".")
	return s
}

@(private)
parse_osc_type :: proc(s: string) -> Osc_Type {
	switch parse_enum_token(s) {
	case "sine", "Sine":
		return .Sine
	case "square", "Square":
		return .Square
	case "sawtooth", "Sawtooth":
		return .Sawtooth
	case "triangle", "Triangle":
		return .Triangle
	}
	return .Sine
}

@(private)
parse_filter_type :: proc(s: string) -> Filter_Type {
	switch parse_enum_token(s) {
	case "lowpass", "Lowpass":
		return .Lowpass
	case "highpass", "Highpass":
		return .Highpass
	case "bandpass", "Bandpass":
		return .Bandpass
	case "notch", "Notch":
		return .Notch
	}
	return .Bandpass
}

@(private)
parse_num :: proc(s: string) -> (Num_Expr, bool) {
	s := strings.trim_space(s)
	if strings.has_prefix(s, "max(f32(0.001),") && strings.has_suffix(s, ")") {
		inner := strings.trim_space(s[len("max(f32(0.001),"):len(s) - 1])
		n, ok := parse_num(inner)
		n.max_exp = true
		return n, ok
	}
	if strings.has_prefix(s, "max(0.001,") && strings.has_suffix(s, ")") {
		inner := strings.trim_space(s[len("max(0.001,"):len(s) - 1])
		n, ok := parse_num(inner)
		n.max_exp = true
		return n, ok
	}
	if star := strings.index(s, " * ("); star > 0 && strings.has_suffix(s, ")") && strings.contains(s, "rand.float32()") {
		lit_s := strings.trim_space(s[:star])
		inner := s[star + 4:len(s) - 1]
		mark := " + rand.float32() * "
		at := strings.index(inner, mark)
		if at >= 0 {
			a_s := strings.trim_space(inner[:at])
			b_s := strings.trim_space(inner[at + len(mark):])
		v, vok := parse_num(lit_s)
		b, bok := parse_num(b_s)
		_ = a_s
		if vok && bok {
			return Num_Expr{value = v.value, jitter = b.value * 0.5}, true
		}
		}
	}
	if strings.has_prefix(s, "f32(") && strings.has_suffix(s, ")") {
		return parse_num(s[len("f32("):len(s) - 1])
	}
	if strings.has_prefix(s, "f64(") && strings.has_suffix(s, ")") {
		return parse_num(s[len("f64("):len(s) - 1])
	}
	v, ok := strconv.parse_f32(s)
	return Num_Expr{value = v}, ok
}

@(private)
draft_ptr :: proc(drafts: ^map[string]Draft, name: string) -> ^Draft {
	if name in drafts^ {
		return &drafts[name]
	}
	return nil
}

@(private)
ensure_node :: proc(
	p: ^Patch,
	taken: ^map[string]bool,
	name_to_id: ^map[string]string,
	drafts: ^map[string]Draft,
	buf_to_id: ^map[string]string,
	kind: Node_Kind,
	name: string,
	allocator := context.allocator,
) -> ^Draft {
	if name in name_to_id^ && name_to_id[name] != "out" {
		if name in drafts^ {
			return &drafts[name]
		}
	}
	id := uid(kind_key(kind), taken^, allocator)
	taken[id] = true
	node := Graph_Node {
		id     = id,
		kind   = kind,
		name   = strings.clone(name, allocator),
		params = defaults_for(kind),
	}
	append(&p.nodes, node)
	name_key := strings.clone(name, context.temp_allocator)
	name_to_id[name_key] = id
	buf_to_id[strings.concatenate({name, "_buf"}, context.temp_allocator)] = id
	d := Draft {
		id   = id,
		name = name,
		kind = kind,
		ramp = .Exp,
	}
	switch kind {
	case .Filter:
		d.q = 1
	case .Osc, .Noise, .Gain, .Shaper, .Panner, .Out:
	}
	drafts[name_key] = d
	return &drafts[name]
}

@(private)
resolve_sources :: proc(
	arg: string,
	name_to_id: map[string]string,
	buf_to_id: map[string]string,
	mix_ids: map[string][dynamic]string,
	allocator := context.temp_allocator,
) -> []string {
	arg := strip_ref(arg)
	if ids, ok := mix_ids[arg]; ok {
		return ids[:]
	}
	if id, ok := buf_to_id[arg]; ok {
		out := make([]string, 1, allocator)
		out[0] = id
		return out
	}
	stem := buf_stem(arg)
	if id, ok := name_to_id[stem]; ok && id != "out" {
		out := make([]string, 1, allocator)
		out[0] = id
		return out
	}
	return {}
}

@(private)
add_edges :: proc(
	p: ^Patch,
	from_ids: []string,
	to_id: string,
	taken: ^map[string]bool,
	allocator := context.allocator,
) {
	for from_id in from_ids {
		if from_id == "" || to_id == "" || from_id == to_id {
			continue
		}
		dup := false
		for e in p.edges {
			if e.from == from_id && e.to == to_id {
				dup = true
				break
			}
		}
		if dup {
			continue
		}
		edge := Graph_Edge {
			id   = uid("e", taken^, allocator),
			from = strings.clone(from_id, allocator),
			to   = strings.clone(to_id, allocator),
		}
		taken[edge.id] = true
		append(&p.edges, edge)
	}
}

@(private)
apply_num_to_name :: proc(drafts: ^map[string]Draft, lhs: string, n: Num_Expr) -> bool {
	if stem, ok := stem_suffix(lhs, "_f0"); ok {
		if d := draft_ptr(drafts, stem); d != nil {
			d.freq = n.value
			if n.jitter != 0 {
				d.jitter = n.jitter
			}
			return true
		}
	}
	if stem, ok := stem_suffix(lhs, "_f1"); ok {
		if d := draft_ptr(drafts, stem); d != nil {
			d.freq_end = n.value
			d.has_ramp = true
			if n.jitter != 0 {
				d.jitter = n.jitter
			}
			return true
		}
	}
	if stem, ok := stem_suffix(lhs, "_peak"); ok {
		if d := draft_ptr(drafts, stem); d != nil {
			d.peak = n.value
			if n.jitter != 0 {
				d.jitter = n.jitter
			}
			return true
		}
	}
	return false
}

@(private)
apply_assign :: proc(
	p: ^Patch,
	taken: ^map[string]bool,
	name_to_id: ^map[string]string,
	drafts: ^map[string]Draft,
	buf_to_id: ^map[string]string,
	mix_ids: ^map[string][dynamic]string,
	lhs, rhs: string,
	allocator := context.allocator,
) -> bool {
	if n, ok := parse_num(rhs); ok {
		if stem, sok := stem_suffix(lhs, "_peak"); sok {
			d := ensure_node(p, taken, name_to_id, drafts, buf_to_id, .Gain, stem, allocator)
			d.peak = n.value
			if n.jitter != 0 {
				d.jitter = n.jitter
			}
			return true
		}
		apply_num_to_name(drafts, lhs, n)
		return true
	}
	callee, args, cok := parse_call_expr(rhs)
	if !cok {
		return true
	}
	switch callee {
	case "ma.waveform_config_init":
		if stem, ok := stem_suffix(lhs, "_cfg"); ok {
			if d := draft_ptr(drafts, stem); d != nil && len(args) >= 4 {
				d.osc = parse_osc_type(args[3])
			}
		}
	case "ma.noise_config_init":
	case "mix_mono":
		ids := make([dynamic]string, context.temp_allocator)
		for a in args {
			for id in resolve_sources(a, name_to_id^, buf_to_id^, mix_ids^) {
				append(&ids, id)
			}
		}
		mix_ids[strings.clone(lhs, context.temp_allocator)] = ids
	case "downmix":
		if len(args) >= 1 {
			ids := make([dynamic]string, context.temp_allocator)
			for id in resolve_sources(args[0], name_to_id^, buf_to_id^, mix_ids^) {
				append(&ids, id)
			}
			mix_ids[strings.clone(lhs, context.temp_allocator)] = ids
		}
	case "make":
	case:
		_ = p
		_ = taken
		_ = allocator
	}
	return true
}

@(private)
apply_call :: proc(
	p: ^Patch,
	taken: ^map[string]bool,
	name_to_id: ^map[string]string,
	drafts: ^map[string]Draft,
	buf_to_id: ^map[string]string,
	mix_ids: ^map[string][dynamic]string,
	callee: string,
	args: []string,
	allocator := context.allocator,
) -> bool {
	switch callee {
	case "read_waveform_ramp":
		if len(args) < 7 {
			return false
		}
		name := strip_ref(args[0])
		d := draft_ptr(drafts, name)
		if d == nil {
			return false
		}
		if t, ok := parse_num(args[5]); ok {
			d.start = t.value
			d.has_start = true
			d.delay = t.value
		}
		if t, ok := parse_num(args[6]); ok {
			d.stop = t.value
			d.has_stop = true
		}
		if len(args) >= 8 && parse_enum_token(args[7]) == "lin" {
			d.ramp = .Lin
		} else {
			d.ramp = .Exp
		}
		if args[3] != args[4] {
			d.has_ramp = true
		}
	case "read_noise_window":
		if len(args) < 5 {
			return false
		}
		name := strip_ref(args[0])
		d := draft_ptr(drafts, name)
		if d == nil {
			return false
		}
		if t, ok := parse_num(args[3]); ok {
			d.start = t.value
			d.has_start = true
			d.delay = t.value
		}
		if t, ok := parse_num(args[4]); ok {
			d.stop = t.value
			d.has_stop = true
		}
	case "biquad_init_rbj":
		if len(args) < 5 {
			return false
		}
		name := strip_ref(args[0])
		d := draft_ptr(drafts, name)
		if d == nil {
			return false
		}
		d.filter = parse_filter_type(args[2])
		if q, ok := parse_num(args[4]); ok {
			d.q = q.value
		}
	case "biquad_sweep":
		if len(args) < 9 {
			return false
		}
		name := strip_ref(args[0])
		d := draft_ptr(drafts, name)
		if d == nil {
			return false
		}
		d.filter = parse_filter_type(args[4])
		if q, ok := parse_num(args[5]); ok {
			d.q = q.value
		}
		if args[6] != args[7] {
			d.has_ramp = true
		}
		if t, ok := parse_num(args[8]); ok {
			d.ramp_time = t.value
			if t.value > 0 {
				d.has_ramp = true
			}
		}
		from := resolve_sources(args[1], name_to_id^, buf_to_id^, mix_ids^)
		add_edges(p, from, d.id, taken, allocator)
	case "gain_env":
		if len(args) < 6 {
			return false
		}
		name := buf_stem(args[1])
		d := ensure_node(p, taken, name_to_id, drafts, buf_to_id, .Gain, name, allocator)
		if n, ok := parse_num(args[3]); ok {
			d.peak = n.value
			if n.jitter != 0 {
				d.jitter = n.jitter
			}
		}
		if t, ok := parse_num(args[4]); ok {
			d.start = t.value
			d.has_start = true
			d.delay = t.value
		}
		if t, ok := parse_num(args[5]); ok {
			d.stop = t.value
			d.has_stop = true
		}
		from := resolve_sources(args[0], name_to_id^, buf_to_id^, mix_ids^)
		add_edges(p, from, d.id, taken, allocator)
	case "waveshape":
		if len(args) < 3 {
			return false
		}
		name := buf_stem(args[1])
		d := ensure_node(p, taken, name_to_id, drafts, buf_to_id, .Shaper, name, allocator)
		if n, ok := parse_num(args[2]); ok {
			d.amount = n.value
		}
		from := resolve_sources(args[0], name_to_id^, buf_to_id^, mix_ids^)
		add_edges(p, from, d.id, taken, allocator)
	case "pan_to_stereo":
		if len(args) < 3 {
			return false
		}
		name := buf_stem(args[1])
		d := ensure_node(p, taken, name_to_id, drafts, buf_to_id, .Panner, name, allocator)
		if n, ok := parse_num(args[2]); ok {
			d.pan = n.value
		}
		from := resolve_sources(args[0], name_to_id^, buf_to_id^, mix_ids^)
		add_edges(p, from, d.id, taken, allocator)
	case "delay_line":
		if len(args) < 6 {
			return false
		}
		name := buf_stem(args[1])
		d := ensure_node(p, taken, name_to_id, drafts, buf_to_id, .Delay, name, allocator)
		if n, ok := parse_num(args[3]); ok {
			d.time = n.value
		}
		if n, ok := parse_num(args[4]); ok {
			d.mix = n.value
		}
		if n, ok := parse_num(args[5]); ok {
			d.feedback = n.value
		}
		from := resolve_sources(args[0], name_to_id^, buf_to_id^, mix_ids^)
		add_edges(p, from, d.id, taken, allocator)
	case "add_stereo", "add_mono_to_stereo":
		if len(args) < 2 {
			return false
		}
		from := resolve_sources(args[1], name_to_id^, buf_to_id^, mix_ids^)
		add_edges(p, from, "out", taken, allocator)
	case:
	}
	return true
}

@(private)
apply_draft :: proc(node: ^Graph_Node, d: Draft) {
	duration := d.duration
	if d.has_start && d.has_stop {
		duration = max(f32(0.005), d.stop - d.start)
	}
	delay := d.delay
	if d.has_start {
		delay = d.start
	}
	switch node.kind {
	case .Osc:
		freq_end := d.freq_end if d.has_ramp else 0
		node.params = Osc_Params {
			type     = d.osc,
			freq     = d.freq,
			freq_end = freq_end,
			ramp     = d.ramp,
			duration = duration,
			delay    = delay,
			jitter   = d.jitter,
		}
	case .Noise:
		node.params = Noise_Params{duration = duration if duration > 0 else d.duration, delay = delay}
	case .Filter:
		node.params = Filter_Params {
			type      = d.filter,
			freq      = d.freq,
			freq_end  = d.freq_end if d.has_ramp else 0,
			q         = d.q,
			ramp_time = d.ramp_time,
			jitter    = d.jitter,
		}
	case .Gain:
		dur := duration
		if d.has_stop {
			dur = max(f32(0.005), d.stop - delay)
		}
		node.params = Gain_Params{peak = d.peak, duration = dur, delay = delay, jitter = d.jitter}
	case .Shaper:
		node.params = Shaper_Params{amount = d.amount}
	case .Panner:
		node.params = Panner_Params{pan = d.pan}
	case .Delay:
		node.params = Delay_Params{time = d.time, mix = d.mix, feedback = d.feedback}
	case .Out:
	}
}

@(private)
layout_parsed :: proc(p: ^Patch) {
	n := len(p.nodes)
	if n == 0 {
		return
	}
	idx := make(map[string]int, context.temp_allocator)
	for node, i in p.nodes {
		idx[node.id] = i
	}
	rank := make([]int, n, context.temp_allocator)
	for pass in 0 ..< n {
		_ = pass
		changed := false
		for e in p.edges {
			a, aok := idx[e.from]
			b, bok := idx[e.to]
			if aok && bok && rank[a] + 1 > rank[b] {
				rank[b] = rank[a] + 1
				changed = true
			}
		}
		if !changed {
			break
		}
	}
	count_at := make(map[int]int, context.temp_allocator)
	for i in 0 ..< n {
		r := rank[i]
		slot := count_at[r]
		count_at[r] = slot + 1
		p.nodes[i].x = 40 + f32(r) * 200
		p.nodes[i].y = 40 + f32(slot) * 180
	}
}
