package wirebang

import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

Node_Kind :: enum {
	Osc,
	Noise,
	Filter,
	Gain,
	Shaper,
	Panner,
	Out,
}

Osc_Type :: enum {
	Sine,
	Square,
	Sawtooth,
	Triangle,
}

Filter_Type :: enum {
	Lowpass,
	Highpass,
	Bandpass,
	Notch,
}

Ramp_Curve :: enum {
	Exp,
	Lin,
}

Osc_Params :: struct {
	type:     Osc_Type,
	freq:     f32,
	freq_end: f32,
	ramp:     Ramp_Curve,
	duration: f32,
	delay:    f32,
	jitter:   f32,
}

Noise_Params :: struct {
	duration: f32,
	delay:    f32,
}

Filter_Params :: struct {
	type:      Filter_Type,
	freq:      f32,
	freq_end:  f32,
	q:         f32,
	ramp_time: f32,
	jitter:    f32,
}

Gain_Params :: struct {
	peak:     f32,
	duration: f32,
	delay:    f32,
	jitter:   f32,
}

Shaper_Params :: struct {
	amount: f32,
}

Panner_Params :: struct {
	pan: f32,
}

Node_Params :: union {
	Osc_Params,
	Noise_Params,
	Filter_Params,
	Gain_Params,
	Shaper_Params,
	Panner_Params,
}

Graph_Node :: struct {
	id:     string,
	kind:   Node_Kind,
	x, y:   f32,
	name:   string,
	params: Node_Params,
}

Graph_Edge :: struct {
	id:   string,
	from: string,
	to:   string,
}

Patch :: struct {
	name:    string,
	fn_name: string,
	nodes:   [dynamic]Graph_Node,
	edges:   [dynamic]Graph_Edge,
}

Param_Kind :: enum {
	Number,
	Enum,
}

Param_Spec :: struct {
	key:     string,
	label:   string,
	kind:    Param_Kind,
	min:     f32,
	max:     f32,
	step:    f32,
	unit:    string,
	options: []string,
}

OSC_PARAM_SPECS := [?]Param_Spec {
	{key = "type", label = "Wave", kind = .Enum, options = {"sine", "square", "sawtooth", "triangle"}},
	{key = "freq", label = "Freq", kind = .Number, min = 20, max = 8000, step = 1, unit = "Hz"},
	{key = "freqEnd", label = "Freq end", kind = .Number, min = 0, max = 8000, step = 1, unit = "Hz"},
	{key = "ramp", label = "Ramp", kind = .Enum, options = {"exp", "lin"}},
	{key = "duration", label = "Dur", kind = .Number, min = 0.005, max = 2, step = 0.001, unit = "s"},
	{key = "delay", label = "Delay", kind = .Number, min = 0, max = 1, step = 0.001, unit = "s"},
	{key = "jitter", label = "Jitter", kind = .Number, min = 0, max = 0.5, step = 0.01},
}

NOISE_PARAM_SPECS := [?]Param_Spec {
	{key = "duration", label = "Dur", kind = .Number, min = 0.005, max = 2, step = 0.001, unit = "s"},
	{key = "delay", label = "Delay", kind = .Number, min = 0, max = 1, step = 0.001, unit = "s"},
}

FILTER_PARAM_SPECS := [?]Param_Spec {
	{key = "type", label = "Type", kind = .Enum, options = {"lowpass", "highpass", "bandpass", "notch"}},
	{key = "freq", label = "Freq", kind = .Number, min = 40, max = 12000, step = 1, unit = "Hz"},
	{key = "freqEnd", label = "Freq end", kind = .Number, min = 0, max = 12000, step = 1, unit = "Hz"},
	{key = "q", label = "Q", kind = .Number, min = 0.1, max = 18, step = 0.1},
	{key = "rampTime", label = "Ramp", kind = .Number, min = 0, max = 1, step = 0.001, unit = "s"},
	{key = "jitter", label = "Jitter", kind = .Number, min = 0, max = 0.5, step = 0.01},
}

GAIN_PARAM_SPECS := [?]Param_Spec {
	{key = "peak", label = "Peak", kind = .Number, min = 0, max = 1, step = 0.01},
	{key = "duration", label = "Dur", kind = .Number, min = 0.005, max = 2, step = 0.001, unit = "s"},
	{key = "delay", label = "Delay", kind = .Number, min = 0, max = 1, step = 0.001, unit = "s"},
	{key = "jitter", label = "Jitter", kind = .Number, min = 0, max = 0.5, step = 0.01},
}

SHAPER_PARAM_SPECS := [?]Param_Spec {
	{key = "amount", label = "Drive", kind = .Number, min = 0, max = 40, step = 0.5},
}

PANNER_PARAM_SPECS := [?]Param_Spec {
	{key = "pan", label = "Pan", kind = .Number, min = -1, max = 1, step = 0.01},
}

params_for :: proc(kind: Node_Kind) -> []Param_Spec {
	switch kind {
	case .Osc:
		return OSC_PARAM_SPECS[:]
	case .Noise:
		return NOISE_PARAM_SPECS[:]
	case .Filter:
		return FILTER_PARAM_SPECS[:]
	case .Gain:
		return GAIN_PARAM_SPECS[:]
	case .Shaper:
		return SHAPER_PARAM_SPECS[:]
	case .Panner:
		return PANNER_PARAM_SPECS[:]
	case .Out:
		return {}
	}
	return {}
}

defaults_for :: proc(kind: Node_Kind) -> Node_Params {
	switch kind {
	case .Osc:
		return Osc_Params{type = .Sine, freq = 180, freq_end = 60, ramp = .Exp, duration = 0.04, delay = 0, jitter = 0.08}
	case .Noise:
		return Noise_Params{duration = 0.025, delay = 0}
	case .Filter:
		return Filter_Params{type = .Bandpass, freq = 2200, freq_end = 700, q = 1.4, ramp_time = 0.02, jitter = 0.1}
	case .Gain:
		return Gain_Params{peak = 0.2, duration = 0.03, delay = 0, jitter = 0.1}
	case .Shaper:
		return Shaper_Params{amount = 6}
	case .Panner:
		return Panner_Params{pan = 0}
	case .Out:
		return nil
	}
	return nil
}

has_input :: proc(kind: Node_Kind) -> bool {
	return kind != .Osc && kind != .Noise
}

has_output :: proc(kind: Node_Kind) -> bool {
	return kind != .Out
}

kind_label :: proc(kind: Node_Kind) -> string {
	switch kind {
	case .Osc:
		return "Oscillator"
	case .Noise:
		return "Noise"
	case .Filter:
		return "Filter"
	case .Gain:
		return "Gain"
	case .Shaper:
		return "Shaper"
	case .Panner:
		return "Panner"
	case .Out:
		return "Out"
	}
	return "Node"
}

kind_key :: proc(kind: Node_Kind) -> string {
	switch kind {
	case .Osc:
		return "osc"
	case .Noise:
		return "noise"
	case .Filter:
		return "filter"
	case .Gain:
		return "gain"
	case .Shaper:
		return "shaper"
	case .Panner:
		return "panner"
	case .Out:
		return "out"
	}
	return "osc"
}

kind_from_key :: proc(key: string) -> (Node_Kind, bool) {
	switch key {
	case "osc":
		return .Osc, true
	case "noise":
		return .Noise, true
	case "filter":
		return .Filter, true
	case "gain":
		return .Gain, true
	case "shaper":
		return .Shaper, true
	case "panner":
		return .Panner, true
	case "out":
		return .Out, true
	}
	return .Osc, false
}

osc_type_key :: proc(t: Osc_Type) -> string {
	switch t {
	case .Sine:
		return "sine"
	case .Square:
		return "square"
	case .Sawtooth:
		return "sawtooth"
	case .Triangle:
		return "triangle"
	}
	return "sine"
}

osc_type_from_key :: proc(key: string) -> (Osc_Type, bool) {
	switch key {
	case "sine":
		return .Sine, true
	case "square":
		return .Square, true
	case "sawtooth":
		return .Sawtooth, true
	case "triangle":
		return .Triangle, true
	}
	return .Sine, false
}

filter_type_key :: proc(t: Filter_Type) -> string {
	switch t {
	case .Lowpass:
		return "lowpass"
	case .Highpass:
		return "highpass"
	case .Bandpass:
		return "bandpass"
	case .Notch:
		return "notch"
	}
	return "bandpass"
}

filter_type_from_key :: proc(key: string) -> (Filter_Type, bool) {
	switch key {
	case "lowpass":
		return .Lowpass, true
	case "highpass":
		return .Highpass, true
	case "bandpass":
		return .Bandpass, true
	case "notch":
		return .Notch, true
	}
	return .Bandpass, false
}

ramp_key :: proc(c: Ramp_Curve) -> string {
	return c == .Lin ? "lin" : "exp"
}

ramp_from_key :: proc(key: string) -> Ramp_Curve {
	return key == "lin" ? .Lin : .Exp
}

find_node :: proc(patch: Patch, id: string) -> (Graph_Node, int, bool) {
	for n, i in patch.nodes {
		if n.id == id {
			return n, i, true
		}
	}
	return {}, -1, false
}

find_node_ptr :: proc(patch: ^Patch, id: string) -> ^Graph_Node {
	for &n in patch.nodes {
		if n.id == id {
			return &n
		}
	}
	return nil
}

taken_ids :: proc(patch: Patch, allocator := context.allocator) -> map[string]bool {
	taken := make(map[string]bool, allocator)
	for n in patch.nodes {
		taken[n.id] = true
	}
	for e in patch.edges {
		taken[e.id] = true
	}
	return taken
}

uid :: proc(prefix: string, taken: map[string]bool, allocator := context.allocator) -> string {
	for n := 1; ; n += 1 {
		id := fmt.tprintf("%s_%d", prefix, n)
		if id not_in taken {
			return strings.clone(id, allocator)
		}
	}
}

sanitize_fn_name :: proc(name: string, allocator := context.allocator) -> string {
	words := make([dynamic]string, context.temp_allocator)
	buf: [64]u8
	n := 0

	flush :: proc(words: ^[dynamic]string, buf: []u8, n: ^int) {
		if n^ == 0 {
			return
		}
		append(words, strings.clone(string(buf[:n^]), context.temp_allocator))
		n^ = 0
	}

	prev_lower := false
	for r in name {
		if unicode.is_letter(r) || unicode.is_digit(r) {
			if unicode.is_upper(r) && prev_lower && n > 0 {
				flush(&words, buf[:], &n)
			}
			low := unicode.to_lower(r)
			encoded, enc_n := utf8.encode_rune(low)
			if n + enc_n < len(buf) {
				copy(buf[n:], encoded[:enc_n])
				n += enc_n
			}
			prev_lower = unicode.is_lower(r) || unicode.is_digit(r)
		} else {
			flush(&words, buf[:], &n)
			prev_lower = false
		}
	}
	flush(&words, buf[:], &n)

	if len(words) == 0 {
		return strings.clone("play_sound", allocator)
	}

	start := 0
	if words[0] == "play" {
		start = 1
	}
	parts := make([dynamic]string, context.temp_allocator)
	append(&parts, "play")
	for w in words[start:] {
		if len(w) > 0 {
			append(&parts, w)
		}
	}
	return strings.join(parts[:], "_", allocator)
}

set_owned_string :: proc(dst: ^string, value: string, allocator := context.allocator) {
	delete(dst^)
	dst^ = strings.clone(value, allocator)
}

ident :: proc(name, id: string, allocator := context.allocator) -> string {
	base := make([dynamic]u8, context.temp_allocator)
	src := name if name != "" else id
	for r in src {
		if unicode.is_letter(r) || unicode.is_digit(r) {
			low, n := utf8.encode_rune(r)
			append(&base, ..low[:n])
		}
	}
	if len(base) == 0 {
		return strings.clone("n", allocator)
	}
	first := rune(base[0])
	if !unicode.is_letter(first) {
		out := strings.concatenate({"n", string(base[:])}, allocator)
		return out
	}
	base[0] = u8(unicode.to_lower(first))
	return strings.clone(string(base[:]), allocator)
}

empty_patch :: proc(allocator := context.allocator) -> Patch {
	p: Patch
	p.name = strings.clone("Untitled", allocator)
	p.fn_name = strings.clone("play_sound", allocator)
	p.nodes = make([dynamic]Graph_Node, allocator)
	p.edges = make([dynamic]Graph_Edge, allocator)
	append(&p.nodes, Graph_Node{id = strings.clone("out", allocator), kind = .Out, x = 720, y = 220, name = strings.clone("out", allocator)})
	return p
}

destroy_node_strings :: proc(n: Graph_Node) {
	delete(n.id)
	delete(n.name)
}

destroy_edge_strings :: proc(e: Graph_Edge) {
	delete(e.id)
	delete(e.from)
	delete(e.to)
}

destroy_patch :: proc(p: ^Patch) {
	if p == nil {
		return
	}
	delete(p.name)
	delete(p.fn_name)
	for n in p.nodes {
		destroy_node_strings(n)
	}
	for e in p.edges {
		destroy_edge_strings(e)
	}
	delete(p.nodes)
	delete(p.edges)
	p^ = {}
}

clone_patch :: proc(src: Patch, allocator := context.allocator) -> Patch {
	p: Patch
	p.name = strings.clone(src.name, allocator)
	p.fn_name = strings.clone(src.fn_name, allocator)
	p.nodes = make([dynamic]Graph_Node, len(src.nodes), allocator)
	p.edges = make([dynamic]Graph_Edge, len(src.edges), allocator)
	for n, i in src.nodes {
		p.nodes[i] = Graph_Node {
			id     = strings.clone(n.id, allocator),
			kind   = n.kind,
			x      = n.x,
			y      = n.y,
			name   = strings.clone(n.name, allocator),
			params = n.params,
		}
	}
	for e, i in src.edges {
		p.edges[i] = Graph_Edge {
			id   = strings.clone(e.id, allocator),
			from = strings.clone(e.from, allocator),
			to   = strings.clone(e.to, allocator),
		}
	}
	return p
}

patch_from_slices :: proc(name, fn_name: string, nodes: []Graph_Node, edges: []Graph_Edge, allocator := context.allocator) -> Patch {
	p: Patch
	p.name = strings.clone(name, allocator)
	p.fn_name = strings.clone(fn_name, allocator)
	p.nodes = make([dynamic]Graph_Node, len(nodes), allocator)
	p.edges = make([dynamic]Graph_Edge, len(edges), allocator)
	for n, i in nodes {
		p.nodes[i] = Graph_Node {
			id     = strings.clone(n.id, allocator),
			kind   = n.kind,
			x      = n.x,
			y      = n.y,
			name   = strings.clone(n.name, allocator),
			params = n.params,
		}
	}
	for e, i in edges {
		p.edges[i] = Graph_Edge {
			id   = strings.clone(e.id, allocator),
			from = strings.clone(e.from, allocator),
			to   = strings.clone(e.to, allocator),
		}
	}
	return p
}

params_ok :: proc(node: Graph_Node) -> bool {
	switch node.kind {
	case .Osc:
		_, ok := node.params.(Osc_Params)
		return ok
	case .Noise:
		_, ok := node.params.(Noise_Params)
		return ok
	case .Filter:
		_, ok := node.params.(Filter_Params)
		return ok
	case .Gain:
		_, ok := node.params.(Gain_Params)
		return ok
	case .Shaper:
		_, ok := node.params.(Shaper_Params)
		return ok
	case .Panner:
		_, ok := node.params.(Panner_Params)
		return ok
	case .Out:
		return node.params == nil
	}
	return false
}

@(private)
adjacency :: proc(nodes: []Graph_Node, edges: []Graph_Edge, allocator := context.allocator) -> map[string][dynamic]string {
	adj := make(map[string][dynamic]string, allocator)
	for n in nodes {
		adj[n.id] = make([dynamic]string, allocator)
	}
	for e in edges {
		if list, ok := &adj[e.from]; ok {
			append(list, e.to)
		}
	}
	return adj
}

@(private)
graph_has_cycle :: proc(adj: map[string][dynamic]string) -> bool {
	State :: enum {
		None,
		Active,
		Done,
	}
	state := make(map[string]State, context.temp_allocator)
	visit :: proc(id: string, adj: map[string][dynamic]string, state: ^map[string]State) -> bool {
		s := state[id]
		if s == .Active {
			return true
		}
		if s == .Done {
			return false
		}
		state[id] = .Active
		if nexts, ok := adj[id]; ok {
			for next in nexts {
				if visit(next, adj, state) {
					return true
				}
			}
		}
		state[id] = .Done
		return false
	}
	for id in adj {
		if state[id] == .None && visit(id, adj, &state) {
			return true
		}
	}
	return false
}

creates_cycle :: proc(patch: Patch, from, to: string) -> bool {
	if from == to {
		return true
	}
	adj := adjacency(patch.nodes[:], patch.edges[:], context.temp_allocator)
	if list, ok := &adj[from]; ok {
		append(list, to)
	}
	return graph_has_cycle(adj)
}

is_patch :: proc(p: Patch) -> bool {
	if p.name == "" || p.fn_name == "" {
		return false
	}
	ids := make(map[string]bool, context.temp_allocator)
	out_count := 0
	for n in p.nodes {
		if n.id == "" || n.name == "" {
			return false
		}
		if !params_ok(n) {
			return false
		}
		if n.id in ids {
			return false
		}
		ids[n.id] = true
		if n.kind == .Out {
			if n.id != "out" {
				return false
			}
			out_count += 1
		}
	}
	if out_count != 1 || "out" not_in ids {
		return false
	}

	edge_ids := make(map[string]bool, context.temp_allocator)
	for e in p.edges {
		if e.id == "" || e.from == "" || e.to == "" {
			return false
		}
		if e.id in edge_ids || e.from == e.to || e.from not_in ids || e.to not_in ids {
			return false
		}
		edge_ids[e.id] = true
		a, _, aok := find_node(p, e.from)
		b, _, bok := find_node(p, e.to)
		if !aok || !bok || !has_output(a.kind) || !has_input(b.kind) {
			return false
		}
	}
	return !graph_has_cycle(adjacency(p.nodes[:], p.edges[:], context.temp_allocator))
}

asset_file_name :: proc(patch: Patch, ext := "odin", allocator := context.allocator) -> string {
	fn := sanitize_fn_name(patch.fn_name if patch.fn_name != "" else patch.name, context.temp_allocator)
	stem := strings.trim_prefix(fn, "play_")
	if stem == "" || stem == fn {
		stem = "sound"
	}
	return fmt.aprintf("%s.%s", stem, ext, allocator = allocator)
}

add_node :: proc(patch: ^Patch, kind: Node_Kind, x, y: f32, allocator := context.allocator) -> Graph_Node {
	if kind == .Out {
		for n in patch.nodes {
			if n.kind == .Out {
				return n
			}
		}
	}
	taken := taken_ids(patch^, context.temp_allocator)
	id := strings.clone("out", allocator) if kind == .Out else uid(kind_key(kind), taken, allocator)
	node := Graph_Node {
		id     = id,
		kind   = kind,
		x      = x,
		y      = y,
		name   = strings.clone(kind_key(kind), allocator),
		params = defaults_for(kind),
	}
	append(&patch.nodes, node)
	return node
}

remove_node :: proc(patch: ^Patch, id: string) {
	if id == "out" {
		return
	}
	for i := 0; i < len(patch.nodes); i += 1 {
		if patch.nodes[i].id == id {
			destroy_node_strings(patch.nodes[i])
			ordered_remove(&patch.nodes, i)
			break
		}
	}
	for i := len(patch.edges) - 1; i >= 0; i -= 1 {
		e := patch.edges[i]
		if e.from == id || e.to == id {
			destroy_edge_strings(e)
			ordered_remove(&patch.edges, i)
		}
	}
}

connect :: proc(patch: ^Patch, from, to: string, allocator := context.allocator) -> (Graph_Edge, bool) {
	if from == to {
		return {}, false
	}
	a, _, aok := find_node(patch^, from)
	b, _, bok := find_node(patch^, to)
	if !aok || !bok || !has_output(a.kind) || !has_input(b.kind) {
		return {}, false
	}
	for e in patch.edges {
		if e.from == from && e.to == to {
			return {}, false
		}
	}
	if creates_cycle(patch^, from, to) {
		return {}, false
	}
	taken := taken_ids(patch^, context.temp_allocator)
	edge := Graph_Edge {
		id   = uid("e", taken, allocator),
		from = strings.clone(from, allocator),
		to   = strings.clone(to, allocator),
	}
	append(&patch.edges, edge)
	return edge, true
}

disconnect :: proc(patch: ^Patch, edge_id: string) {
	for i := 0; i < len(patch.edges); i += 1 {
		if patch.edges[i].id == edge_id {
			destroy_edge_strings(patch.edges[i])
			ordered_remove(&patch.edges, i)
			return
		}
	}
}

patch_duration :: proc(patch: Patch) -> f32 {
	max_t: f32 = 0.05
	for n in patch.nodes {
		switch p in n.params {
		case Osc_Params:
			max_t = max(max_t, p.delay + max(p.duration, 0.03))
		case Noise_Params:
			max_t = max(max_t, p.delay + max(p.duration, 0.03))
		case Gain_Params:
			max_t = max(max_t, p.delay + max(p.duration, 0.03))
		case Filter_Params:
			max_t = max(max_t, p.ramp_time)
		case Shaper_Params, Panner_Params:
		case:
		}
	}
	return max_t + 0.02
}

param_f32 :: proc(node: Graph_Node, key: string, fallback: f32 = 0) -> f32 {
	switch p in node.params {
	case Osc_Params:
		switch key {
		case "freq":
			return p.freq
		case "freqEnd":
			return p.freq_end
		case "duration":
			return p.duration
		case "delay":
			return p.delay
		case "jitter":
			return p.jitter
		}
	case Noise_Params:
		switch key {
		case "duration":
			return p.duration
		case "delay":
			return p.delay
		}
	case Filter_Params:
		switch key {
		case "freq":
			return p.freq
		case "freqEnd":
			return p.freq_end
		case "q":
			return p.q
		case "rampTime":
			return p.ramp_time
		case "jitter":
			return p.jitter
		}
	case Gain_Params:
		switch key {
		case "peak":
			return p.peak
		case "duration":
			return p.duration
		case "delay":
			return p.delay
		case "jitter":
			return p.jitter
		}
	case Shaper_Params:
		if key == "amount" {
			return p.amount
		}
	case Panner_Params:
		if key == "pan" {
			return p.pan
		}
	}
	return fallback
}

set_param_f32 :: proc(node: ^Graph_Node, key: string, value: f32) {
	switch &p in node.params {
	case Osc_Params:
		switch key {
		case "freq":
			p.freq = value
		case "freqEnd":
			p.freq_end = value
		case "duration":
			p.duration = value
		case "delay":
			p.delay = value
		case "jitter":
			p.jitter = value
		}
	case Noise_Params:
		switch key {
		case "duration":
			p.duration = value
		case "delay":
			p.delay = value
		}
	case Filter_Params:
		switch key {
		case "freq":
			p.freq = value
		case "freqEnd":
			p.freq_end = value
		case "q":
			p.q = value
		case "rampTime":
			p.ramp_time = value
		case "jitter":
			p.jitter = value
		}
	case Gain_Params:
		switch key {
		case "peak":
			p.peak = value
		case "duration":
			p.duration = value
		case "delay":
			p.delay = value
		case "jitter":
			p.jitter = value
		}
	case Shaper_Params:
		if key == "amount" {
			p.amount = value
		}
	case Panner_Params:
		if key == "pan" {
			p.pan = value
		}
	}
}

param_enum :: proc(node: Graph_Node, key: string) -> string {
	switch p in node.params {
	case Osc_Params:
		if key == "type" {
			return osc_type_key(p.type)
		}
		if key == "ramp" {
			return ramp_key(p.ramp)
		}
	case Filter_Params:
		if key == "type" {
			return filter_type_key(p.type)
		}
	case Noise_Params, Gain_Params, Shaper_Params, Panner_Params:
	}
	return ""
}

set_param_enum :: proc(node: ^Graph_Node, key, value: string) {
	switch &p in node.params {
	case Osc_Params:
		if key == "type" {
			if t, ok := osc_type_from_key(value); ok {
				p.type = t
			}
		} else if key == "ramp" {
			p.ramp = ramp_from_key(value)
		}
	case Filter_Params:
		if key == "type" {
			if t, ok := filter_type_from_key(value); ok {
				p.type = t
			}
		}
	case Noise_Params, Gain_Params, Shaper_Params, Panner_Params:
	}
}

node_summary :: proc(node: Graph_Node, allocator := context.allocator) -> string {
	switch p in node.params {
	case Osc_Params:
		return fmt.aprintf("%s %dHz", osc_type_key(p.type), int(p.freq + 0.5), allocator = allocator)
	case Noise_Params:
		return fmt.aprintf("%.3fs", p.duration, allocator = allocator)
	case Filter_Params:
		return fmt.aprintf("%s %dHz", filter_type_key(p.type), int(p.freq + 0.5), allocator = allocator)
	case Gain_Params:
		return fmt.aprintf("peak %.2f", p.peak, allocator = allocator)
	case Shaper_Params:
		return fmt.aprintf("drive %.0f", p.amount, allocator = allocator)
	case Panner_Params:
		return fmt.aprintf("pan %.2f", p.pan, allocator = allocator)
	}
	return strings.clone("destination", allocator)
}
