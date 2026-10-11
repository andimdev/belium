# Belium — Gameplay Systems

# 1. Overworld foundation

Priority systems:

- player movement;
- map transitions;
- interaction;
- NPC interaction;
- dialogue;
- triggers;
- story events;
- cutscenes;
- save/load;
- music/ambience;
- route conditions.

The project owner already knows how to create maps in Godot and has a growing TileSet.

---

# 2. Story event system

Events should not be hardcoded independently inside every map.

Preferred structure:

- stable event IDs;
- reusable trigger conditions;
- centralized story-state queries;
- scripted/declarative event sequences;
- persistence to save data.

Example conceptual event:

```text
Event: C1_CYN_014

Requires:
- chapter == 1
- route == CYNTHIA
- badge_count >= 4
- dragonair_event_started == false

Effects:
- set world.dragonair_event_started
- update cynthia knowledge
- launch cutscene
- lock/unlock locations
```

Exact implementation language/API is TBD.

---

# 3. Story state

Recommended categories:

- world state;
- route state;
- player knowledge;
- character knowledge;
- relationships;
- battle telemetry;
- postgame memory state;
- system progression.

The save format should be versioned.

---

# 4. Dialogue system

Requirements:

- localization-ready;
- route-aware;
- condition-aware;
- speaker-aware;
- supports portraits if added;
- supports choice prompts;
- choices can emit story effects;
- can distinguish player knowledge from character knowledge;
- can be triggered from NPCs, map events, battles, memories, and cutscenes.

---

# 5. Cutscene system

The game is intended to be more cinematic than DS-era Pokémon.

Desired capabilities:

- player/NPC movement;
- camera pans;
- camera zoom/shake;
- fades;
- weather;
- rain;
- snow;
- flashes;
- earthquakes;
- sprite animation;
- dialogue;
- music transitions;
- sound effects;
- timed waits;
- event flags;
- battle transition;
- illustrated/full-screen story images;
- potentially parallax / lightly animated CGs.

Godot `AnimationPlayer` and a reusable event/cutscene runner are likely central tools.

---

# 6. Battle system — high-level goals

The final battle engine must eventually support:

- standard Pokémon-style turn combat;
- animated Pokémon sprites;
- Mega Evolution;
- Ultra Beasts;
- special boss rules;
- stronger AI;
- single and double battles;
- boss-only abilities/mechanics;
- highly authored Cyrus fights.

The project does **not** need every Pokémon.

Only the subset required by the game's content is necessary.

---

# 7. Cyrus dynamic battle system

Cyrus's team can vary based on:

- narrative decisions;
- route history;
- levels/progression;
- possibly battle behavior;
- difficulty.

Potential battle changes:

- roster;
- levels;
- moves;
- battle format;
- AI behavior;
- lead;
- final Pokémon;
- Mega choice.

## Optional battle telemetry

A future system could track:

- most-used Pokémon;
- common leads;
- preferred types;
- status usage;
- switching frequency;
- recurring tactics.

This could inform authored Cyrus variants.

This is an **optional design proposal**, not yet a required feature.

---

# 8. Boss design

## Giratina

Not treated as a normal Legendary encounter.

Confirmed direction:

- ~Level 100;
- extremely boosted;
- unique ability/mechanic;
- 1-vs-3-style presentation;
- intentionally difficult.

## Necrozma

Boss progression:

1. fused form with Solgaleo/Lunala;
2. release of Solgaleo/Lunala;
3. Ultra Necrozma.

## Ultra Necrozma

Can use phase-based boss design and battlefield rule changes.

Exact mechanics: **TBD**.

---

# 9. Postgame memory system

Darkrai leads the player physically to memory locations.

The player does **not** simply click memories from a menu.

Possible sequence:

1. Darkrai appears.
2. Player follows Darkrai.
3. Arrive at meaningful location.
4. Darkrai uses its power.
5. Flashback/memory starts.
6. Memory reveals hidden event.
7. Return to present.
8. Memory state is saved.

Whether every memory is cinematic or partially playable remains open.

---

# 10. Gym progression

Known story-linked badge anchors:

- Chapter I Cynthia route: fourth badge before Dragonair death;
- fifth badge before +4-year skip;
- Chapter II Cynthia route: eighth badge before long League-training period.

Later Lucas/Maya Gym content:

- stronger than standard;
- includes exclusive events;
- not a simple vanilla Platinum difficulty curve.

---

# 11. Difficulty philosophy

The project explicitly wants:

- difficult Cyrus fights;
- especially difficult Chapter III bosses;
- route-sensitive challenge;
- stronger AI.

Difficulty should be authored rather than relying only on inflated levels.

---

# 12. Save system requirements

Must preserve:

- current chapter;
- playable-route history;
- story flags;
- world state;
- player knowledge;
- character knowledge;
- relationships;
- badge progression;
- party/inventory;
- Cyrus-variant determinants;
- postgame memories;
- content version.

Use a version field for future migration.

---

# 13. Localization

The creator frequently works bilingually, but project localization status is not yet fixed.

System should avoid hardcoding display text into gameplay logic.

This is a technical recommendation, not a confirmed release requirement.
