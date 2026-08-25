package wirebang

import "core:testing"

@(test)
test_zap_plan_order :: proc(t: ^testing.T) {
	p := library_zap()
	defer destroy_patch(&p)
	plan := plan_patch(p)
	defer destroy_plan(&plan)
	want := [?]string{"noise_1", "noise_2", "osc_1", "filter_1", "shaper_1", "gain_1", "filter_2", "gain_2", "gain_3"}
	testing.expect_value(t, len(plan.nodes), len(want))
	for id, i in want {
		if i < len(plan.nodes) {
			testing.expect_value(t, plan.nodes[i].id, id)
		}
	}
}

@(test)
test_zap_air_has_no_freq_ramp :: proc(t: ^testing.T) {
	p := library_zap()
	defer destroy_patch(&p)
	plan := plan_patch(p)
	defer destroy_plan(&plan)
	found := false
	for n in plan.nodes {
		if n.id == "filter_2" {
			found = true
			for a in n.actions {
				testing.expect(t, a.kind != .Ramp)
			}
		}
	}
	testing.expect(t, found, "filter_2 missing from plan")
}

@(test)
test_plan_order_follows_edges :: proc(t: ^testing.T) {
	p := empty_patch()
	defer destroy_patch(&p)
	add_node(&p, .Gain, 300, 10)
	add_node(&p, .Filter, 150, 10)
	add_node(&p, .Osc, 10, 10)

	osc := find_node_ptr(&p, "osc_1")
	testing.expect(t, osc != nil)
	osc.params = Osc_Params{type = .Square, freq = 440, freq_end = 0, ramp = .Lin, duration = 0.04, delay = 0, jitter = 0}
	filt := find_node_ptr(&p, "filter_1")
	testing.expect(t, filt != nil)
	filt.params = Filter_Params{type = .Lowpass, freq = 8000, freq_end = 0, q = 0.7, ramp_time = 0, jitter = 0}
	gain := find_node_ptr(&p, "gain_1")
	testing.expect(t, gain != nil)
	gain.params = Gain_Params{peak = 0.5, duration = 0.04, delay = 0, jitter = 0}

	_, ok1 := connect(&p, "osc_1", "filter_1")
	_, ok2 := connect(&p, "filter_1", "gain_1")
	_, ok3 := connect(&p, "gain_1", "out")
	testing.expect(t, ok1 && ok2 && ok3)

	plan := plan_patch(p)
	defer destroy_plan(&plan)
	index := make(map[string]int, context.temp_allocator)
	for n, i in plan.nodes {
		index[n.id] = i
	}
	testing.expect(t, index["osc_1"] < index["filter_1"])
	testing.expect(t, index["filter_1"] < index["gain_1"])

	pcm := bake(p)
	defer delete(pcm)
	peak: f32
	for s in pcm {
		peak = max(peak, abs(s))
	}
	testing.expectf(t, peak > 0.01, "peak was %v", peak)
	testing.expect(t, abs(pcm[0]) > 1e-6 || abs(pcm[1]) > 1e-6)
}
