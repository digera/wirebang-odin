package wirebang

import "core:strconv"
import "core:strings"
import "core:unicode"

parse_code :: proc(src: string, allocator := context.allocator) -> (Patch, bool) {
	body, body_ok := extract_build_body(src)
	if !body_ok {
		return {}, false
	}

	p := empty_patch(allocator)
	delete(p.name)
	delete(p.fn_name)
	fn := extract_fn_name(src)
	p.fn_name = strings.clone(fn, allocator)
	stem := strings.trim_prefix(fn, "play_")
	if stem == "" || stem == fn {
		stem = "sound"
	}
	p.name = strings.clone(title_stem(stem, context.temp_allocator), allocator)

	taken := taken_ids(p, context.temp_allocator)
	name_to_id := make(map[string]string, context.temp_allocator)
	name_to_id["out"] = "out"
	drafts := make(map[string]Draft, context.temp_allocator)

	lines := strings.split_lines(body, context.temp_allocator)
	for raw in lines {
		line := strip_comment(strings.trim_space(raw))
		if line == "" {
			continue
		}
		if lhs, callee, args, ok := parse_assign(line); ok {
			kind, kok := callee_kind(callee)
			if !kok {
				destroy_patch(&p)
				return {}, false
			}
			id := uid(kind_key(kind), taken, allocator)
			taken[id] = true
			node := Graph_Node {
				id     = id,
				kind   = kind,
				name   = strings.clone(lhs, allocator),
				params = defaults_for(kind),
			}
			d := draft_from_create(kind, args)
			d.id = id
			d.name = lhs
			d.kind = kind
			apply_create_params(&node, d)
			append(&p.nodes, node)
			name_to_id[strings.clone(lhs, context.temp_allocator)] = id
			drafts[lhs] = d
			continue
		}
		if callee, args, ok := parse_call(line); ok {
			if !apply_call(&p, &drafts, name_to_id, callee, args, allocator) {
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
	i := strings.index(src, ":: proc")
	if i <= 0 {
		return "play_sound"
	}
	j := i - 1
	for j >= 0 && is_ident_byte(src[j]) {
		j -= 1
	}
	name := strings.trim_space(src[j + 1:i])
	if name == "" {
		return "play_sound"
	}
	return name
}

@(private)
is_ident_byte :: proc(b: u8) -> bool {
	return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_'
}

@(private)
extract_build_body :: proc(src: string) -> (string, bool) {
	marker := "proc(ctx:"
	i := strings.index(src, marker)
	if i < 0 {
		i = strings.index(src, "proc(ctx :")
	}
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
split_args :: proc(s: string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	start := 0
	depth := 0
	for i in 0 ..< len(s) {
		c := s[i]
		switch c {
		case '(':
			depth += 1
		case ')':
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
parse_assign :: proc(line: string) -> (lhs, callee: string, args: []string, ok: bool) {
	eq := strings.index(line, ":=")
	if eq < 0 {
		return
	}
	lhs = strings.trim_space(line[:eq])
	rhs := strings.trim_space(line[eq + 2:])
	paren := strings.index_byte(rhs, '(')
	if paren < 0 || !strings.has_suffix(rhs, ")") {
		return
	}
	callee = strings.trim_space(rhs[:paren])
	args = split_args(rhs[paren + 1:len(rhs) - 1])
	ok = lhs != "" && callee != ""
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
callee_kind :: proc(callee: string) -> (Node_Kind, bool) {
	switch callee {
	case "wb.osc":
		return .Osc, true
	case "wb.noise":
		return .Noise, true
	case "wb.filter":
		return .Filter, true
	case "wb.gain":
		return .Gain, true
	case "wb.shaper":
		return .Shaper, true
	case "wb.panner":
		return .Panner, true
	}
	return .Osc, false
}

@(private)
parse_num :: proc(s: string) -> (Num_Expr, bool) {
	s := strings.trim_space(s)
	if strings.has_prefix(s, "wb.safe_exp(") && strings.has_suffix(s, ")") {
		inner, ok := parse_num(s[len("wb.safe_exp("):len(s) - 1])
		inner.max_exp = true
		return inner, ok
	}
	if strings.has_prefix(s, "wb.jitter(") && strings.has_suffix(s, ")") {
		args := split_args(s[len("wb.jitter("):len(s) - 1])
		if len(args) != 2 {
			return {}, false
		}
		a, aok := strconv.parse_f32(strings.trim_space(args[0]))
		b, bok := strconv.parse_f32(strings.trim_space(args[1]))
		return Num_Expr{value = a, jitter = b}, aok && bok
	}
	v, ok := strconv.parse_f32(s)
	return Num_Expr{value = v}, ok
}

@(private)
parse_enum_token :: proc(s: string) -> string {
	s := strings.trim_space(s)
	return strings.trim_prefix(s, ".")
}

@(private)
draft_from_create :: proc(kind: Node_Kind, args: []string) -> Draft {
	d: Draft
	d.kind = kind
	d.ramp = .Exp
	switch kind {
	case .Osc:
		if len(args) >= 2 {
			switch parse_enum_token(args[1]) {
			case "Sine":
				d.osc = .Sine
			case "Square":
				d.osc = .Square
			case "Sawtooth":
				d.osc = .Sawtooth
			case "Triangle":
				d.osc = .Triangle
			}
		}
	case .Noise:
		if len(args) >= 2 {
			if n, ok := parse_num(args[1]); ok {
				d.duration = n.value
			}
		}
	case .Filter:
		if len(args) >= 2 {
			switch parse_enum_token(args[1]) {
			case "Lowpass":
				d.filter = .Lowpass
			case "Highpass":
				d.filter = .Highpass
			case "Bandpass":
				d.filter = .Bandpass
			case "Notch":
				d.filter = .Notch
			}
		}
		if len(args) >= 3 {
			if n, ok := parse_num(args[2]); ok {
				d.q = n.value
			}
		}
	case .Shaper:
		if len(args) >= 2 {
			if n, ok := parse_num(args[1]); ok {
				d.amount = n.value
			}
		}
	case .Panner:
		if len(args) >= 2 {
			if n, ok := parse_num(args[1]); ok {
				d.pan = n.value
			}
		}
	case .Gain, .Out:
	}
	return d
}

@(private)
apply_create_params :: proc(node: ^Graph_Node, d: Draft) {
	switch node.kind {
	case .Osc:
		node.params = Osc_Params{type = d.osc}
	case .Noise:
		node.params = Noise_Params{duration = d.duration}
	case .Filter:
		node.params = Filter_Params{type = d.filter, q = d.q}
	case .Gain:
		node.params = Gain_Params{}
	case .Shaper:
		node.params = Shaper_Params{amount = d.amount}
	case .Panner:
		node.params = Panner_Params{pan = d.pan}
	case .Out:
	}
}

@(private)
apply_call :: proc(
	p: ^Patch,
	drafts: ^map[string]Draft,
	name_to_id: map[string]string,
	callee: string,
	args: []string,
	allocator := context.allocator,
) -> bool {
	if len(args) == 0 {
		return true
	}
	name := strings.trim_space(args[0])
	switch callee {
	case "wb.start":
		if len(args) < 2 {
			return false
		}
		d, ok := &drafts[name]
		if !ok {
			return false
		}
		n, nok := parse_num(args[1])
		if !nok {
			return false
		}
		d.start = n.value
		d.has_start = true
		d.delay = n.value
	case "wb.stop":
		if len(args) < 2 {
			return false
		}
		d, ok := &drafts[name]
		if !ok {
			return false
		}
		n, nok := parse_num(args[1])
		if !nok {
			return false
		}
		d.stop = n.value
		d.has_stop = true
	case "wb.set_freq":
		if len(args) < 3 {
			return false
		}
		d, ok := &drafts[name]
		if !ok {
			return false
		}
		n, nok := parse_num(args[1])
		if !nok {
			return false
		}
		d.freq = n.value
		if n.jitter != 0 {
			d.jitter = n.jitter
		}
	case "wb.ramp_freq":
		if len(args) < 3 {
			return false
		}
		d, ok := &drafts[name]
		if !ok {
			return false
		}
		n, nok := parse_num(args[1])
		if !nok {
			return false
		}
		d.freq_end = n.value
		d.has_ramp = true
		t, tok := parse_num(args[2])
		if !tok {
			return false
		}
		if d.kind == .Filter {
			d.ramp_time = t.value
		}
		if n.jitter != 0 {
			d.jitter = n.jitter
		}
		if len(args) >= 4 && parse_enum_token(args[3]) == "Lin" {
			d.ramp = .Lin
		} else {
			d.ramp = .Exp
		}
	case "wb.set_gain":
		if len(args) < 3 {
			return false
		}
		d, ok := &drafts[name]
		if !ok {
			return false
		}
		n, nok := parse_num(args[1])
		if !nok {
			return false
		}
		d.peak = n.value
		if n.jitter != 0 {
			d.jitter = n.jitter
		}
		t, tok := parse_num(args[2])
		if tok {
			d.delay = t.value
		}
	case "wb.ramp_gain":
		if len(args) < 3 {
			return false
		}
		d, ok := &drafts[name]
		if !ok {
			return false
		}
		t, tok := parse_num(args[2])
		if !tok {
			return false
		}
		d.stop = t.value
		d.has_stop = true
	case "wb.connect":
		if len(args) < 2 {
			return false
		}
		from_name := name
		to_raw := strings.trim_space(args[1])
		from_id, fok := name_to_id[from_name]
		if !fok {
			return false
		}
		to_id: string
		if to_raw == "ctx.out" {
			to_id = "out"
		} else {
			ok := false
			to_id, ok = name_to_id[to_raw]
			if !ok {
				return false
			}
		}
		taken := taken_ids(p^, context.temp_allocator)
		edge := Graph_Edge {
			id   = uid("e", taken, allocator),
			from = strings.clone(from_id, allocator),
			to   = strings.clone(to_id, allocator),
		}
		append(&p.edges, edge)
	case:
		return true
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
