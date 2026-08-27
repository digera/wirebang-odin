package wirebang

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"

encode_patch :: proc(patch: Patch, allocator := context.allocator) -> []u8 {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n  \"version\": 1,\n  \"name\": %q,\n  \"fnName\": %q,\n  \"nodes\": [\n", patch.name, patch.fn_name)
	for n, i in patch.nodes {
		fmt.sbprintf(&b, "    {{\n      \"id\": %q,\n      \"kind\": %q,\n      \"x\": %g,\n      \"y\": %g,\n      \"name\": %q,\n      \"params\": {{", n.id, kind_key(n.kind), n.x, n.y, n.name)
		write_params_json(&b, n)
		fmt.sbprintf(&b, "}}\n    }}")
		if i + 1 < len(patch.nodes) {
			strings.write_string(&b, ",\n")
		} else {
			strings.write_string(&b, "\n")
		}
	}
	strings.write_string(&b, "  ],\n  \"edges\": [\n")
	for e, i in patch.edges {
		fmt.sbprintf(&b, "    {{\"id\": %q, \"from\": %q, \"to\": %q}}", e.id, e.from, e.to)
		if i + 1 < len(patch.edges) {
			strings.write_string(&b, ",\n")
		} else {
			strings.write_string(&b, "\n")
		}
	}
	strings.write_string(&b, "  ]\n}\n")
	return transmute([]u8)strings.to_string(b)
}

@(private)
write_params_json :: proc(b: ^strings.Builder, node: Graph_Node) {
	first := true
	write :: proc(b: ^strings.Builder, first: ^bool, key: string, fmt_str: string, args: ..any) {
		if !first^ {
			strings.write_string(b, ", ")
		}
		first^ = false
		fmt.sbprintf(b, " %q: ", key)
		fmt.sbprintf(b, fmt_str, ..args)
	}
	switch p in node.params {
	case Osc_Params:
		write(b, &first, "type", "%q", osc_type_key(p.type))
		write(b, &first, "freq", "%g", p.freq)
		write(b, &first, "freqEnd", "%g", p.freq_end)
		write(b, &first, "ramp", "%q", ramp_key(p.ramp))
		write(b, &first, "duration", "%g", p.duration)
		write(b, &first, "delay", "%g", p.delay)
		write(b, &first, "jitter", "%g", p.jitter)
	case Noise_Params:
		write(b, &first, "duration", "%g", p.duration)
		write(b, &first, "delay", "%g", p.delay)
	case Filter_Params:
		write(b, &first, "type", "%q", filter_type_key(p.type))
		write(b, &first, "freq", "%g", p.freq)
		write(b, &first, "freqEnd", "%g", p.freq_end)
		write(b, &first, "q", "%g", p.q)
		write(b, &first, "rampTime", "%g", p.ramp_time)
		write(b, &first, "jitter", "%g", p.jitter)
	case Gain_Params:
		write(b, &first, "peak", "%g", p.peak)
		write(b, &first, "duration", "%g", p.duration)
		write(b, &first, "delay", "%g", p.delay)
		write(b, &first, "jitter", "%g", p.jitter)
	case Shaper_Params:
		write(b, &first, "amount", "%g", p.amount)
	case Panner_Params:
		write(b, &first, "pan", "%g", p.pan)
	case Delay_Params:
		write(b, &first, "time", "%g", p.time)
		write(b, &first, "mix", "%g", p.mix)
		write(b, &first, "feedback", "%g", p.feedback)
	}
	if !first {
		strings.write_byte(b, ' ')
	}
}

@(private)
json_str :: proc(v: json.Value) -> (string, bool) {
	s, ok := v.(json.String)
	return s, ok
}

@(private)
json_f32 :: proc(v: json.Value) -> (f32, bool) {
	switch n in v {
	case json.Float:
		return f32(n), true
	case json.Integer:
		return f32(n), true
	case json.String:
		f, ok := strconv.parse_f32(n)
		return f, ok
	case json.Null, json.Boolean, json.Array, json.Object:
		return 0, false
	}
	return 0, false
}

@(private)
obj_f32 :: proc(obj: json.Object, key: string, fallback: f32) -> f32 {
	if v, ok := obj[key]; ok {
		if f, fok := json_f32(v); fok {
			return f
		}
	}
	return fallback
}

@(private)
obj_str :: proc(obj: json.Object, key: string, fallback: string) -> string {
	if v, ok := obj[key]; ok {
		if s, sok := json_str(v); sok {
			return s
		}
	}
	return fallback
}

decode_patch :: proc(data: []u8, allocator := context.allocator) -> (Patch, bool) {
	val, err := json.parse(data, parse_integers = true, allocator = context.temp_allocator)
	if err != .None {
		return {}, false
	}
	root, rok := val.(json.Object)
	if !rok {
		return {}, false
	}
	if v, vok := root["version"]; vok {
		if n, nok := json_f32(v); nok && n > 1 {
			return {}, false
		}
	}

	p: Patch
	p.name = strings.clone(obj_str(root, "name", "Untitled"), allocator)
	p.fn_name = strings.clone(obj_str(root, "fnName", "play_sound"), allocator)
	p.nodes = make([dynamic]Graph_Node, allocator)
	p.edges = make([dynamic]Graph_Edge, allocator)

	nodes_v, nok := root["nodes"]
	nodes, n_ok := nodes_v.(json.Array)
	if !nok || !n_ok {
		destroy_patch(&p)
		return {}, false
	}
	for nv in nodes {
		obj, ook := nv.(json.Object)
		if !ook {
			destroy_patch(&p)
			return {}, false
		}
		kind, kok := kind_from_key(obj_str(obj, "kind", ""))
		if !kok {
			destroy_patch(&p)
			return {}, false
		}
		node := Graph_Node {
			id   = strings.clone(obj_str(obj, "id", ""), allocator),
			kind = kind,
			x    = obj_f32(obj, "x", 0),
			y    = obj_f32(obj, "y", 0),
			name = strings.clone(obj_str(obj, "name", kind_key(kind)), allocator),
		}
		params := defaults_for(kind)
		if pv, pok := obj["params"]; pok {
			if pobj, pook := pv.(json.Object); pook {
				params = params_from_json(kind, pobj)
			}
		}
		node.params = params
		append(&p.nodes, node)
	}

	if ev, eok := root["edges"]; eok {
		if arr, aok := ev.(json.Array); aok {
			for item in arr {
				obj, ook := item.(json.Object)
				if !ook {
					continue
				}
				append(
					&p.edges,
					Graph_Edge {
						id   = strings.clone(obj_str(obj, "id", ""), allocator),
						from = strings.clone(obj_str(obj, "from", ""), allocator),
						to   = strings.clone(obj_str(obj, "to", ""), allocator),
					},
				)
			}
		}
	}
	if !is_patch(p) {
		destroy_patch(&p)
		return {}, false
	}
	return p, true
}

@(private)
params_from_json :: proc(kind: Node_Kind, obj: json.Object) -> Node_Params {
	d := defaults_for(kind)
	switch kind {
	case .Osc:
		p := d.(Osc_Params)
		if t, ok := osc_type_from_key(obj_str(obj, "type", osc_type_key(p.type))); ok {
			p.type = t
		}
		p.freq = obj_f32(obj, "freq", p.freq)
		p.freq_end = obj_f32(obj, "freqEnd", p.freq_end)
		p.ramp = ramp_from_key(obj_str(obj, "ramp", ramp_key(p.ramp)))
		p.duration = obj_f32(obj, "duration", p.duration)
		p.delay = obj_f32(obj, "delay", p.delay)
		p.jitter = obj_f32(obj, "jitter", p.jitter)
		return p
	case .Noise:
		p := d.(Noise_Params)
		p.duration = obj_f32(obj, "duration", p.duration)
		p.delay = obj_f32(obj, "delay", p.delay)
		return p
	case .Filter:
		p := d.(Filter_Params)
		if t, ok := filter_type_from_key(obj_str(obj, "type", filter_type_key(p.type))); ok {
			p.type = t
		}
		p.freq = obj_f32(obj, "freq", p.freq)
		p.freq_end = obj_f32(obj, "freqEnd", p.freq_end)
		p.q = obj_f32(obj, "q", p.q)
		p.ramp_time = obj_f32(obj, "rampTime", p.ramp_time)
		p.jitter = obj_f32(obj, "jitter", p.jitter)
		return p
	case .Gain:
		p := d.(Gain_Params)
		p.peak = obj_f32(obj, "peak", p.peak)
		p.duration = obj_f32(obj, "duration", p.duration)
		p.delay = obj_f32(obj, "delay", p.delay)
		p.jitter = obj_f32(obj, "jitter", p.jitter)
		return p
	case .Shaper:
		p := d.(Shaper_Params)
		p.amount = obj_f32(obj, "amount", p.amount)
		return p
	case .Panner:
		p := d.(Panner_Params)
		p.pan = obj_f32(obj, "pan", p.pan)
		return p
	case .Delay:
		p := d.(Delay_Params)
		p.time = obj_f32(obj, "time", p.time)
		p.mix = obj_f32(obj, "mix", p.mix)
		p.feedback = obj_f32(obj, "feedback", p.feedback)
		return p
	case .Out:
		return nil
	}
	return nil
}
