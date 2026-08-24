package wirebang

import "core:testing"

@(test)
test_bake_library_sounds_have_energy :: proc(t: ^testing.T) {
	for entry in LIBRARY {
		p := entry.patch()
		defer destroy_patch(&p)
		pcm := bake(p)
		defer delete(pcm)
		testing.expect(t, len(pcm) > 100, entry.label)
		peak: f32
		energy: f32
		for s in pcm {
			a := abs(s)
			peak = max(peak, a)
			energy += a
		}
		testing.expectf(t, peak > 0.01, "%s peak was %v", entry.label, peak)
		testing.expectf(t, energy > 1, "%s energy was %v", entry.label, energy)
	}
}

@(test)
test_wav_header :: proc(t: ^testing.T) {
	p := library_thump()
	defer destroy_patch(&p)
	wav := bake_wav(p)
	defer delete(wav)
	testing.expect(t, len(wav) > 44)
	testing.expect_value(t, string(wav[0:4]), "RIFF")
	testing.expect_value(t, string(wav[8:12]), "WAVE")
}
