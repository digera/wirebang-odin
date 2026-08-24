package sounds

import wb "../wirebang"
import ma "vendor:miniaudio"

ZAP_NODES := wb.ZAP_NODES
ZAP_EDGES := wb.ZAP_EDGES

make_zap :: proc(allocator := context.allocator) -> wb.Patch {
	return wb.library_zap(allocator)
}

play_zap :: proc(engine: ^ma.engine = nil) {
	p := make_zap()
	defer wb.destroy_patch(&p)
	if engine != nil {
		wb.play(engine, p)
	} else {
		wb.play(p)
	}
}
