# Wirebang

A node graph for one-shot SFX. Written in Odin. Preview is live through miniaudio. Default game export is a baked WAV.

## License

The editor is [MIT](LICENSE).

**You own what you make.** Copied or downloaded Odin and WAV files are yours. You may copyright them, keep them closed-source, and ship them in a commercial game. There is no attribution requirement.

## Build

Requires [Odin](https://odin-lang.org/) with `vendor:miniaudio` and `vendor:raylib`.

```bash
odin test wirebang
odin build cmd/play -out:bin/play.exe
odin build cmd/editor -out:bin/editor.exe
```

## Use the editor

```bash
bin/editor
```

The editor draws with raylib and plays through miniaudio. It does not call raylib's `InitAudioDevice`.

1. Add nodes from the left palette (oscillator, noise, filter, gain, shaper, panner).
2. Click an output jack, then an input jack, to cable them. Right-click a cable to cut it.
3. Select a node and drag its knobs (Shift = fine). Space plays the patch.
4. **Bake** writes a WAV plus an Odin wrapper to `export/`. **Live** writes a playable `Patch` instead.

The graph is the source of truth. Preview and bake share one voice, so Space and the exported sample are the same synth.

The current graph is saved to `wirebang-patch.json`.

## Play from the command line

```bash
bin/play zap
bin/play thump
bin/play whoosh
```

## Use in a game

Baked one-shots are just samples. Drop the WAV onto whatever you already use:

- miniaudio `ma_decoder` / `ma_sound_init_from_file`
- raylib `LoadSound` / `LoadWaveFromMemory` next to existing music

You do not need the Wirebang DSP in a shipped game if you bake.

Live playback is opt-in. Link `wirebang` and call `wb.play(patch)` (or `wb.play(&engine, patch)` if you already have a `ma.engine`). A raylib game can keep `InitAudioDevice` for music and still open a Wirebang engine for live one-shots. Shared-mode devices usually allow both. One engine for all audio is cleaner when you can do it.

```odin
import wb "wirebang"

wb.init()
wb.play(patch)
wb.wait_until_quiet()
wb.shutdown()
```

`sounds/` is the example library (Zap, Thump, Whoosh). Treat those files the same way as anything you export: use them, change them, or ignore them.

## Scope

In: short procedural SFX, live preview, baked WAV export, optional live Odin patch export.

Out: a DAW, sample playback engine, or a shipped mixer.
