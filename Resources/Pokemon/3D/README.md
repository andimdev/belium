# Pokémon 3D runtime layout

This directory is the Godot-side deployment target for the pipeline documented
in `Pokemon_3D_Models/README.md`.

```text
3D/
├── shared/
│   └── animations/
│       ├── generic/        Reusable fallback animation
│       └── families/       Reusable anatomical-family animation
└── species/
    └── 0376/               Zero-padded National Pokédex number
        ├── source/         Original Metagross inputs (`.gdignore`)
        ├── blender/
        │   ├── generated/  Rebuildable Blender intermediates
        │   └── custom/     Approved hand-authored Blender sources
        ├── runtime/        Final GLBs and Godot-extracted textures
        ├── metadata/       PokemonBattleVisualData `.tres` resources
        ├── scenes/         PokemonBattler3D wrapper scenes
        ├── animations/
        │   ├── species_specific/
        │   └── special/
        └── reports/        Validation and QA output (`.gdignore`)
```

Runtime paths use stable asset IDs, for example:

```text
res://Resources/Pokemon/3D/species/0376/runtime/0376_base.glb
res://Resources/Pokemon/3D/species/0376/metadata/0376_base.tres
res://Resources/Pokemon/3D/species/0376/scenes/0376_base.tscn
```

Every species gets one four-digit folder and keeps all of its forms together.
Only reusable cross-species animations belong in `shared`; species-specific and
cinematic motion belongs under the corresponding species folder. `source`,
`blender` and `reports` contain `.gdignore` because Godot does not need to import
production inputs, Blender files or QA reports. Approved binary assets should be
tracked with Git LFS before the library grows significantly.

The first runtime integration uses the three 0376 paths above as one unit: the
`.tres` selects the wrapper `.tscn`, cry and presentation limits, while the
wrapper instantiates the final `.glb` and maps the logical `idle` and
`battle_enter` actions. Game code should load the metadata resource instead of
hardcoding a direct GLB path.

