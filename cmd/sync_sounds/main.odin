package main

import "core:fmt"
import "core:os"
import wb "../../wirebang"

main :: proc() {
	os.make_directory("sounds")
	for entry in wb.LIBRARY {
		p := entry.patch()
		defer wb.destroy_patch(&p)
		src := wb.generate_code(p, {package_name = "sounds"})
		defer delete(src)
		path := fmt.tprintf("sounds/%s.odin", entry.id)
		if err := os.write_entire_file(path, transmute([]u8)src); err != nil {
			fmt.eprintf("failed to write %s\n", path)
			os.exit(1)
		}
		fmt.println(path)
	}
}
