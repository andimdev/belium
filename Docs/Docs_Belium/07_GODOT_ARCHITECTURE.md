# Belium — Godot Architecture

# 1. Engine

Current direction:

- Godot 4.x
- project owner reports Godot 4.7.2 available
- Godot .NET 4.7.2 also available

Primary implementation recommendation:

- start mainly in **GDScript**;
- introduce C# selectively if a system materially benefits from stronger typing or scale.

The project owner is an experienced software engineer but a Godot beginner, so architecture should be clean without over-engineering early.

---

# 2. Recommended repository structure

```text
Belium/
├── AGENTS.md
├── docs/
├── scenes/
│   ├── overworld/
│   ├── map/
│   ├── character/
│   ├── battle/
│   ├── cutscene/
│   └── ui/
├── scripts/
│   ├── core/
│   ├── story/
│   ├── overworld/
│   ├── battle/
│   ├── ui/
│   └── data/
├── resources/
│   ├── pokemon/
│   ├── moves/
│   ├── item/
│   ├── trainer/
│   ├── encounter/
│   └── story/
├── assets/
│   ├── sprite/
│   ├── tileset/
│   ├── portrait/
│   ├── illustration/
│   ├── audio/
│   └── source/
├── shaders/
├── tests/
└── project.godot
```

Actual project structure should adapt to what already exists.

---

# 3. Early system boundaries

Recommended conceptual services/managers:

## GameState / StoryState

Owns persistent narrative state.

## MapManager

Handles:

- map loading;
- transitions;
- spawn points;
- map-entry metadata.

## InteractionSystem

Handles player interaction with:

- NPCs;
- signs;
- doors;
- objects;
- event hotspots.

## DialogueSystem

Loads and presents dialogue while evaluating conditions.

## EventRunner / CutsceneRunner

Executes authored event sequences.

## SaveSystem

Serializes/deserializes versioned save data.

## AudioManager

Handles:

- music;
- loops;
- crossfades;
- buses;
- persistent track state.

## BattleManager

Future system for starting/resolving battles.

---

# 4. Avoid map-local story coupling

Bad pattern:

```text
Route201.gd
if player_has_badge_4 and cynthia_route and not event_72:
    ...
```

Preferred pattern:

```text
Map trigger -> Event ID -> Story/Event system -> conditions/effects
```

Maps should host triggers, not own the entire story logic.

---

# 5. Data-driven content

Long-lived content should prefer:

- Godot `Resource` types;
- external JSON where appropriate;
- stable IDs;
- references by ID rather than fragile scene-path assumptions.

Candidate data:

- Pokémon species;
- moves;
- items;
- trainer teams;
- encounter tables;
- dialogue;
- story event definitions;
- battle variants;
- cutscene metadata.

---

# 6. Story state model

Conceptual structure:

```text
StoryState
├── world
├── route
├── player_knowledge
├── character_knowledge
├── relationships
├── battle_profile
└── postgame_memories
```

Exact class/resource design: **TBD**.

---

# 7. Character controller

Expected early Godot nodes:

- `CharacterBody2D`
- `AnimatedSprite2D`
- `CollisionShape2D`
- `RayCast2D` or equivalent interaction detection
- `Camera2D`

Grid vs free movement is not yet explicitly fixed.

## Initial movement prototype

The first free-movement prototype is implemented with:

- `scenes/character/cyrus_player.tscn` as the reusable player scene;
- `CharacterBody2D` movement and a feet-level collision shape;
- a lightweight `IDLE` / `WALK` / `RUN` state machine;
- strictly cardinal movement with one active axis at a time;
- independent walking and running speeds;
- a following `Camera2D`;
- `scenes/overworld/movement_prototype.tscn` as the empty test environment.

Current default controls are WASD or arrow keys for movement and Shift for running.
The controller registers these temporary prototype bindings at runtime; a future
input-settings system can replace them without changing movement-state logic.

Adult Cyrus and Cynthia share the same controller. Enter switches the active
character in place, transferring position and facing while enabling only the
selected character's input, collision, visibility, and camera.

---

# 8. Maps

The project owner already knows how to create maps.

Current map tooling/content:

- `TileMapLayer`;
- large custom TileSet;
- centers;
- shops;
- houses;
- bridges;
- miscellaneous environment assets.

Animated environment content should use:

- animated tiles where appropriate;
- `AnimatedSprite2D` for stand-alone animated objects;
- shaders for effects where useful.

## Initial map-layer contract

`scenes/map/basic_map.tscn` establishes the first reusable map composition.
Its playable area is 1600×1200 pixels on a 16×16 base grid and its ordered
layers are:

1. `background_bottom` — base terrain such as grass;
2. `background_upon` — paths, flowers, stones, and terrain decoration;
3. `buildings` — buildings and their local collision bodies;
4. `character` — player and map actors;
5. `details` — atmospheric and story-relevant visual effects;
6. `limit` — map-border collision and future forest/mountain blockers.

The prototype fills `background_bottom` at runtime through a `TileSetAtlasSource`
backed by `set1.png`. Grass and two flower variants are selected through stable
atlas-coordinate constants. The first red Pokémon Center uses a 96×128 atlas
region with map-authored scale. The `limit` layer generates a perimeter of trees
backed by inset physical boundaries. The `character` layer contains Cyrus, adult
Cynthia, young Belium, and young Cynthia as separate reusable scenes.

---

# 9. Event/cutscene implementation

Godot tools likely involved:

- `AnimationPlayer`;
- signals;
- tweens;
- reusable event commands;
- camera control;
- dialogue callbacks.

Potential authored commands:

```text
move_actor
face_actor
play_animation
camera_pan
camera_shake
fade
play_music
crossfade_music
play_sfx
show_dialogue
wait
set_flag
start_battle
change_map
```

This command-based system is a recommendation, not yet implemented.

---

# 10. C# usage

C# is optional.

Potential future candidates:

- large battle simulation systems;
- AI evaluation;
- complex data processing;
- tooling.

Do not mix C# and GDScript without a concrete reason.

---

# 11. Framework history

Pokémon-Godot-style frameworks were discussed as possible accelerators.

However, the preferred early strategy became:

1. learn Godot fundamentals;
2. build a small vertical slice;
3. evaluate external frameworks later;
4. avoid importing a huge framework before understanding the engine.

Any named third-party Pokémon Godot framework should be re-verified before adoption.

---

# 12. First vertical-slice architecture

Target sequence:

```text
Boot
→ Load Map
→ Player Movement
→ NPC Interaction
→ Dialogue
→ Story Trigger
→ Cutscene
→ Map Transition
→ Audio Loop
→ Save
```

This should exist before implementing the full Pokémon battle engine.
