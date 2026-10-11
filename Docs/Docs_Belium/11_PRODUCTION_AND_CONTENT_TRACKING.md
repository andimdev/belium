# Belium — Production and Content Tracking

# 1. Existing project spreadsheet

The project owner already maintains an Excel workbook tracking:

- game dynamics/mechanics to program;
- map events;
- map locations;
- specific production items.

This workbook should be treated as a production-management companion to the Markdown docs.

---

# 2. Recommended workbook sheets

Suggested sheets:

## Narrative Matrix

Tracks:

- Event ID
- Chapter
- Route
- Location
- Playable character
- Prerequisites
- Dialogue variant
- Story effects
- Character knowledge
- Player knowledge
- Relationship effects
- Battle consequences
- Postgame linkage
- Status

## Locations

Tracks:

- map ID;
- display name;
- chapter availability;
- connected maps;
- major NPCs;
- story events;
- music;
- weather;
- assets needed;
- status.

## Mechanics

Existing/expanded technical backlog.

## Audio

See `09_AUDIO.md`.

## Pokémon / Trainers

Tracks:

- trainer;
- battle variant;
- roster;
- level;
- moves;
- items;
- route conditions;
- difficulty.

## Assets

Tracks:

- asset ID;
- type;
- source;
- format;
- runtime format;
- owner/origin;
- status;
- notes.

## Postgame Memories

Tracks:

- memory ID;
- location;
- Darkrai trigger;
- topic;
- prerequisites;
- route sensitivity;
- reward;
- status.

---

# 3. Stable identifiers

Use stable IDs for:

- events;
- maps;
- dialogue blocks;
- memories;
- trainers;
- battle variants;
- audio tracks;
- cutscenes.

Avoid using visible names as internal primary keys.

---

# 4. Figma

Potentially useful for:

- screen architecture;
- UI mockups;
- map planning;
- scene boards;
- cinematic framing;
- sprite reference boards;
- visual timelines.

Figma should complement, not replace:

- Git/versioned docs;
- structured production data.

---

# 5. Documentation ownership

Recommended rule:

- Markdown = canon + architecture + long-form design.
- Excel = production matrix + sortable operational tracking.
- Figma = visual planning.
- Godot = executable implementation.

---

# 6. Change management

When canon changes:

1. update the relevant Markdown;
2. update timeline if ages/time are affected;
3. update route matrix;
4. update event IDs/conditions if needed;
5. assess save compatibility;
6. update Godot implementation.

When only implementation changes:

- do not silently change narrative canon.

---

# 7. Canon review workflow

Before implementing a major scene:

- read relevant chapter canon;
- verify ages;
- verify current character knowledge;
- verify who is playable;
- verify which Pokémon are present;
- verify route conditions;
- verify whether the event is immutable or branch-sensitive.

---

# 8. Current known production assets/status

- large TileSet under development;
- map creation learned;
- two interfaces created;
- custom young Belium sprite work started;
- animated GIF resources being converted to sprite sheets;
- audio workflow under investigation/establishment;
- Cyrus team defined;
- Chapter structure extensively outlined.
