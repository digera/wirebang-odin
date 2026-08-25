package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:strings"
import rl "vendor:raylib"
import wb "../../wirebang"

BAR_H :: 58
PAL_W :: 168
SIDE_W :: 420
NODE_W :: 168
NODE_H :: 64
JACK :: 12
PERSIST_PATH :: "wirebang-patch.json"
EXPORT_DIR :: "export"

BG :: rl.Color{9, 11, 16, 255}
PANEL :: rl.Color{16, 20, 28, 255}
PANEL2 :: rl.Color{22, 27, 38, 255}
LINE :: rl.Color{40, 50, 64, 255}
TEXT :: rl.Color{215, 224, 236, 255}
MUTED :: rl.Color{139, 154, 175, 255}
ACCENT :: rl.Color{126, 182, 255, 255}

kind_color :: proc(kind: wb.Node_Kind) -> rl.Color {
	switch kind {
	case .Osc:
		return {126, 182, 255, 255}
	case .Noise:
		return {224, 179, 106, 255}
	case .Filter:
		return {143, 212, 184, 255}
	case .Gain:
		return {215, 161, 255, 255}
	case .Shaper:
		return {255, 143, 122, 255}
	case .Panner:
		return {154, 208, 255, 255}
	case .Out:
		return {201, 211, 224, 255}
	}
	return ACCENT
}

App :: struct {
	patch:          wb.Patch,
	selected:       string,
	cable_from:     string,
	dragging:       bool,
	drag_id:        string,
	drag_dx:        f32,
	drag_dy:        f32,
	knob_key:       string,
	knob_start_y:   f32,
	knob_start_v:   f32,
	name_buf:       [128]u8,
	fn_buf:         [128]u8,
	node_name_buf:  [128]u8,
	name_edit:      bool,
	fn_edit:        bool,
	node_name_edit: bool,
	library_i:      i32,
	status:         string,
	code:           string,
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1400, 820, "Wirebang")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	if !wb.init() {
		fmt.eprintln("miniaudio init failed")
		return
	}
	defer wb.shutdown()

	app: App
	if data, err := os.read_entire_file(PERSIST_PATH, context.allocator); err == nil {
		if p, pok := wb.decode_patch(data); pok {
			app.patch = p
		} else {
			app.patch = wb.empty_patch()
		}
		delete(data)
	} else {
		app.patch = wb.empty_patch()
	}
	app.selected = "out"
	sync_name_bufs(&app)
	refresh_code(&app)

	for !rl.WindowShouldClose() {
		wb.reap()
		update(&app)
		rl.BeginDrawing()
		rl.ClearBackground(BG)
		draw(&app)
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
	persist(&app)
	wb.destroy_patch(&app.patch)
}

sync_name_bufs :: proc(app: ^App) {
	write_cstr(app.name_buf[:], app.patch.name)
	write_cstr(app.fn_buf[:], app.patch.fn_name)
	if n := wb.find_node_ptr(&app.patch, app.selected); n != nil {
		write_cstr(app.node_name_buf[:], n.name)
	}
}

write_cstr :: proc(buf: []u8, s: string) {
	n := min(len(s), len(buf) - 1)
	copy(buf, s[:n])
	for i in n ..< len(buf) {
		buf[i] = 0
	}
}

cstr :: proc(buf: []u8) -> cstring {
	return cstring(raw_data(buf))
}

persist :: proc(app: ^App) {
	data := wb.encode_patch(app.patch)
	defer delete(data)
	_ = os.write_entire_file(PERSIST_PATH, data)
}

refresh_code :: proc(app: ^App) {
	if app.code != "" {
		delete(app.code)
	}
	app.code = wb.generate_code(app.patch)
}

set_status :: proc(app: ^App, s: string) {
	if app.status != "" {
		delete(app.status)
	}
	app.status = strings.clone(s)
}

board_rect :: proc() -> rl.Rectangle {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())
	return {PAL_W, BAR_H, w - PAL_W - SIDE_W, h - BAR_H}
}

node_rect :: proc(n: wb.Graph_Node) -> rl.Rectangle {
	return {n.x, n.y, NODE_W, NODE_H}
}

jack_pos :: proc(n: wb.Graph_Node, side: string) -> rl.Vector2 {
	if side == "in" {
		return {n.x + 10, n.y + 16}
	}
	return {n.x + NODE_W - 10, n.y + 16}
}

over_ui :: proc(mouse: rl.Vector2) -> bool {
	w := f32(rl.GetScreenWidth())
	if mouse.y < BAR_H {
		return true
	}
	if mouse.x < PAL_W {
		return true
	}
	if mouse.x > w - SIDE_W {
		return true
	}
	return false
}

update :: proc(app: ^App) {
	mouse := rl.GetMousePosition()
	board := board_rect()
	local := rl.Vector2{mouse.x - board.x, mouse.y - board.y}

	if rl.IsKeyPressed(.SPACE) && !app.name_edit && !app.fn_edit && !app.node_name_edit {
		wb.play(app.patch)
		set_status(app, "Playing")
	}
	if (rl.IsKeyPressed(.DELETE) || rl.IsKeyPressed(.BACKSPACE)) &&
	   !app.name_edit &&
	   !app.fn_edit &&
	   !app.node_name_edit {
		if app.selected != "" && app.selected != "out" {
			wb.remove_node(&app.patch, app.selected)
			app.selected = ""
			persist(app)
			refresh_code(app)
		}
	}
	if rl.IsKeyPressed(.ESCAPE) {
		app.cable_from = ""
	}

	if app.knob_key != "" {
		if rl.IsMouseButtonDown(.LEFT) {
			n := wb.find_node_ptr(&app.patch, app.selected)
			if n != nil {
				spec := spec_for(n^, app.knob_key)
				span := spec.max - spec.min
				fine: f32 = 0.15 if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) else 1
				next := app.knob_start_v + ((app.knob_start_y - mouse.y) * fine / 110) * span
				next = clamp(next, spec.min, spec.max)
				if spec.step > 0 {
					next = math.round(next / spec.step) * spec.step
				}
				wb.set_param_f32(n, app.knob_key, next)
				refresh_code(app)
			}
		} else {
			app.knob_key = ""
			persist(app)
		}
		return
	}

	if app.dragging {
		if rl.IsMouseButtonDown(.LEFT) {
			n := wb.find_node_ptr(&app.patch, app.drag_id)
			if n != nil {
				n.x = max(8, local.x - app.drag_dx)
				n.y = max(8, local.y - app.drag_dy)
			}
		} else {
			app.dragging = false
			persist(app)
		}
		return
	}

	if rl.IsMouseButtonPressed(.LEFT) && !over_ui(mouse) {
		handled := false
		for n in app.patch.nodes {
			if wb.has_output(n.kind) {
				p := jack_pos(n, "out")
				if rl.CheckCollisionPointCircle(local, p, JACK) {
					app.cable_from = n.id
					handled = true
					break
				}
			}
			if wb.has_input(n.kind) {
				p := jack_pos(n, "in")
				if rl.CheckCollisionPointCircle(local, p, JACK) {
					if app.cable_from != "" {
						wb.connect(&app.patch, app.cable_from, n.id)
						app.cable_from = ""
						persist(app)
						refresh_code(app)
					}
					handled = true
					break
				}
			}
		}
		if !handled {
			for e in app.patch.edges {
				a, _, aok := wb.find_node(app.patch, e.from)
				b, _, bok := wb.find_node(app.patch, e.to)
				if aok && bok && cable_hit(jack_pos(a, "out"), jack_pos(b, "in"), local) {
					if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsMouseButtonDown(.RIGHT) {
						wb.disconnect(&app.patch, e.id)
						persist(app)
						refresh_code(app)
						handled = true
						break
					}
				}
			}
		}
		if !handled {
			app.selected = ""
			for n in app.patch.nodes {
				if rl.CheckCollisionPointRec(local, node_rect(n)) {
					app.selected = n.id
					app.dragging = true
					app.drag_id = n.id
					app.drag_dx = local.x - n.x
					app.drag_dy = local.y - n.y
					sync_name_bufs(app)
					break
				}
			}
		}
	}

	if rl.IsMouseButtonPressed(.RIGHT) && !over_ui(mouse) {
		for e in app.patch.edges {
			a, _, aok := wb.find_node(app.patch, e.from)
			b, _, bok := wb.find_node(app.patch, e.to)
			if aok && bok && cable_hit(jack_pos(a, "out"), jack_pos(b, "in"), local) {
				wb.disconnect(&app.patch, e.id)
				persist(app)
				refresh_code(app)
				break
			}
		}
	}
}

spec_for :: proc(node: wb.Graph_Node, key: string) -> wb.Param_Spec {
	for s in wb.params_for(node.kind) {
		if s.key == key {
			return s
		}
	}
	return {}
}

cable_hit :: proc(a, b, p: rl.Vector2) -> bool {
	dx := max(f32(36), abs(b.x - a.x) * 0.45)
	c1 := rl.Vector2{a.x + dx, a.y}
	c2 := rl.Vector2{b.x - dx, b.y}
	for i in 0 ..= 20 {
		t := f32(i) / 20
		u := 1 - t
		pt := rl.Vector2 {
			u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x,
			u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y,
		}
		if rl.Vector2Distance(pt, p) < 7 {
			return true
		}
	}
	return false
}

button :: proc(r: rl.Rectangle, label: string) -> bool {
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), r)
	rl.DrawRectangleRec(r, PANEL2)
	rl.DrawRectangleLinesEx(r, 1, hover ? ACCENT : LINE)
	rl.DrawText(strings.clone_to_cstring(label, context.temp_allocator), i32(r.x + 8), i32(r.y + 7), 14, TEXT)
	return hover && rl.IsMouseButtonPressed(.LEFT)
}

draw :: proc(app: ^App) {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	rl.DrawRectangle(0, 0, i32(w), BAR_H, PANEL)
	rl.DrawLine(0, BAR_H, i32(w), BAR_H, LINE)
	rl.DrawText("WIREBANG", 14, 12, 16, TEXT)
	rl.DrawText("Node graph for one-shot SFX. Emits Odin.", 14, 32, 12, MUTED)

	if rl.GuiTextBox({220, 14, 140, 30}, cstr(app.name_buf[:]), i32(len(app.name_buf)), app.name_edit) {
		app.name_edit = !app.name_edit
		if !app.name_edit {
			wb.set_owned_string(&app.patch.name, string(cstr(app.name_buf[:])))
			persist(app)
		}
	}
	if rl.GuiTextBox({370, 14, 150, 30}, cstr(app.fn_buf[:]), i32(len(app.fn_buf)), app.fn_edit) {
		app.fn_edit = !app.fn_edit
		if !app.fn_edit {
			wb.set_owned_string(&app.patch.fn_name, wb.sanitize_fn_name(string(cstr(app.fn_buf[:])), context.temp_allocator))
			write_cstr(app.fn_buf[:], app.patch.fn_name)
			persist(app)
			refresh_code(app)
		}
	}

	lib_text := "Library;Zap;Thump;Whoosh"
	prev := app.library_i
	rl.GuiComboBox({530, 14, 140, 30}, strings.clone_to_cstring(lib_text, context.temp_allocator), &app.library_i)
	if app.library_i != prev && app.library_i > 0 {
		entry := wb.LIBRARY[app.library_i - 1]
		wb.destroy_patch(&app.patch)
		loaded := false
		path := fmt.tprintf("sounds/%s.odin", entry.id)
		if data, err := os.read_entire_file(path, context.allocator); err == nil {
			if parsed, pok := wb.parse_code(string(data)); pok {
				app.patch = parsed
				loaded = true
			}
			delete(data)
		}
		if !loaded {
			app.patch = entry.patch()
		}
		app.selected = "out"
		app.cable_from = ""
		sync_name_bufs(app)
		persist(app)
		refresh_code(app)
		set_status(app, fmt.tprintf("Loaded %s", entry.label))
	}

	if button({680, 14, 70, 30}, "Play") {
		wb.play(app.patch)
		set_status(app, "Playing")
	}
	if button({758, 14, 70, 30}, "Bake") {
		path, ok := wb.write_baked_wav(app.patch, EXPORT_DIR)
		if ok {
			set_status(app, fmt.tprintf("Wrote %s", path))
		} else {
			set_status(app, "Bake failed")
		}
	}
	if button({836, 14, 70, 30}, "Live") {
		path, ok := wb.write_live_file(app.patch, EXPORT_DIR)
		if ok {
			set_status(app, fmt.tprintf("Wrote %s", path))
		} else {
			set_status(app, "Live export failed")
		}
	}
	if button({914, 14, 70, 30}, "New") {
		wb.destroy_patch(&app.patch)
		app.patch = wb.empty_patch()
		app.selected = "out"
		app.library_i = 0
		sync_name_bufs(app)
		persist(app)
		refresh_code(app)
		set_status(app, "New patch")
	}

	rl.DrawRectangle(0, BAR_H, PAL_W, i32(h - BAR_H), PANEL)
	rl.DrawLine(PAL_W, BAR_H, PAL_W, i32(h), LINE)
	kinds := [?]wb.Node_Kind{.Osc, .Noise, .Filter, .Gain, .Shaper, .Panner}
	for kind, i in kinds {
		r := rl.Rectangle{12, f32(BAR_H + 12 + i * 48), PAL_W - 24, 40}
		if button(r, wb.kind_label(kind)) {
			n := wb.add_node(&app.patch, kind, 80 + rand.float32() * 80, 80 + rand.float32() * 280)
			app.selected = n.id
			sync_name_bufs(app)
			persist(app)
			refresh_code(app)
		}
		rl.DrawRectangle(i32(r.x), i32(r.y), 3, i32(r.height), kind_color(kind))
	}

	board := board_rect()
	rl.BeginScissorMode(i32(board.x), i32(board.y), i32(board.width), i32(board.height))
	rl.DrawRectangleRec(board, {11, 14, 20, 255})

	rl.BeginMode2D({offset = {board.x, board.y}, target = {}, rotation = 0, zoom = 1})
	for e in app.patch.edges {
		a, _, aok := wb.find_node(app.patch, e.from)
		b, _, bok := wb.find_node(app.patch, e.to)
		if !aok || !bok {
			continue
		}
		p0 := jack_pos(a, "out")
		p1 := jack_pos(b, "in")
		dx := max(f32(36), abs(p1.x - p0.x) * 0.45)
		rl.DrawSplineSegmentBezierCubic(p0, {p0.x + dx, p0.y}, {p1.x - dx, p1.y}, p1, 2, {126, 182, 255, 140})
	}
	if app.cable_from != "" {
		if n, _, ok := wb.find_node(app.patch, app.cable_from); ok {
			p := jack_pos(n, "out")
			rl.DrawCircleV(p, 5, ACCENT)
		}
	}
	for n in app.patch.nodes {
		r := node_rect(n)
		col := kind_color(n.kind)
		rl.DrawRectangleRounded(r, 0.12, 6, PANEL2)
		border := app.selected == n.id ? ACCENT : LINE
		rl.DrawRectangleRoundedLines(r, 0.12, 6, border)
		rl.DrawRectangle(i32(r.x), i32(r.y), i32(r.width), 28, {18, 22, 32, 255})
		rl.DrawText(strings.clone_to_cstring(n.name, context.temp_allocator), i32(r.x + 18), i32(r.y + 8), 12, col)
		sum := wb.node_summary(n, context.temp_allocator)
		rl.DrawText(strings.clone_to_cstring(sum, context.temp_allocator), i32(r.x + 10), i32(r.y + 38), 12, MUTED)
		if wb.has_input(n.kind) {
			rl.DrawCircleV(jack_pos(n, "in"), 6, {154, 208, 192, 255})
		}
		if wb.has_output(n.kind) {
			rl.DrawCircleV(jack_pos(n, "out"), 6, ACCENT)
		}
	}
	rl.EndMode2D()
	if app.status != "" {
		rl.DrawText(strings.clone_to_cstring(app.status, context.temp_allocator), i32(board.x + 12), i32(board.y + board.height - 24), 14, MUTED)
	}
	rl.EndScissorMode()

	rl.DrawRectangle(i32(w - SIDE_W), BAR_H, SIDE_W, i32(h - BAR_H), PANEL)
	rl.DrawLine(i32(w - SIDE_W), BAR_H, i32(w - SIDE_W), i32(h), LINE)
	draw_inspector(app, {w - SIDE_W, f32(BAR_H), SIDE_W, 320})
	draw_code(app, {w - SIDE_W, f32(BAR_H) + 320, SIDE_W, h - BAR_H - 320})
}

draw_inspector :: proc(app: ^App, r: rl.Rectangle) {
	rl.DrawText("INSPECTOR", i32(r.x + 14), i32(r.y + 12), 13, MUTED)
	n := wb.find_node_ptr(&app.patch, app.selected)
	if n == nil {
		rl.DrawText("Select a node. Space plays.\nDelete removes. Right-click a\ncable to cut it.", i32(r.x + 14), i32(r.y + 40), 14, MUTED)
		return
	}
	rl.DrawText(strings.clone_to_cstring(wb.kind_label(n.kind), context.temp_allocator), i32(r.x + 14), i32(r.y + 36), 18, TEXT)
	if n.kind != .Out {
		if rl.GuiTextBox({r.x + 14, r.y + 64, r.width - 28, 28}, cstr(app.node_name_buf[:]), i32(len(app.node_name_buf)), app.node_name_edit) {
			app.node_name_edit = !app.node_name_edit
			if !app.node_name_edit {
				name := string(cstr(app.node_name_buf[:]))
				if name == "" {
					name = wb.kind_key(n.kind)
				}
				wb.set_owned_string(&n.name, name)
				persist(app)
				refresh_code(app)
			}
		}
	}

	x := r.x + 18
	y := r.y + 108
	for spec in wb.params_for(n.kind) {
		if spec.kind == .Enum {
			label := fmt.ctprintf("%s", spec.label)
			rl.DrawText(label, i32(x), i32(y), 12, MUTED)
			cur := wb.param_enum(n^, spec.key)
			idx: i32 = 0
			joined: string
			for opt, i in spec.options {
				if i == 0 {
					joined = opt
				} else {
					joined = fmt.tprintf("%s;%s", joined, opt)
				}
				if opt == cur {
					idx = i32(i)
				}
			}
			prev := idx
			rl.GuiComboBox({x, y + 16, 150, 26}, strings.clone_to_cstring(joined, context.temp_allocator), &idx)
			if idx != prev {
				wb.set_param_enum(n, spec.key, spec.options[idx])
				persist(app)
				refresh_code(app)
			}
			y += 52
			continue
		}
		v := wb.param_f32(n^, spec.key, spec.min)
		t := (v - spec.min) / max(spec.max - spec.min, 0.0001)
		center := rl.Vector2{x + 24, y + 24}
		rl.DrawCircleV(center, 22, {12, 16, 24, 255})
		rl.DrawRing(center, 14, 22, 210, 210 + t * 300, 24, ACCENT)
		rl.DrawCircleLinesV(center, 22, LINE)
		val: string
		if spec.unit == "Hz" {
			val = fmt.tprintf("%d", int(v + 0.5))
		} else if spec.unit == "s" {
			val = fmt.tprintf("%.3f", v)
		} else {
			val = fmt.tprintf("%.2f", v)
		}
		rl.DrawText(strings.clone_to_cstring(val, context.temp_allocator), i32(x + 8), i32(y + 50), 12, TEXT)
		rl.DrawText(strings.clone_to_cstring(spec.label, context.temp_allocator), i32(x + 8), i32(y + 64), 10, MUTED)
		knob := rl.Rectangle{x, y, 48, 80}
		if rl.CheckCollisionPointRec(rl.GetMousePosition(), knob) && rl.IsMouseButtonPressed(.LEFT) {
			app.knob_key = spec.key
			app.knob_start_y = rl.GetMousePosition().y
			app.knob_start_v = v
		}
		x += 64
		if x > r.x + r.width - 60 {
			x = r.x + 18
			y += 88
		}
	}

	y += 90
	rl.DrawText("WIRES  (click to cut)", i32(r.x + 14), i32(y), 11, MUTED)
	y += 20
	for e in app.patch.edges {
		if e.from != n.id && e.to != n.id {
			continue
		}
		from, _, _ := wb.find_node(app.patch, e.from)
		to, _, _ := wb.find_node(app.patch, e.to)
		label := fmt.tprintf("%s -> %s  x", from.name, to.name)
		if button({r.x + 14, y, r.width - 28, 24}, label) {
			wb.disconnect(&app.patch, e.id)
			persist(app)
			refresh_code(app)
		}
		y += 28
	}
}

draw_code :: proc(app: ^App, r: rl.Rectangle) {
	rl.DrawLine(i32(r.x), i32(r.y), i32(r.x + r.width), i32(r.y), LINE)
	rl.DrawText("PLAY PROC", i32(r.x + 14), i32(r.y + 10), 12, MUTED)
	rl.DrawText("Dialect Odin. Live writes the play proc. Bake is a WAV fallback.", i32(r.x + 14), i32(r.y + 28), 12, MUTED)
	src := app.code
	if len(src) > 1800 {
		src = src[:1800]
	}
	rl.DrawText(strings.clone_to_cstring(src, context.temp_allocator), i32(r.x + 12), i32(r.y + 50), 12, {201, 215, 234, 255})
}
