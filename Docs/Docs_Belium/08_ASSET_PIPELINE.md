# Belium — Asset Pipeline

# 1. Visual direction

The game should be more cinematic and visually dynamic than original DS-era Pokémon presentation.

Desired content includes:

- animated Pokémon battle sprites;
- Mega Evolutions;
- Ultra Beasts;
- animated environment elements;
- map-engine cutscenes;
- full-screen/static story images;
- lightly animated illustrations;
- camera motion;
- weather;
- parallax;
- dimensional effects;
- large boss presentation.

---

# 2. Current TileSet work

The project owner is building a large TileSet containing:

- Pokémon Centers;
- shops;
- houses;
- bridges;
- miscellaneous map/environment assets.

Map creation in Godot is already understood at a functional level.

---

# 3. GIF handling

Godot should not rely on GIF as a runtime animation format.

Workflow established:

```text
GIF source
→ extract/export sprite sheet
→ PNG sprite sheet
→ Godot SpriteFrames / animated tile
```

Keep source GIFs for archival/reference if useful, but convert runtime assets.

---

# 4. AnimatedSprite2D workflow

For Pokémon or standalone animated objects:

1. Convert GIF to a sprite sheet.
2. Create `AnimatedSprite2D`.
3. Create a `SpriteFrames` resource.
4. Use **Add Frames from Sprite Sheet**.
5. Configure rows/columns or frame size.
6. Select the required frames.
7. Set FPS.
8. Enable loop where appropriate.

A 41-frame sprite does **not** need to be imported frame-by-frame manually.

---

# 5. Animated map tiles

For:

- flowers;
- water;
- environmental loops;
- repeating decorative elements;

prefer TileSet animation when they belong naturally to the tile grid.

Benefits:

- reuse;
- performance;
- easy map placement;
- synchronized looping.

---

# 6. Shaders

Shaders were discussed as a future option for:

- grass/wind motion;
- water;
- dimensional distortion;
- crystals;
- pulsing cracks;
- Distortion World effects;
- Necrozma-related lighting.

This is an **optional technical direction**, not a mandatory early milestone.

---

# 7. Sprite style

Desired battle animation inspiration:

- Black/White-style continuous animation.

The game only needs the Pokémon actually used by the story/content.

No requirement exists to implement every Pokémon.

---

# 8. Young Belium sprites

Custom art required.

Known design:

- black medium-length hair;
- fringe/bangs;
- visually distinct from adult Cyrus.

Existing Pokémon sprites can be used as bases/references during creation, subject to the project's intended distribution/IP approach.

---

# 9. Figma

Figma is being considered for:

- UI screens;
- map planning;
- sprite references;
- cinematics;
- scene boards;
- production layout;
- moodboards.

Recommended role:

- visual production bible;
- not the authoritative source for gameplay state.

---

# 10. Asset folder concept

Suggested organization:

```text
assets/
├── source/
│   ├── gif_original/
│   ├── audio_master/
│   └── references/
├── sprites/
│   ├── characters/
│   ├── pokemon/
│   └── effects/
├── sprite_sheets/
├── tilesets/
├── portraits/
├── illustrations/
└── audio/
```

Actual repo should avoid unnecessary duplication.

---

# 11. Animated cinematic assets

Potential techniques:

- `AnimatedSprite2D`;
- `AnimationPlayer`;
- sprite sheets;
- parallax layers;
- camera animation;
- shaders;
- particle systems;
- pre-rendered video only if necessary.

---

# 12. IP / distribution risk

The project uses Pokémon characters, locations, music references, and potentially copyrighted visual/audio assets.

This creates legal/IP distribution risk.

This document does not provide legal advice.

Practical production rule:

- keep source provenance documented;
- distinguish original/custom assets from extracted/reused assets;
- avoid assuming community availability equals redistribution permission.

## Current generated prototype assets

`resources/trainer/Cynthia-Young.png` and
`resources/trainer/Belium-Young.png` are AI-generated prototype sprite sheets
created with OpenAI's built-in image generation tool on 2026-09-19. They use the
project owner's `Cynthia-Grown.png` and `Cyrus-Grown.png` sheets as references for
frame layout, scale, and pixel-art presentation. They should be treated as
reviewable prototype art rather than implicitly approved final character assets.
