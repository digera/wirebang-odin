package wirebang

import "core:strings"
import "core:testing"

@(test)
test_sanitize_fn_name :: proc(t: ^testing.T) {
	testing.expect_value(t, sanitize_fn_name("Frost Nova"), "play_frost_nova")
	testing.expect_value(t, sanitize_fn_name("playZap"), "play_zap")
	testing.expect_value(t, sanitize_fn_name("play_zap"), "play_zap")
	testing.expect_value(t, sanitize_fn_name("123 boom"), "play_123_boom")
	testing.expect_value(t, sanitize_fn_name(""), "play_sound")
}

@(test)
test_asset_file_name :: proc(t: ^testing.T) {
	p := empty_patch()
	defer destroy_patch(&p)
	set_owned_string(&p.fn_name, "play_frost_nova")
	testing.expect_value(t, asset_file_name(p), "frost_nova.odin")
	set_owned_string(&p.fn_name, "play_zap")
	testing.expect_value(t, asset_file_name(p), "zap.odin")
	testing.expect_value(t, asset_file_name(p, "wav"), "zap.wav")
}

@(test)
test_is_patch_empty :: proc(t: ^testing.T) {
	p := empty_patch()
	defer destroy_patch(&p)
	testing.expect(t, is_patch(p))
}

@(test)
test_is_patch_rejects_bad :: proc(t: ^testing.T) {
	bad: Patch
	bad.name = "x"
	bad.fn_name = "play_x"
	testing.expect(t, !is_patch(bad))

	dup := empty_patch()
	defer destroy_patch(&dup)
	append(&dup.nodes, Graph_Node{id = strings.clone("out"), kind = .Gain, x = 0, y = 0, name = strings.clone("g"), params = Gain_Params{}})
	testing.expect(t, !is_patch(dup))

	dangling := empty_patch()
	defer destroy_patch(&dangling)
	append(&dangling.edges, Graph_Edge{id = strings.clone("e_1"), from = strings.clone("osc_1"), to = strings.clone("out")})
	testing.expect(t, !is_patch(dangling))
}

@(test)
test_connect_and_cycles :: proc(t: ^testing.T) {
	p := empty_patch()
	defer destroy_patch(&p)
	add_node(&p, .Filter, 10, 10)
	add_node(&p, .Gain, 40, 10)
	_, ok1 := connect(&p, "filter_1", "filter_1")
	testing.expect(t, !ok1)
	_, ok2 := connect(&p, "filter_1", "gain_1")
	testing.expect(t, ok2)
	_, ok3 := connect(&p, "filter_1", "gain_1")
	testing.expect(t, !ok3)
	_, ok4 := connect(&p, "gain_1", "filter_1")
	testing.expect(t, !ok4)
	testing.expect(t, creates_cycle(p, "gain_1", "filter_1"))
	testing.expect(t, is_patch(p))
}

@(test)
test_no_second_out :: proc(t: ^testing.T) {
	p := empty_patch()
	defer destroy_patch(&p)
	again := add_node(&p, .Out, 0, 0)
	testing.expect_value(t, again.id, "out")
	count := 0
	for n in p.nodes {
		if n.kind == .Out {
			count += 1
		}
	}
	testing.expect_value(t, count, 1)
}

@(test)
test_library_patches_valid :: proc(t: ^testing.T) {
	for entry in LIBRARY {
		p := entry.patch()
		defer destroy_patch(&p)
		testing.expectf(t, is_patch(p), "%s should be a valid patch", entry.label)
	}
}
