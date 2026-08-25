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
