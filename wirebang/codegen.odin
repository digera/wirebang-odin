package wirebang

import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"

Emit_Options :: struct {
	package_name: string,
	import_path:  string,
}

generate_code :: proc(patch: Patch, opts := Emit_Options{}, allocator := context.allocator) -> string {
	pkg := opts.package_name if opts.package_name != "" else "sfx"
	imp := opts.import_path if opts.import_path != "" else "wirebang"
	fn := sanitize_fn_name(patch.fn_name if patch.fn_name != "" else patch.name, context.temp_allocator)
	plan := plan_patch(patch, context.temp_allocator)

	used := make(map[string]bool, context.temp_allocator)
	used["ctx"] = true
	used["engine"] = true
	used["out"] = true
	names := make([]string, len(plan.nodes), context.temp_allocator)
	for n, i in plan.nodes {
		names[i] = var_name(n.node, &used, context.temp_allocator)
	}

	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "package %s\n\n", pkg)
	fmt.sbprintf(&b, "import wb %q\n\n", imp)
	fmt.sbprintf(&b, "%s :: proc(engine: ^wb.Engine = nil) {{\n", fn)
	fmt.sbprintf(&b, "\twb.play(engine, proc(ctx: ^wb.Ctx) {{\n")

	for n, i in plan.nodes {
		name := names[i]
		switch n.create.kind {
		case .Osc:
			fmt.sbprintf(&b, "\t\t%s := wb.osc(ctx, .%v)\n", name, n.create.osc)
		case .Noise:
			fmt.sbprintf(&b, "\t\t%s := wb.noise(ctx, %s)\n", name, fmt_f32(n.create.duration))
		case .Filter:
			fmt.sbprintf(&b, "\t\t%s := wb.filter(ctx, .%v, %s)\n", name, n.create.filter, fmt_f32(n.create.q))
		case .Gain:
			fmt.sbprintf(&b, "\t\t%s := wb.gain(ctx)\n", name)
		case .Shaper:
			fmt.sbprintf(&b, "\t\t%s := wb.shaper(ctx, %s)\n", name, fmt_f32(n.create.amount))
		case .Panner:
			fmt.sbprintf(&b, "\t\t%s := wb.panner(ctx, %s)\n", name, fmt_f32(n.create.pan))
		}
		for a in n.actions {
			switch a.kind {
			case .Set:
				if a.param == .Frequency {
					fmt.sbprintf(&b, "\t\twb.set_freq(%s, %s, %s)\n", name, emit_num_expr(a.value), fmt_f32(a.time))
				} else {
					fmt.sbprintf(&b, "\t\twb.set_gain(%s, %s, %s)\n", name, emit_num_expr(a.value), fmt_f32(a.time))
				}
			case .Ramp:
				curve := a.curve == .Lin ? ".Lin" : ".Exp"
				if a.param == .Frequency {
					fmt.sbprintf(&b, "\t\twb.ramp_freq(%s, %s, %s, %s)\n", name, emit_num_expr(a.value), fmt_f32(a.time), curve)
				} else {
					fmt.sbprintf(&b, "\t\twb.ramp_gain(%s, %s, %s, %s)\n", name, emit_num_expr(a.value), fmt_f32(a.time), curve)
				}
			case .Start:
				fmt.sbprintf(&b, "\t\twb.start(%s, %s)\n", name, fmt_f32(a.time))
			case .Stop:
				fmt.sbprintf(&b, "\t\twb.stop(%s, %s)\n", name, fmt_f32(a.time))
			}
		}
		strings.write_string(&b, "\n")
	}

	for e in plan.edges {
		if e.from < 0 || e.from >= len(names) {
			continue
		}
		from := names[e.from]
		if e.to < 0 {
			fmt.sbprintf(&b, "\t\twb.connect(%s, ctx.out)\n", from)
		} else if e.to < len(names) {
			fmt.sbprintf(&b, "\t\twb.connect(%s, %s)\n", from, names[e.to])
		}
	}

	fmt.sbprintf(&b, "\t}})\n")
	fmt.sbprintf(&b, "}}\n")
	return strings.to_string(b)
}

@(private)
fmt_f32 :: proc(v: f32) -> string {
	r := math.round(f64(v) * 1_000_000) / 1_000_000
	if r == 0 {
		return "0"
	}
	return fmt.tprintf("%g", f32(r))
}

@(private)
emit_num_expr :: proc(expr: Num_Expr) -> string {
	inner: string
	if expr.jitter > 0 {
		inner = fmt.tprintf("wb.jitter(%s, %s)", fmt_f32(expr.value), fmt_f32(expr.jitter))
	} else {
		inner = fmt_f32(expr.value)
	}
	if expr.max_exp {
		return fmt.tprintf("wb.safe_exp(%s)", inner)
	}
	return inner
}

write_live_file :: proc(patch: Patch, dir: string) -> (path: string, ok: bool) {
	os.make_directory(dir)
	name := asset_file_name(patch, "odin", context.temp_allocator)
	path, _ = filepath.join({dir, name}, context.temp_allocator)
	src := generate_code(patch)
	defer delete(src)
	if err := os.write_entire_file(path, transmute([]u8)src); err != nil {
		return "", false
	}
	return strings.clone(path), true
}

write_baked_wav :: proc(patch: Patch, dir: string) -> (path: string, ok: bool) {
	os.make_directory(dir)
	wav_name := asset_file_name(patch, "wav", context.temp_allocator)
	path, _ = filepath.join({dir, wav_name}, context.temp_allocator)
	wav := bake_wav(patch)
	defer delete(wav)
	if err := os.write_entire_file(path, wav); err != nil {
		return "", false
	}
	return strings.clone(path), true
}
