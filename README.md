# Wirebang

A node graph for one-shot SFX, written in Odin. The graph is the editor. The Odin it emits is the sound.

Preview, Live export, and in-game playback run the same dialect: a `play_*` procedure that builds oscillators, filters, and cables. There is no `Patch` table in the exported file. WAV is a fallback if you do not want the DSP in the game.

## License

The editor is [MIT](LICENSE).

**You own what you make.** Copied or downloaded Odin and WAV files are yours. You may copyright them, keep them closed-source, and ship them in a commercial game. There is no attribution requirement.

## Build

Requires [Odin](https://odin-lang.org/) with `vendor:miniaudio` and `vendor:raylib`.

```bash
odin test wirebang
odin run cmd/sync_sounds
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
4. **Live** writes a `play_*` procedure to `export/`. **Bake** writes a WAV if you would rather drop a sample on an existing loader.

The current graph is saved to `wirebang-patch.json` (editor only). Drop an exported `.odin` in `sounds/` and pick it from the library to reopen the graph from the code.

## Play from the command line

```bash
bin/play zap
bin/play thump
bin/play whoosh
```

## Use in a game

Drop the exported Odin next to `wirebang` and call `play_*`:

```odin
import wb "wirebang"
import sfx "export" // or copy play_zap into your tree

wb.init()
play_zap()
wb.wait_until_quiet()
wb.shutdown()
```

`play_zap(&engine)` if you already have a `ma.engine`. A raylib game can keep `InitAudioDevice` for music and still open a Wirebang engine for live one-shots. Shared-mode devices usually allow both. One engine for all audio is cleaner when you can do it.

Handwritten files in the same dialect (`wb.osc`, `wb.connect`, …) reopen as graphs. Arbitrary Odin that wanders off-dialect will not.

`sounds/` is the example library (Zap, Thump, Whoosh). Treat those files the same way as anything you export: use them, change them, or ignore them.

WAV is optional. If you do not want to link the DSP, Bake and play the file with whatever you already use (`ma_decoder`, raylib `LoadSound`).

## Scope

In: short procedural SFX, live preview, Odin play-proc export, optional WAV bake.

Out: a DAW, sample playback engine, or a shipped mixer.
