package wirebang

import "base:runtime"

// Node is a handle into a Ctx being built. i == -1 is Ctx.out.
Node :: struct {
	ctx: ^Ctx,
	i:   int,
}

Ctx :: struct {
	plan:      Plan,
	out:       Node,
	allocator: runtime.Allocator,
}

ctx_init :: proc(ctx: ^Ctx, allocator := context.allocator) {
	ctx.allocator = allocator
	ctx.plan.nodes = make([dynamic]Planned_Node, allocator)
	ctx.plan.edges = make([dynamic]Plan_Edge, allocator)
	ctx.out = Node{ctx = ctx, i = -1}
}

ctx_destroy :: proc(ctx: ^Ctx) {
	if ctx == nil {
		return
	}
	destroy_plan(&ctx.plan)
	ctx^ = {}
}

jitter :: proc(value, amount: f32) -> f32 {
	return jittered(value, amount)
}

safe_exp :: proc(value: f32) -> f32 {
	return max(0.001, value)
}

@(private)
push_node :: proc(ctx: ^Ctx, create: Create_Op) -> Node {
	pn: Planned_Node
	pn.create = create
	pn.actions = make([dynamic]Action, ctx.allocator)
	append(&ctx.plan.nodes, pn)
	return Node{ctx = ctx, i = len(ctx.plan.nodes) - 1}
}

osc :: proc(ctx: ^Ctx, type: Osc_Type) -> Node {
	return push_node(ctx, Create_Op{kind = .Osc, osc = type})
}

noise :: proc(ctx: ^Ctx, duration: f32) -> Node {
	return push_node(ctx, Create_Op{kind = .Noise, duration = max(f32(0.005), duration)})
}

filter :: proc(ctx: ^Ctx, type: Filter_Type, q: f32) -> Node {
	return push_node(ctx, Create_Op{kind = .Filter, filter = type, q = q})
}

gain :: proc(ctx: ^Ctx) -> Node {
	return push_node(ctx, Create_Op{kind = .Gain})
}

shaper :: proc(ctx: ^Ctx, amount: f32) -> Node {
	return push_node(ctx, Create_Op{kind = .Shaper, amount = amount})
}

panner :: proc(ctx: ^Ctx, pan: f32) -> Node {
	return push_node(ctx, Create_Op{kind = .Panner, pan = pan})
}

@(private)
node_ptr :: proc(n: Node) -> ^Planned_Node {
	if n.ctx == nil || n.i < 0 || n.i >= len(n.ctx.plan.nodes) {
		return nil
	}
	return &n.ctx.plan.nodes[n.i]
}

start :: proc(n: Node, time: f32) {
	if p := node_ptr(n); p != nil {
		append(&p.actions, Action{kind = .Start, time = time})
	}
}

stop :: proc(n: Node, time: f32) {
	if p := node_ptr(n); p != nil {
		append(&p.actions, Action{kind = .Stop, time = time})
	}
}

set_freq :: proc(n: Node, value: f32, time: f32) {
	if p := node_ptr(n); p != nil {
		append(&p.actions, Action{kind = .Set, param = .Frequency, value = {value = value}, time = time})
	}
}

ramp_freq :: proc(n: Node, value: f32, time: f32, curve: Ramp_Curve = .Exp) {
	if p := node_ptr(n); p != nil {
		append(&p.actions, Action{kind = .Ramp, param = .Frequency, value = {value = value}, time = time, curve = curve})
	}
}

set_gain :: proc(n: Node, value: f32, time: f32) {
	if p := node_ptr(n); p != nil {
		append(&p.actions, Action{kind = .Set, param = .Gain, value = {value = value}, time = time})
	}
}

ramp_gain :: proc(n: Node, value: f32, time: f32, curve: Ramp_Curve = .Exp) {
	if p := node_ptr(n); p != nil {
		append(&p.actions, Action{kind = .Ramp, param = .Gain, value = {value = value}, time = time, curve = curve})
	}
}

connect_nodes :: proc(from, to: Node) {
	if from.ctx == nil || from.i < 0 {
		return
	}
	append(&from.ctx.plan.edges, Plan_Edge{from = from.i, to = to.i})
}

connect :: proc {
	connect_patch,
	connect_nodes,
}
