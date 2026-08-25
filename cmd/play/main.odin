package main

import "core:fmt"
import "core:os"
import "core:time"
import ma "vendor:miniaudio"
import snd "../../sounds"

main :: proc() {
	name := "zap"
	if len(os.args) > 1 {
		name = os.args[1]
	}

	eng: ma.engine
	if ma.engine_init(nil, &eng) != .SUCCESS {
		fmt.eprintf("miniaudio engine init failed\n")
		os.exit(1)
	}
	defer ma.engine_uninit(&eng)

	switch name {
	case "zap", "Zap":
		snd.play_zap(&eng)
	case "thump", "Thump":
		snd.play_thump(&eng)
	case "whoosh", "Whoosh":
		snd.play_whoosh(&eng)
	case:
		fmt.eprintf("unknown sound %q\n", name)
		fmt.println("sounds: zap, thump, whoosh")
		os.exit(1)
	}

	fmt.printf("playing %s\n", name)
	time.sleep(2 * time.Second)
}
