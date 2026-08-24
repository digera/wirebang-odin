# Sounds

Example one-shots used by the editor library and `cmd/play`.

Each file exposes `make_*` (a `wirebang.Patch`) and `play_*` (live miniaudio playback). Drop them in a game the same way as a Live export: call `make_*`, then `wb.play` or `wb.bake`.

Generated or copied files are yours. You may copyright them and ship them in a closed-source project. No attribution required.

Bake from the editor only if you want a WAV and no Wirebang DSP in the binary.
