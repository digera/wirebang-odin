package sounds

import wb "../wirebang"
import ma "vendor:miniaudio"

WHOOSH_NODES := wb.WHOOSH_NODES
WHOOSH_EDGES := wb.WHOOSH_EDGES

make_whoosh :: proc(allocator := context.allocator) -> wb.Patch {
	return wb.library_whoosh(allocator)
}

play_whoosh :: proc(engine: ^ma.engine = nil) {
	p := make_whoosh()
	defer wb.destroy_patch(&p)
	if engine != nil {
		wb.play(engine, p)
	} else {
		wb.play(p)
	}
}
