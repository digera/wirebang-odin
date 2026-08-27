package wirebang

import "core:fmt"
import "core:math/rand"
import "core:strings"

Create_Kind :: enum {
	Osc,
	Noise,
	Filter,
	Gain,
	Shaper,
	Panner,
	Delay,
}

Create_Op :: struct {
	kind:     Create_Kind,
	osc:      Osc_Type,
	filter:   Filter_Type,
	duration: f32,
	q:        f32,
	amount:   f32,
	pan:      f32,
	time:     f32,
	mix:      f32,
	feedback: f32,
}

Num_Expr :: struct {
	value:   f32,
	jitter:  f32,
	max_exp: bool,
}

Action_Kind :: enum {
	Set,
	Ramp,
	Start,
	Stop,
}

Param_Id :: enum {
	Frequency,
	Gain,
}

Action :: struct {
	kind:  Action_Kind,
	param: Param_Id,
	value: Num_Expr,
	time:  f32,
	curve: Ramp_Curve,
}

Planned_Node :: struct {
	id:      string,
	node:    Graph_Node,
	create:  Create_Op,
	actions: [dynamic]Action,
}

// to == -1 means the patch output.
Plan_Edge :: struct {
	from: int,
	to:   int,
}

Plan :: struct {
	nodes: [dynamic]Planned_Node,
	edges: [dynamic]Plan_Edge,
}

jittered :: proc(value, jitter: f32) -> f32 {
	if jitter <= 0 {
		return value
	}
	return value * (1 - jitter + rand.float32() * jitter * 2)
}

eval_num :: proc(expr: Num_Expr) -> f32 {
	v := jittered(expr.value, expr.jitter)
	if expr.max_exp {
		v = max(0.001, v)
	}
	return v
}

destroy_plan :: proc(p: ^Plan) {
	if p == nil {
		return
	}
	for &n in p.nodes {
		delete(n.actions)
	}
	delete(p.nodes)
	delete(p.edges)
	p^ = {}
}

@(private)
at_time :: proc(delay: f32) -> f32 {
	return delay if delay > 0 else 0
}

@(private)
plan_node :: proc(node: Graph_Node, allocator := context.allocator) -> (Planned_Node, bool) {
	out: Planned_Node
	out.id = node.id
	out.node = node
	out.actions = make([dynamic]Action, allocator)

	switch node.kind {
	case .Out:
		delete(out.actions)
		return {}, false
	case .Osc:
		p := node.params.(Osc_Params)
		delay := p.delay
		dur := max(f32(0.005), p.duration)
		t0 := at_time(delay)
		t1 := at_time(delay + dur)
		append(&out.actions, Action{kind = .Set, param = .Frequency, value = {value = p.freq, jitter = p.jitter}, time = t0})
		if p.freq_end > 0 && p.freq_end != p.freq {
			end := Num_Expr{value = p.freq_end, jitter = p.jitter, max_exp = p.ramp != .Lin}
			append(&out.actions, Action{kind = .Ramp, param = .Frequency, value = end, time = t1, curve = p.ramp})
		}
		append(&out.actions, Action{kind = .Start, time = t0})
		append(&out.actions, Action{kind = .Stop, time = t1})
		out.create = Create_Op{kind = .Osc, osc = p.type}
		return out, true
	case .Noise:
		p := node.params.(Noise_Params)
		delay := p.delay
		dur := max(f32(0.005), p.duration)
		out.create = Create_Op{kind = .Noise, duration = dur}
		append(&out.actions, Action{kind = .Start, time = at_time(delay)})
		append(&out.actions, Action{kind = .Stop, time = at_time(delay + dur)})
		return out, true
	case .Filter:
		p := node.params.(Filter_Params)
		append(&out.actions, Action{kind = .Set, param = .Frequency, value = {value = p.freq, jitter = p.jitter}, time = 0})
		if p.freq_end > 0 && p.ramp_time > 0 {
			append(
				&out.actions,
				Action {
					kind = .Ramp,
					param = .Frequency,
					value = {value = p.freq_end, jitter = p.jitter, max_exp = true},
					time = p.ramp_time,
					curve = .Exp,
				},
			)
		}
		out.create = Create_Op{kind = .Filter, filter = p.type, q = p.q}
		return out, true
	case .Gain:
		p := node.params.(Gain_Params)
		delay := p.delay
		dur := max(f32(0.005), p.duration)
		out.create = Create_Op{kind = .Gain}
		append(&out.actions, Action{kind = .Set, param = .Gain, value = {value = p.peak, jitter = p.jitter, max_exp = true}, time = at_time(delay)})
		append(&out.actions, Action{kind = .Ramp, param = .Gain, value = {value = 0.001}, time = at_time(delay + dur), curve = .Exp})
		return out, true
	case .Shaper:
		p := node.params.(Shaper_Params)
		out.create = Create_Op{kind = .Shaper, amount = p.amount}
		return out, true
	case .Panner:
		p := node.params.(Panner_Params)
		out.create = Create_Op{kind = .Panner, pan = p.pan}
		return out, true
	case .Delay:
		p := node.params.(Delay_Params)
		out.create = Create_Op{kind = .Delay, time = p.time, mix = p.mix, feedback = p.feedback}
		return out, true
	}
	delete(out.actions)
	return {}, false
}

@(private)
kind_rank :: proc(k: Node_Kind) -> int {
	switch k {
	case .Osc, .Noise:
		return 0
	case .Out:
		return 2
	case .Filter, .Gain, .Shaper, .Panner, .Delay:
		return 1
	}
	return 1
}

plan_patch :: proc(patch: Patch, allocator := context.allocator) -> Plan {
	order := make([]int, len(patch.nodes), context.temp_allocator)
	for i in 0 ..< len(patch.nodes) {
		order[i] = i
	}
	for i in 0 ..< len(order) {
		for j in i + 1 ..< len(order) {
			a := patch.nodes[order[i]]
			b := patch.nodes[order[j]]
			ra := kind_rank(a.kind)
			rb := kind_rank(b.kind)
			if rb < ra || (rb == ra && order[j] < order[i]) {
				order[i], order[j] = order[j], order[i]
			}
		}
	}

	plan: Plan
	plan.nodes = make([dynamic]Planned_Node, allocator)
	plan.edges = make([dynamic]Plan_Edge, allocator)

	known := make(map[string]bool, context.temp_allocator)
	out_ids := make(map[string]bool, context.temp_allocator)
	for idx in order {
		node := patch.nodes[idx]
		if planned, ok := plan_node(node, allocator); ok {
			known[planned.id] = true
			append(&plan.nodes, planned)
		}
	}
	for n in patch.nodes {
		if n.kind == .Out {
			known[n.id] = true
			out_ids[n.id] = true
		}
	}

	string_edges := make([dynamic]Graph_Edge, context.temp_allocator)
	for e in patch.edges {
		if e.from in known && e.to in known {
			append(&string_edges, e)
		}
	}

	sorted := topo_sort_named(plan.nodes[:], string_edges[:], allocator)
	delete(plan.nodes)
	plan.nodes = sorted

	index_of := make(map[string]int, context.temp_allocator)
	for n, i in plan.nodes {
		index_of[n.id] = i
	}
	for e in string_edges {
		fi, fok := index_of[e.from]
		if !fok {
			continue
		}
		if e.to in out_ids {
			append(&plan.edges, Plan_Edge{from = fi, to = -1})
			continue
		}
		ti, tok := index_of[e.to]
		if tok {
			append(&plan.edges, Plan_Edge{from = fi, to = ti})
		}
	}
	return plan
}

// Kahn sort so voice_tick sees inputs before dependents. kind_rank pre-order
// is preserved among ready nodes, so source-then-processor stays the default.
@(private)
topo_sort_named :: proc(nodes: []Planned_Node, edges: []Graph_Edge, allocator := context.allocator) -> [dynamic]Planned_Node {
	n := len(nodes)
	out := make([dynamic]Planned_Node, 0, n, allocator)
	if n == 0 {
		return out
	}

	index_of := make(map[string]int, context.temp_allocator)
	for node, i in nodes {
		index_of[node.id] = i
	}
	indeg := make([]int, n, context.temp_allocator)
	succs := make([][dynamic]int, n, context.temp_allocator)
	for i in 0 ..< n {
		succs[i] = make([dynamic]int, context.temp_allocator)
	}
	for e in edges {
		fi, fok := index_of[e.from]
		ti, tok := index_of[e.to]
		if fok && tok {
			append(&succs[fi], ti)
			indeg[ti] += 1
		}
	}

	used := make([]bool, n, context.temp_allocator)
	for len(out) < n {
		pick := -1
		for i in 0 ..< n {
			if !used[i] && indeg[i] == 0 {
				pick = i
				break
			}
		}
		if pick < 0 {
			for i in 0 ..< n {
				if !used[i] {
					append(&out, nodes[i])
				}
			}
			break
		}
		used[pick] = true
		append(&out, nodes[pick])
		for t in succs[pick] {
			indeg[t] -= 1
		}
	}
	return out
}

plan_duration :: proc(plan: Plan) -> f32 {
	max_t: f32 = 0.05
	for n in plan.nodes {
		if n.create.kind == .Noise {
			max_t = max(max_t, n.create.duration)
		}
		for a in n.actions {
			max_t = max(max_t, a.time)
		}
	}
	return max_t + 0.02
}

// Returns old-indices in tick order (inputs before dependents).
@(private)
topo_order :: proc(plan: Plan, allocator := context.temp_allocator) -> []int {
	n := len(plan.nodes)
	order := make([dynamic]int, 0, n, allocator)
	if n == 0 {
		return order[:]
	}
	indeg := make([]int, n, context.temp_allocator)
	succs := make([][dynamic]int, n, context.temp_allocator)
	for i in 0 ..< n {
		succs[i] = make([dynamic]int, context.temp_allocator)
	}
	for e in plan.edges {
		if e.from < 0 || e.from >= n {
			continue
		}
		if e.to >= 0 && e.to < n {
			append(&succs[e.from], e.to)
			indeg[e.to] += 1
		}
	}
	used := make([]bool, n, context.temp_allocator)
	for len(order) < n {
		pick := -1
		for i in 0 ..< n {
			if !used[i] && indeg[i] == 0 {
				pick = i
				break
			}
		}
		if pick < 0 {
			for i in 0 ..< n {
				if !used[i] {
					append(&order, i)
				}
			}
			break
		}
		used[pick] = true
		append(&order, pick)
		for t in succs[pick] {
			indeg[t] -= 1
		}
	}
	return order[:]
}

var_name :: proc(node: Graph_Node, used: ^map[string]bool, allocator := context.allocator) -> string {
	base := ident(node.name, node.id, context.temp_allocator)
	if base not_in used^ {
		used[base] = true
		return strings.clone(base, allocator)
	}
	for i := 2; ; i += 1 {
		name := fmt.tprintf("%s%d", base, i)
		if name not_in used^ {
			used[name] = true
			return strings.clone(name, allocator)
		}
	}
}
