# Belium — Story Routes and Branching

# 1. Core route philosophy

Belium uses **perspective divergence with canonical convergence**.

The game is not designed around radically different endings.

The goal is that different routes reveal different parts of the same story.

A player should be able to finish the game while knowing a different subset of the truth than another player.

The postgame helps complete the missing picture.

---

# 2. Chapter I branching

## Playable perspectives

- **Belium**, age 16
- **Cynthia**, age 14

## Route purpose

### Belium route

Should expose information only Belium can know:

- internal reactions;
- Dragonair relationship;
- his interpretation of Cynthia;
- fear, grief, doubt;
- early fractures in worldview.

Exact route-exclusive event list: **TBD**.

### Cynthia route

Known content:

- Rowan assistant role;
- trainer journey;
- Gym progression;
- fourth badge;
- Dragonair death event;
- aftermath;
- fifth badge;
- first major time skip.

It can also reveal external observations Belium would not see.

---

# 3. Chapter II branching

## Early Chapter II

Primary focus is Cynthia after the four-year skip.

Content:

- Sinnoh mythology study;
- attempts to find Belium;
- 2.5-year trace/search period;
- Corvisquire observation;
- Gym progression;
- eighth badge;
- intense training;
- five-year transition.

## Later Chapter II

Perspective moves to:

- Lucas
- or Maya

The selected protagonist begins an elevated-level Sinnoh adventure.

The route can include:

- unique dialogue;
- unique interactions;
- route-dependent scenes;
- different knowledge accumulation.

---

# 4. Chapter III branching

## Confirmed route concept

Player can:

- continue as Lucas/Maya;
- or switch to Cynthia.

Exact selection timing/mechanics: **TBD**.

## Distortion World

Different protagonists should not receive identical dialogue.

Key principle:

> The player may know information that the current character does not.

Example:

- a player who experienced Belium's Chapter I knows Dragonair's history;
- Lucas/Maya should not automatically know it unless they learned it in-universe;
- Cynthia may know some parts that Lucas/Maya do not.

---

# 5. Knowledge model

## CONFIRMED DESIGN DIRECTION

The route system should conceptually distinguish:

### World State

What objectively happened.

Example:

`dragonair_died = true`

### Player Knowledge

What this save/player has seen or discovered.

Example:

`player_knows_dragonair_context = true`

### Character Knowledge

What an in-universe character knows.

Example:

`cynthia_knows_dragonair = true`
`lucas_knows_dragonair = false`

### Relationships

State of important relationships.

Examples:

- Cynthia ↔ Belium
- Belium ↔ Houndoom
- Belium ↔ Crobat
- Cyrus ↔ Giratina

### Route State

Chosen playable perspectives and branch progress.

---

# 6. Dialogue gating

Dialogue should be gated by:

- speaker;
- route;
- world facts;
- character knowledge;
- relationship state;
- prior events;
- optional postgame discoveries.

A character must not reference knowledge only the player possesses.

---

# 7. Route matrix

A production spreadsheet should eventually map:

- event ID;
- chapter;
- location;
- playable character;
- prerequisites;
- exclusive dialogue;
- world-state changes;
- character-knowledge changes;
- player-knowledge changes;
- relationship changes;
- save flags;
- battle consequences;
- postgame memory links.

Recommended stable event ID format:

`C{chapter}_{route}_{number}`

Examples:

- `C1_BEL_001`
- `C1_CYN_004`
- `C2_CYN_019`
- `C2_LUC_027`
- `C2_MAY_027`
- `C3_CYN_011`
- `PG_MEM_006`

---

# 8. What branches may change

Confirmed/intended branch-sensitive content:

- playable protagonist;
- scenes;
- conversations;
- route-exclusive dialogue;
- optional events;
- flashbacks;
- knowledge;
- story context;
- Cyrus's team;
- Cyrus's levels;
- battle format;
- battle AI difficulty.

---

# 9. What branches may NOT change

Current immutable outcome:

- Cyrus/Belium dies.

Other fixed narrative anchors are listed in `01_NARRATIVE_CANON.md`.

---

# 10. Replayability objective

Different playthroughs should provide:

- unseen dialogue;
- different interpretations;
- events unavailable to other route combinations;
- different context for the same canonical moment.

A second playthrough should not merely repeat the same content under a different sprite.

---

# 11. Postgame and route completion

The postgame provides a fourth perspective:

- not simply Belium;
- not simply Cynthia;
- not simply Lucas/Maya;
- but a reconstruction through Darkrai and surviving evidence.

Main story memories should eventually clarify essential canon.

Optional/contextual memories can reward route completion and replay.
