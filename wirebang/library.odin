package wirebang

ZAP_NODES := [?]Graph_Node {
	{id = "out", kind = .Out, x = 780, y = 260, name = "out"},
	{id = "noise_1", kind = .Noise, x = 40, y = 40, name = "snap", params = Noise_Params{duration = 0.025, delay = 0}},
	{
		id = "filter_1",
		kind = .Filter,
		x = 240,
		y = 40,
		name = "snapBp",
		params = Filter_Params{type = .Bandpass, freq = 2400, freq_end = 650, q = 1.5, ramp_time = 0.02, jitter = 0.12},
	},
	{id = "shaper_1", kind = .Shaper, x = 440, y = 40, name = "crunch", params = Shaper_Params{amount = 6}},
	{id = "gain_1", kind = .Gain, x = 620, y = 40, name = "snapGain", params = Gain_Params{peak = 0.26, duration = 0.025, delay = 0, jitter = 0.1}},
	{id = "noise_2", kind = .Noise, x = 40, y = 220, name = "crackle", params = Noise_Params{duration = 0.012, delay = 0.003}},
	{
		id = "filter_2",
		kind = .Filter,
		x = 240,
		y = 220,
		name = "air",
		params = Filter_Params{type = .Highpass, freq = 3800, freq_end = 0, q = 0.7, ramp_time = 0, jitter = 0},
	},
	{id = "gain_2", kind = .Gain, x = 440, y = 220, name = "crackleGain", params = Gain_Params{peak = 0.1, duration = 0.012, delay = 0.003, jitter = 0.1}},
	{
		id = "osc_1",
		kind = .Osc,
		x = 40,
		y = 400,
		name = "thump",
		params = Osc_Params{type = .Sine, freq = 150, freq_end = 55, ramp = .Exp, duration = 0.035, delay = 0, jitter = 0.08},
	},
	{id = "gain_3", kind = .Gain, x = 280, y = 400, name = "thumpGain", params = Gain_Params{peak = 0.14, duration = 0.035, delay = 0, jitter = 0.08}},
}

ZAP_EDGES := [?]Graph_Edge {
	{id = "e_1", from = "noise_1", to = "filter_1"},
	{id = "e_2", from = "filter_1", to = "shaper_1"},
	{id = "e_3", from = "shaper_1", to = "gain_1"},
	{id = "e_4", from = "gain_1", to = "out"},
	{id = "e_5", from = "noise_2", to = "filter_2"},
	{id = "e_6", from = "filter_2", to = "gain_2"},
	{id = "e_7", from = "gain_2", to = "out"},
	{id = "e_8", from = "osc_1", to = "gain_3"},
	{id = "e_9", from = "gain_3", to = "out"},
}

THUMP_NODES := [?]Graph_Node {
	{id = "out", kind = .Out, x = 560, y = 160, name = "out"},
	{id = "osc_1", kind = .Osc, x = 60, y = 80, name = "body", params = Osc_Params{type = .Sine, freq = 90, freq_end = 38, ramp = .Exp, duration = 0.12, delay = 0, jitter = 0.05}},
	{id = "gain_1", kind = .Gain, x = 300, y = 80, name = "amp", params = Gain_Params{peak = 0.28, duration = 0.12, delay = 0, jitter = 0.04}},
	{id = "osc_2", kind = .Osc, x = 60, y = 280, name = "click", params = Osc_Params{type = .Triangle, freq = 420, freq_end = 120, ramp = .Exp, duration = 0.018, delay = 0, jitter = 0.1}},
	{id = "gain_2", kind = .Gain, x = 300, y = 280, name = "clickAmp", params = Gain_Params{peak = 0.08, duration = 0.018, delay = 0, jitter = 0.1}},
}

THUMP_EDGES := [?]Graph_Edge {
	{id = "e_1", from = "osc_1", to = "gain_1"},
	{id = "e_2", from = "gain_1", to = "out"},
	{id = "e_3", from = "osc_2", to = "gain_2"},
	{id = "e_4", from = "gain_2", to = "out"},
}

WHOOSH_NODES := [?]Graph_Node {
	{id = "out", kind = .Out, x = 700, y = 180, name = "out"},
	{id = "noise_1", kind = .Noise, x = 40, y = 80, name = "air", params = Noise_Params{duration = 0.28, delay = 0}},
	{id = "filter_1", kind = .Filter, x = 260, y = 80, name = "sweep", params = Filter_Params{type = .Bandpass, freq = 400, freq_end = 2800, q = 2.2, ramp_time = 0.22, jitter = 0.05}},
	{id = "gain_1", kind = .Gain, x = 480, y = 80, name = "body", params = Gain_Params{peak = 0.18, duration = 0.28, delay = 0, jitter = 0.06}},
	{id = "panner_1", kind = .Panner, x = 480, y = 260, name = "move", params = Panner_Params{pan = -0.35}},
}

WHOOSH_EDGES := [?]Graph_Edge {
	{id = "e_1", from = "noise_1", to = "filter_1"},
	{id = "e_2", from = "filter_1", to = "gain_1"},
	{id = "e_3", from = "gain_1", to = "panner_1"},
	{id = "e_4", from = "panner_1", to = "out"},
}

Library_Entry :: struct {
	id:    string,
	label: string,
	patch: proc(allocator := context.allocator) -> Patch,
}

library_zap :: proc(allocator := context.allocator) -> Patch {
	return patch_from_slices("Zap", "play_zap", ZAP_NODES[:], ZAP_EDGES[:], allocator)
}

library_thump :: proc(allocator := context.allocator) -> Patch {
	return patch_from_slices("Thump", "play_thump", THUMP_NODES[:], THUMP_EDGES[:], allocator)
}

library_whoosh :: proc(allocator := context.allocator) -> Patch {
	return patch_from_slices("Whoosh", "play_whoosh", WHOOSH_NODES[:], WHOOSH_EDGES[:], allocator)
}

CLICK_NODES := [?]Graph_Node {
	{id = "out", kind = .Out, x = 700, y = 180, name = "out"},
	{id = "osc_1", kind = .Osc, x = 40, y = 80, name = "tick", params = Osc_Params{type = .Triangle, freq = 2200, freq_end = 900, ramp = .Exp, duration = 0.012, delay = 0, jitter = 0.06}},
	{id = "gain_1", kind = .Gain, x = 260, y = 80, name = "tickAmp", params = Gain_Params{peak = 0.22, duration = 0.012, delay = 0, jitter = 0.05}},
	{id = "noise_1", kind = .Noise, x = 40, y = 260, name = "tickAir", params = Noise_Params{duration = 0.008, delay = 0}},
	{id = "filter_1", kind = .Filter, x = 260, y = 260, name = "tickHp", params = Filter_Params{type = .Highpass, freq = 4200, freq_end = 0, q = 0.7, ramp_time = 0, jitter = 0}},
	{id = "gain_2", kind = .Gain, x = 480, y = 260, name = "tickAirAmp", params = Gain_Params{peak = 0.07, duration = 0.008, delay = 0, jitter = 0.08}},
}

CLICK_EDGES := [?]Graph_Edge {
	{id = "e_1", from = "osc_1", to = "gain_1"},
	{id = "e_2", from = "gain_1", to = "out"},
	{id = "e_3", from = "noise_1", to = "filter_1"},
	{id = "e_4", from = "filter_1", to = "gain_2"},
	{id = "e_5", from = "gain_2", to = "out"},
}

HIT_NODES := [?]Graph_Node {
	{id = "out", kind = .Out, x = 760, y = 260, name = "out"},
	{id = "noise_1", kind = .Noise, x = 40, y = 40, name = "crack", params = Noise_Params{duration = 0.03, delay = 0}},
	{id = "filter_1", kind = .Filter, x = 200, y = 40, name = "crackBp", params = Filter_Params{type = .Bandpass, freq = 1600, freq_end = 380, q = 1.2, ramp_time = 0.025, jitter = 0.1}},
	{id = "shaper_1", kind = .Shaper, x = 380, y = 40, name = "smash", params = Shaper_Params{amount = 8}},
	{id = "gain_1", kind = .Gain, x = 560, y = 40, name = "crackGain", params = Gain_Params{peak = 0.24, duration = 0.03, delay = 0, jitter = 0.08}},
	{id = "osc_1", kind = .Osc, x = 40, y = 220, name = "body", params = Osc_Params{type = .Sine, freq = 140, freq_end = 48, ramp = .Exp, duration = 0.1, delay = 0, jitter = 0.06}},
	{id = "gain_2", kind = .Gain, x = 280, y = 220, name = "bodyGain", params = Gain_Params{peak = 0.32, duration = 0.1, delay = 0, jitter = 0.05}},
	{id = "osc_2", kind = .Osc, x = 40, y = 400, name = "edge", params = Osc_Params{type = .Square, freq = 320, freq_end = 90, ramp = .Exp, duration = 0.022, delay = 0, jitter = 0.1}},
	{id = "gain_3", kind = .Gain, x = 280, y = 400, name = "edgeGain", params = Gain_Params{peak = 0.07, duration = 0.022, delay = 0, jitter = 0.1}},
}

HIT_EDGES := [?]Graph_Edge {
	{id = "e_1", from = "noise_1", to = "filter_1"},
	{id = "e_2", from = "filter_1", to = "shaper_1"},
	{id = "e_3", from = "shaper_1", to = "gain_1"},
	{id = "e_4", from = "gain_1", to = "out"},
	{id = "e_5", from = "osc_1", to = "gain_2"},
	{id = "e_6", from = "gain_2", to = "out"},
	{id = "e_7", from = "osc_2", to = "gain_3"},
	{id = "e_8", from = "gain_3", to = "out"},
}

PICKUP_NODES := [?]Graph_Node {
	{id = "out", kind = .Out, x = 780, y = 260, name = "out"},
	{id = "osc_1", kind = .Osc, x = 40, y = 60, name = "pluck", params = Osc_Params{type = .Triangle, freq = 520, freq_end = 780, ramp = .Lin, duration = 0.06, delay = 0, jitter = 0.04}},
	{id = "gain_1", kind = .Gain, x = 280, y = 60, name = "pluckAmp", params = Gain_Params{peak = 0.20, duration = 0.06, delay = 0, jitter = 0.04}},
	{id = "osc_2", kind = .Osc, x = 40, y = 200, name = "chime", params = Osc_Params{type = .Sine, freq = 880, freq_end = 1320, ramp = .Lin, duration = 0.12, delay = 0.05, jitter = 0.03}},
	{id = "gain_2", kind = .Gain, x = 280, y = 200, name = "chimeAmp", params = Gain_Params{peak = 0.16, duration = 0.12, delay = 0.05, jitter = 0.04}},
	{id = "noise_1", kind = .Noise, x = 40, y = 360, name = "sparkle", params = Noise_Params{duration = 0.04, delay = 0.05}},
	{id = "filter_1", kind = .Filter, x = 260, y = 360, name = "sparkleBp", params = Filter_Params{type = .Bandpass, freq = 5000, freq_end = 7000, q = 3.5, ramp_time = 0.04, jitter = 0.05}},
	{id = "gain_3", kind = .Gain, x = 500, y = 360, name = "sparkleAmp", params = Gain_Params{peak = 0.05, duration = 0.04, delay = 0.05, jitter = 0.08}},
}

PICKUP_EDGES := [?]Graph_Edge {
	{id = "e_1", from = "osc_1", to = "gain_1"},
	{id = "e_2", from = "gain_1", to = "out"},
	{id = "e_3", from = "osc_2", to = "gain_2"},
	{id = "e_4", from = "gain_2", to = "out"},
	{id = "e_5", from = "noise_1", to = "filter_1"},
	{id = "e_6", from = "filter_1", to = "gain_3"},
	{id = "e_7", from = "gain_3", to = "out"},
}

library_click :: proc(allocator := context.allocator) -> Patch {
	return patch_from_slices("Click", "play_click", CLICK_NODES[:], CLICK_EDGES[:], allocator)
}

library_hit :: proc(allocator := context.allocator) -> Patch {
	return patch_from_slices("Hit", "play_hit", HIT_NODES[:], HIT_EDGES[:], allocator)
}

library_pickup :: proc(allocator := context.allocator) -> Patch {
	return patch_from_slices("Pickup", "play_pickup", PICKUP_NODES[:], PICKUP_EDGES[:], allocator)
}

LIBRARY := [?]Library_Entry {
	{id = "zap", label = "Zap", patch = library_zap},
	{id = "thump", label = "Thump", patch = library_thump},
	{id = "whoosh", label = "Whoosh", patch = library_whoosh},
	{id = "click", label = "Click", patch = library_click},
	{id = "hit", label = "Hit", patch = library_hit},
	{id = "pickup", label = "Pickup", patch = library_pickup},
}
