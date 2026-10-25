# Plushie

Turn a player you see into a plushie, wearing the outfit they have on right now. Name it, resize it, pose it, and hug it.

*This mod was created with the assistance of AI.*

See `thunderstore/README.md` for what it does and how to use it.

## How it works

- `plush.gd` builds a plushie from the game's own player scene (same skeleton, face, tail and cosmetics code) and holds it in a pose by turning the skeleton's bones. It sits on the ground by working out the lowest point of the skinned body for each pose.
- `poses.gd` is the pose table.
- `main.gd` is the menu, saving (`user://plushie.json`), the Steam lobby sync (`plushie`, `plushie_h`, `plushie_v` member data) and the small "E  Hug" tag, the hug (two-bone arm reach like Hugs and More, squeak, hearts).
- `squeak*.wav` are three squeaks made with a small script (synthesised, no recordings).

## Building

The mod is plain GDScript plus three sounds, packed into `package/Plushie/Plushie.pck` with the Godot 3.5 engine's own packer:

```
godot --no-window -s pack.gd
./build.sh
```

`build.sh` makes `out/Plushie-mod.zip` (the folder for `GDWeave/mods`) and the Thunderstore upload zip from `thunderstore/`. Requires [GDWeave](https://thunderstore.io/c/webfishing/p/NotNet/GDWeave/).

`tests/` has the Godot scripts used to check it against a decompiled copy of the game (not included).

## License

MIT, see `LICENSE`.
