package main

import "core:fmt"
import "core:os"
import snd "../../sounds"
import wb "../../wirebang"

main :: proc() {
	name := "zap"
	if len(os.args) > 1 {
		name = os.args[1]
	}

	if !wb.init() {
		os.exit(1)
	}
	defer wb.shutdown()

	switch name {
	case "zap", "Zap":
		snd.play_zap()
	case "thump", "Thump":
		snd.play_thump()
	case "whoosh", "Whoosh":
		snd.play_whoosh()
	case:
		fmt.eprintf("unknown sound %q\n", name)
		fmt.println("sounds: zap, thump, whoosh")
		os.exit(1)
	}

	fmt.printf("playing %s\n", name)
	wb.wait_until_quiet()
}
