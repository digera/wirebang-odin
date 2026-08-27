package wirebang

import "core:os"
import "core:testing"

@(test)
test_json_roundtrip_zap :: proc(t: ^testing.T) {
	p := library_zap()
	defer destroy_patch(&p)
	data := encode_patch(p)
	defer delete(data)
	got, ok := decode_patch(data)
	defer destroy_patch(&got)
	testing.expect(t, ok)
	testing.expect_value(t, got.name, "Zap")
	testing.expect_value(t, len(got.nodes), len(p.nodes))
	testing.expect_value(t, len(got.edges), len(p.edges))
	testing.expect(t, is_patch(got))
	testing.expect(t, strings_contains(string(data), "\"version\": 1"))
}

@(test)
test_generate_code_is_play_proc :: proc(t: ^testing.T) {
	p := library_whoosh()
	defer destroy_patch(&p)
	src := generate_code(p)
	defer delete(src)
	testing.expect(t, strings_contains(src, "play_whoosh"))
	testing.expect(t, strings_contains(src, "vendor:miniaudio"))
	testing.expect(t, strings_contains(src, "ma.noise_config_init"))
	testing.expect(t, strings_contains(src, "ma.biquad"))
	testing.expect(t, !strings_contains(src, "import wb"))
	testing.expect(t, !strings_contains(src, "wb.play"))
	testing.expect(t, !strings_contains(src, "wb.noise"))
	testing.expect(t, !strings_contains(src, "Graph_Node"))
	testing.expect(t, !strings_contains(src, "ZAP_NODES"))
	testing.expect(t, !strings_contains(src, "patch_from_slices"))
}

@(test)
test_parse_sounds_zap_file :: proc(t: ^testing.T) {
	data, err := os.read_entire_file("sounds/zap.odin", context.allocator)
	if err != nil {
		testing.expect(t, false, "sounds/zap.odin missing — run odin run cmd/sync_sounds")
		return
	}
	defer delete(data)
	got, ok := parse_code(string(data))
	defer destroy_patch(&got)
	testing.expect(t, ok)
	testing.expect(t, is_patch(got))
	testing.expect(t, len(got.nodes) > 2)
}

@(test)
test_parse_roundtrip_library :: proc(t: ^testing.T) {
	for entry in LIBRARY {
		p := entry.patch()
		defer destroy_patch(&p)
		src := generate_code(p, {package_name = "sounds"})
		defer delete(src)
		got, ok := parse_code(src)
		defer destroy_patch(&got)
		testing.expectf(t, ok, "%s failed to parse", entry.label)
		if !ok {
			continue
		}
		testing.expect_value(t, len(got.nodes), len(p.nodes))
		testing.expect_value(t, len(got.edges), len(p.edges))
		testing.expect(t, is_patch(got))
		if entry.id == "whoosh" {
			pan_ok := false
			for n in got.nodes {
				if n.kind == .Panner {
					pp := n.params.(Panner_Params)
					pan_ok = abs(pp.pan - (-0.35)) < 0.001
				}
			}
			testing.expect(t, pan_ok, "whoosh panner pan")
		}
	}
}

@(test)
test_delay_codegen_and_parse :: proc(t: ^testing.T) {
	p := empty_patch()
	defer destroy_patch(&p)
	set_owned_string(&p.name, "DelayTest")
	set_owned_string(&p.fn_name, "play_delay_test")
	osc := add_node(&p, .Osc, 10, 10)
	if osc_n := find_node_ptr(&p, osc.id); osc_n != nil {
		osc_n.params = Osc_Params{type = .Sine, freq = 440, freq_end = 220, ramp = .Exp, duration = 0.1, delay = 0, jitter = 0}
	}
	delay := add_node(&p, .Delay, 200, 10)
	if del_n := find_node_ptr(&p, delay.id); del_n != nil {
		del_n.params = Delay_Params{time = 0.15, mix = 0.6, feedback = 0.35}
	}
	connect(&p, osc.id, delay.id)
	connect(&p, delay.id, "out")
	src := generate_code(p, {package_name = "sfx"})
	defer delete(src)
	testing.expect(t, strings_contains(src, "delay_line"))
	testing.expect(t, strings_contains(src, "0.15"))
	testing.expect(t, strings_contains(src, "0.6"))
	testing.expect(t, strings_contains(src, "0.35"))
	got, ok := parse_code(src)
	defer destroy_patch(&got)
	testing.expect(t, ok)
	testing.expect(t, is_patch(got))
	testing.expect_value(t, len(got.nodes), 3)
	testing.expect_value(t, len(got.edges), 2)
	delay_found := false
	for n in got.nodes {
		if n.kind == .Delay {
			dp := n.params.(Delay_Params)
			testing.expect(t, abs(dp.time - 0.15) < 0.001)
			testing.expect(t, abs(dp.mix - 0.6) < 0.001)
			testing.expect(t, abs(dp.feedback - 0.35) < 0.001)
			delay_found = true
		}
	}
	testing.expect(t, delay_found)
}

@(test)
test_delay_voice_produces_tail :: proc(t: ^testing.T) {
	p := empty_patch()
	defer destroy_patch(&p)
	osc := add_node(&p, .Osc, 10, 10)
	if osc_n := find_node_ptr(&p, osc.id); osc_n != nil {
		osc_n.params = Osc_Params{type = .Sine, freq = 440, freq_end = 220, ramp = .Exp, duration = 0.05, delay = 0, jitter = 0}
	}
	delay := add_node(&p, .Delay, 200, 10)
	if del_n := find_node_ptr(&p, delay.id); del_n != nil {
		del_n.params = Delay_Params{time = 0.1, mix = 0.5, feedback = 0.3}
	}
	connect(&p, osc.id, delay.id)
	connect(&p, delay.id, "out")
	plan := plan_patch(p, context.temp_allocator)
	defer destroy_plan(&plan)
	voice := voice_from_plan(plan, DEFAULT_SAMPLE_RATE, context.temp_allocator)
	defer destroy_voice(&voice)
	dry_end_frame := u64(0.05 * DEFAULT_SAMPLE_RATE)
	tail_start_frame := u64(0.15 * DEFAULT_SAMPLE_RATE)
	tail_energy: f32
	for voice.frame < tail_start_frame + 1000 {
		l, r, ok := voice_tick(&voice)
		if !ok {
			break
		}
		if voice.frame > tail_start_frame {
			tail_energy += abs(l) + abs(r)
		}
	}
	testing.expectf(t, tail_energy > 0.01, "expected delay tail energy, got %v", tail_energy)
}

@(private)
strings_contains :: proc(s, sub: string) -> bool {
	if len(sub) == 0 {
		return true
	}
	for i in 0 ..= len(s) - len(sub) {
		if s[i:i + len(sub)] == sub {
			return true
		}
	}
	return false
}
