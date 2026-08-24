package wirebang

import "core:c"
import "core:fmt"
import "base:runtime"
import "core:time"
import ma "vendor:miniaudio"

MAX_PLAYING :: 32

Voice_Source :: struct {
	base:  ma.data_source_base,
	voice: Voice,
}

Playing_Sound :: struct {
	used:   bool,
	source: Voice_Source,
	sound:  ma.sound,
}

@(private)
g_owned_engine: ma.engine

@(private)
g_engine: ^ma.engine

@(private)
g_inited: bool

@(private)
g_owned: bool

@(private)
g_playing: [MAX_PLAYING]Playing_Sound

@(private)
voice_vtable := ma.data_source_vtable {
	onRead          = source_read,
	onSeek          = source_seek,
	onGetDataFormat = source_format,
	onGetCursor     = source_cursor,
	onGetLength     = source_length,
	onSetLooping    = source_loop,
}

@(private)
source_read :: proc "c" (p: ^ma.data_source, out: rawptr, frame_count: u64, frames_read: ^u64) -> ma.result {
	context = runtime.default_context()
	src := cast(^Voice_Source)p
	n: u64 = 0
	frames := ([^]f32)(out)
	for n < frame_count {
		l, r, ok := voice_tick(&src.voice)
		if !ok {
			break
		}
		if frames != nil {
			frames[n * 2] = l
			frames[n * 2 + 1] = r
		}
		n += 1
	}
	if frames_read != nil {
		frames_read^ = n
	}
	return .SUCCESS
}

@(private)
source_seek :: proc "c" (p: ^ma.data_source, frame_index: u64) -> ma.result {
	context = runtime.default_context()
	src := cast(^Voice_Source)p
	if frame_index == 0 {
		src.voice.frame = 0
		src.voice.ended = false
		for &n in src.voice.nodes {
			n.phase = 0
			n.noise_pos = 0
			n.z1 = 0
			n.z2 = 0
		}
		return .SUCCESS
	}
	return .NOT_IMPLEMENTED
}

@(private)
source_format :: proc "c" (
	p: ^ma.data_source,
	format: ^ma.format,
	channels: ^u32,
	sample_rate: ^u32,
	channel_map: [^]ma.channel,
	channel_map_cap: c.size_t,
) -> ma.result {
	src := cast(^Voice_Source)p
	if format != nil {
		format^ = .f32
	}
	if channels != nil {
		channels^ = CHANNELS
	}
	if sample_rate != nil {
		sample_rate^ = u32(src.voice.sample_rate)
	}
	return .SUCCESS
}

@(private)
source_cursor :: proc "c" (p: ^ma.data_source, cursor: ^u64) -> ma.result {
	src := cast(^Voice_Source)p
	if cursor != nil {
		cursor^ = src.voice.frame
	}
	return .SUCCESS
}

@(private)
source_length :: proc "c" (p: ^ma.data_source, length: ^u64) -> ma.result {
	src := cast(^Voice_Source)p
	if length != nil {
		length^ = src.voice.length
	}
	return .SUCCESS
}

@(private)
source_loop :: proc "c" (_: ^ma.data_source, _: b32) -> ma.result {
	return .INVALID_OPERATION
}

init :: proc() -> bool {
	if g_inited {
		return true
	}
	if ma.engine_init(nil, &g_owned_engine) != .SUCCESS {
		fmt.eprintf("wirebang: failed to init miniaudio engine\n")
		return false
	}
	g_engine = &g_owned_engine
	g_inited = true
	g_owned = true
	return true
}

init_with_engine :: proc(eng: ^ma.engine) -> bool {
	if eng == nil {
		return init()
	}
	if g_inited && g_owned {
		ma.engine_uninit(&g_owned_engine)
	}
	g_engine = eng
	g_inited = true
	g_owned = false
	return true
}

shutdown :: proc() {
	reap()
	for &slot in g_playing {
		if slot.used {
			release_slot(&slot)
		}
	}
	if g_inited && g_owned {
		ma.engine_uninit(&g_owned_engine)
	}
	g_engine = nil
	g_inited = false
	g_owned = false
}

engine :: proc() -> ^ma.engine {
	if !g_inited {
		init()
	}
	return g_engine
}

reap :: proc() {
	for &slot in g_playing {
		if slot.used && bool(ma.sound_at_end(&slot.sound)) {
			release_slot(&slot)
		}
	}
}

@(private)
release_slot :: proc(slot: ^Playing_Sound) {
	ma.sound_uninit(&slot.sound)
	ma.data_source_uninit(cast(^ma.data_source)&slot.source.base)
	destroy_voice(&slot.source.voice)
	slot.used = false
}

play :: proc {
	play_patch,
	play_patch_engine,
}

play_patch :: proc(patch: Patch) -> bool {
	if !g_inited && !init() {
		return false
	}
	return play_patch_engine(g_engine, patch)
}

play_patch_engine :: proc(eng: ^ma.engine, patch: Patch) -> bool {
	if eng == nil {
		return play_patch(patch)
	}
	reap()
	slot: ^Playing_Sound
	for &s in g_playing {
		if !s.used {
			slot = &s
			break
		}
	}
	if slot == nil {
		fmt.eprintf("wirebang: too many overlapping one-shots\n")
		return false
	}

	rate := f32(ma.engine_get_sample_rate(eng))
	if rate <= 0 {
		rate = DEFAULT_SAMPLE_RATE
	}
	slot.source.voice = voice_from_patch(patch, rate)
	cfg := ma.data_source_config_init()
	cfg.vtable = &voice_vtable
	if ma.data_source_init(&cfg, cast(^ma.data_source)&slot.source.base) != .SUCCESS {
		destroy_voice(&slot.source.voice)
		return false
	}
	flags := ma.sound_flags{.NO_PITCH, .NO_SPATIALIZATION}
	if ma.sound_init_from_data_source(eng, cast(^ma.data_source)&slot.source.base, flags, nil, &slot.sound) !=
	   .SUCCESS {
		ma.data_source_uninit(cast(^ma.data_source)&slot.source.base)
		destroy_voice(&slot.source.voice)
		return false
	}
	if ma.sound_start(&slot.sound) != .SUCCESS {
		release_slot(slot)
		return false
	}
	slot.used = true
	return true
}

any_playing :: proc() -> bool {
	reap()
	for s in g_playing {
		if s.used {
			return true
		}
	}
	return false
}

wait_until_quiet :: proc(timeout := 2 * time.Second) {
	start := time.now()
	for any_playing() {
		if time.since(start) > timeout {
			break
		}
		time.sleep(5 * time.Millisecond)
	}
}
