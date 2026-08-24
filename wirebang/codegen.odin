package wirebang

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

emit_live :: proc(patch: Patch, allocator := context.allocator) -> string {
	fn := sanitize_fn_name(patch.fn_name if patch.fn_name != "" else patch.name, context.temp_allocator)
	upper, _ := strings.to_upper(fn, context.temp_allocator)
	stem := strings.trim_prefix(fn, "play_")
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "package sfx\n\n")
	fmt.sbprintf(&b, "import wb \"wirebang\"\n")
	fmt.sbprintf(&b, "import ma \"vendor:miniaudio\"\n\n")
	fmt.sbprintf(&b, "%s_NODES := [?]wb.Graph_Node {{\n", upper)
	for n in patch.nodes {
		fmt.sbprintf(&b, "\t{{id = %q, kind = .%v, x = %g, y = %g, name = %q", n.id, n.kind, n.x, n.y, n.name)
		if n.kind != .Out {
			fmt.sbprintf(&b, ", params = ")
			write_params_odin(&b, n)
		}
		fmt.sbprintf(&b, "}},\n")
	}
	fmt.sbprintf(&b, "}}\n\n")
	fmt.sbprintf(&b, "%s_EDGES := [?]wb.Graph_Edge {{\n", upper)
	for e in patch.edges {
		fmt.sbprintf(&b, "\t{{id = %q, from = %q, to = %q}},\n", e.id, e.from, e.to)
	}
	fmt.sbprintf(&b, "}}\n\n")
	fmt.sbprintf(&b, "make_%s :: proc(allocator := context.allocator) -> wb.Patch {{\n", stem)
	fmt.sbprintf(&b, "\treturn wb.patch_from_slices(%q, %q, %s_NODES[:], %s_EDGES[:], allocator)\n", patch.name, fn, upper, upper)
	fmt.sbprintf(&b, "}}\n\n")
	fmt.sbprintf(&b, "%s :: proc(engine: ^ma.engine = nil) {{\n", fn)
	fmt.sbprintf(&b, "\tp := make_%s()\n", stem)
	fmt.sbprintf(&b, "\tdefer wb.destroy_patch(&p)\n")
	fmt.sbprintf(&b, "\tif engine != nil {{\n")
	fmt.sbprintf(&b, "\t\twb.play(engine, p)\n")
	fmt.sbprintf(&b, "\t}} else {{\n")
	fmt.sbprintf(&b, "\t\twb.play(p)\n")
	fmt.sbprintf(&b, "\t}}\n")
	fmt.sbprintf(&b, "}}\n")
	return strings.clone(strings.to_string(b), allocator)
}

emit_baked :: proc(patch: Patch, wav_file: string, allocator := context.allocator) -> string {
	fn := sanitize_fn_name(patch.fn_name if patch.fn_name != "" else patch.name, context.temp_allocator)
	stem := strings.trim_prefix(fn, "play_")
	upper, _ := strings.to_upper(stem, context.temp_allocator)
	json_text := string(encode_patch(patch, context.temp_allocator))
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "package sfx\n\n")
	fmt.sbprintf(&b, "import ma \"vendor:miniaudio\"\n\n")
	fmt.sbprintf(&b, "// Baked one-shot. Play with miniaudio or raylib LoadWaveFromMemory.\n")
	fmt.sbprintf(&b, "%s_WAV := #load(%q)\n\n", upper, wav_file)
	fmt.sbprintf(&b, "// Graph so Wirebang can reopen this sound.\n")
	fmt.sbprintf(&b, "%s_PATCH :: %q\n\n", upper, json_text)
	fmt.sbprintf(&b, "play_%s :: proc(engine: ^ma.engine) {{\n", stem)
	fmt.sbprintf(&b, "\t// Decode %s_WAV with ma.decoder_init_memory and ma.sound_init_from_data_source.\n", upper)
	fmt.sbprintf(&b, "\t_ = engine\n")
	fmt.sbprintf(&b, "}}\n")
	return strings.clone(strings.to_string(b), allocator)
}

write_baked_files :: proc(patch: Patch, dir: string) -> (wav_path, odin_path: string, ok: bool) {
	os.make_directory(dir)
	wav_name := asset_file_name(patch, "wav", context.temp_allocator)
	odin_name := asset_file_name(patch, "odin", context.temp_allocator)
	wav_path, _ = filepath.join({dir, wav_name}, context.temp_allocator)
	odin_path, _ = filepath.join({dir, odin_name}, context.temp_allocator)
	wav := bake_wav(patch)
	defer delete(wav)
	if err := os.write_entire_file(wav_path, wav); err != nil {
		return "", "", false
	}
	src := emit_baked(patch, wav_name)
	defer delete(src)
	if err := os.write_entire_file(odin_path, transmute([]u8)src); err != nil {
		return "", "", false
	}
	return strings.clone(wav_path), strings.clone(odin_path), true
}

write_live_file :: proc(patch: Patch, dir: string) -> (path: string, ok: bool) {
	os.make_directory(dir)
	name := asset_file_name(patch, "odin", context.temp_allocator)
	path, _ = filepath.join({dir, name}, context.temp_allocator)
	src := emit_live(patch)
	defer delete(src)
	if err := os.write_entire_file(path, transmute([]u8)src); err != nil {
		return "", false
	}
	return strings.clone(path), true
}

@(private)
write_params_odin :: proc(b: ^strings.Builder, node: Graph_Node) {
	switch p in node.params {
	case Osc_Params:
		fmt.sbprintf(
			b,
			"wb.Osc_Params{{type = .%v, freq = %g, freq_end = %g, ramp = .%v, duration = %g, delay = %g, jitter = %g}}",
			p.type,
			p.freq,
			p.freq_end,
			p.ramp,
			p.duration,
			p.delay,
			p.jitter,
		)
	case Noise_Params:
		fmt.sbprintf(b, "wb.Noise_Params{{duration = %g, delay = %g}}", p.duration, p.delay)
	case Filter_Params:
		fmt.sbprintf(
			b,
			"wb.Filter_Params{{type = .%v, freq = %g, freq_end = %g, q = %g, ramp_time = %g, jitter = %g}}",
			p.type,
			p.freq,
			p.freq_end,
			p.q,
			p.ramp_time,
			p.jitter,
		)
	case Gain_Params:
		fmt.sbprintf(b, "wb.Gain_Params{{peak = %g, duration = %g, delay = %g, jitter = %g}}", p.peak, p.duration, p.delay, p.jitter)
	case Shaper_Params:
		fmt.sbprintf(b, "wb.Shaper_Params{{amount = %g}}", p.amount)
	case Panner_Params:
		fmt.sbprintf(b, "wb.Panner_Params{{pan = %g}}", p.pan)
	}
}
