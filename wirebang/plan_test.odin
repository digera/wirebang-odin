package wirebang

import "core:testing"

@(test)
test_zap_plan_order :: proc(t: ^testing.T) {
	p := library_zap()
	defer destroy_patch(&p)
	plan := plan_patch(p)
	defer destroy_plan(&plan)
	testing.expect(t, plan.uses_noise)
	testing.expect(t, plan.uses_shaper)
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
