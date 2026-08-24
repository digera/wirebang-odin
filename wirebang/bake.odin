package wirebang

import "core:encoding/endian"
import "core:math"

bake :: proc(patch: Patch, sample_rate: f32 = DEFAULT_SAMPLE_RATE, allocator := context.allocator) -> []f32 {
	v := voice_from_patch(patch, sample_rate, context.temp_allocator)
	frames := make([]f32, int(v.length) * CHANNELS, allocator)
	render_frames(&v, frames)
	return frames
}

bake_wav :: proc(patch: Patch, sample_rate: u32 = DEFAULT_SAMPLE_RATE, allocator := context.allocator) -> []u8 {
	pcm := bake(patch, f32(sample_rate), context.temp_allocator)
	return pcm_to_wav(pcm, sample_rate, allocator)
}

pcm_to_wav :: proc(pcm: []f32, sample_rate: u32, allocator := context.allocator) -> []u8 {
	frame_count := len(pcm) / CHANNELS
	data_bytes := frame_count * CHANNELS * 2
	out := make([]u8, 44 + data_bytes, allocator)
	copy(out[0:4], transmute([]u8)string("RIFF"))
	endian.put_u32(out[4:8], .Little, u32(36 + data_bytes))
	copy(out[8:12], transmute([]u8)string("WAVE"))
	copy(out[12:16], transmute([]u8)string("fmt "))
	endian.put_u32(out[16:20], .Little, 16)
	endian.put_u16(out[20:22], .Little, 1)
	endian.put_u16(out[22:24], .Little, u16(CHANNELS))
	endian.put_u32(out[24:28], .Little, sample_rate)
	endian.put_u32(out[28:32], .Little, sample_rate * u32(CHANNELS) * 2)
	endian.put_u16(out[32:34], .Little, u16(CHANNELS * 2))
	endian.put_u16(out[34:36], .Little, 16)
	copy(out[36:40], transmute([]u8)string("data"))
	endian.put_u32(out[40:44], .Little, u32(data_bytes))
	for i in 0 ..< len(pcm) {
		s := clamp(pcm[i], -1, 1)
		q := i16(math.round(f32(s) * 32767))
		endian.put_i16(out[44 + i * 2:], .Little, q)
	}
	return out
}
