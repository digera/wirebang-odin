package main

import "core:fmt"
import "core:os"
import wb "../../wirebang"

main :: proc() {
	name := "zap"
	if len(os.args) > 1 {
		name = os.args[1]
	}

	entry: wb.Library_Entry
	found := false
	for e in wb.LIBRARY {
		if e.id == name || e.label == name {
			entry = e
			found = true
			break
		}
	}
	if !found {
		fmt.eprintf("unknown sound %q\n", name)
		fmt.println("sounds: zap, thump, whoosh")
		os.exit(1)
	}

	if !wb.init() {
		os.exit(1)
	}
	defer wb.shutdown()

	patch := entry.patch()
	defer wb.destroy_patch(&patch)
	if !wb.play(patch) {
		fmt.eprintf("failed to play %s\n", entry.label)
		os.exit(1)
	}
	fmt.printf("playing %s\n", entry.label)
	wb.wait_until_quiet()
}
