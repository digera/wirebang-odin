package sounds

import wb "../wirebang"
import ma "vendor:miniaudio"

THUMP_NODES := wb.THUMP_NODES
THUMP_EDGES := wb.THUMP_EDGES

make_thump :: proc(allocator := context.allocator) -> wb.Patch {
	return wb.library_thump(allocator)
}

play_thump :: proc(engine: ^ma.engine = nil) {
	p := make_thump()
	defer wb.destroy_patch(&p)
	if engine != nil {
		wb.play(engine, p)
	} else {
		wb.play(p)
	}
}
