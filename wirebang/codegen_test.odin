package wirebang

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
}

@(test)
test_emit_live_contains_play :: proc(t: ^testing.T) {
	p := library_whoosh()
	defer destroy_patch(&p)
	src := emit_live(p)
	defer delete(src)
	testing.expect(t, strings_contains(src, "play_whoosh"))
	testing.expect(t, strings_contains(src, "wb.play"))
}

@(test)
test_emit_baked_loads_wav :: proc(t: ^testing.T) {
	p := library_thump()
	defer destroy_patch(&p)
	src := emit_baked(p, "thump.wav")
	defer delete(src)
	testing.expect(t, strings_contains(src, "#load(\"thump.wav\")"))
	testing.expect(t, strings_contains(src, "THUMP_PATCH"))
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
