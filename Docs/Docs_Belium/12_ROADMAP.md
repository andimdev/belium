# Belium — Development Roadmap

This roadmap is intentionally incremental.

Do not begin by implementing the full Pokémon ecosystem.

# Phase 0 — Documentation / source of truth

Status: **in progress**

Deliverables:

- `AGENTS.md`
- Project Bible
- Canon
- Timeline
- Characters
- Pokémon/teams
- Routes
- Gameplay systems
- Godot architecture
- Asset pipeline
- Audio
- Postgame memories
- production tracking

Next:

- owner review;
- corrections;
- promote only approved material to canon.

---

# Phase 1 — Overworld foundation

Goal: make one small story slice playable end-to-end.

Implement:

- player controller;
- animation;
- collisions;
- camera;
- map loading;
- spawn points;
- doors;
- transitions;
- interaction;
- NPC base;
- signs/objects.

Success condition:

Player can enter a map, walk, interact, change maps, and return safely.

---

# Phase 2 — Dialogue + StoryState

Implement:

- dialogue UI;
- speaker data;
- conditional lines;
- choices;
- story flags;
- world state;
- route state;
- player knowledge;
- character knowledge;
- relationship data;
- persistence.

Success condition:

A dialogue can change state and later dialogue can react correctly.

---

# Phase 3 — Event / cutscene runner

Implement reusable commands for:

- actor movement;
- facing;
- animation;
- camera;
- fades;
- dialogue;
- waits;
- audio;
- flags;
- map transition;
- battle start placeholder.

Success condition:

A multi-character story scene can run without custom one-off code inside the map.

---

# Phase 4 — Save / load

Implement:

- versioned save schema;
- story persistence;
- location;
- party placeholder;
- event state;
- route state;
- memory state.

Success condition:

Close and reopen game without losing narrative consistency.

---

# Phase 5 — Audio foundation

Implement:

- music manager;
- intro + loop support;
- crossfade;
- ambience;
- bus routing;
- track metadata.

Success condition:

A track can play intro once and loop seamlessly across a scene.

---

# Phase 6 — Chapter I vertical slice

Recommended first substantial playable slice:

- observatory / youth environment;
- Belium/Cynthia interaction;
- one exploration segment;
- NPC dialogue;
- one story choice;
- one map transition;
- one cinematic event;
- music loop;
- save/load.

Do **not** attempt the entire 3+ hour chapter at once.

---

# Phase 7 — Pokémon data model

Implement only what the first battle prototype needs:

- species data;
- stats;
- moves;
- types;
- level;
- HP/status;
- trainer team;
- simple party.

Use data-driven Resources.

---

# Phase 8 — Battle prototype

Implement:

- turn structure;
- move selection;
- damage;
- fainting;
- switching;
- simple AI;
- animated sprites.

Success condition:

One authored trainer battle can complete and return to the overworld.

---

# Phase 9 — Battle expansion

Add progressively:

- abilities;
- held items;
- status;
- double battles;
- better AI;
- Mega Evolution;
- boss modifiers;
- special Giratina/Necrozma mechanics.

---

# Phase 10 — Chapter I production

Build:

- young Belium route;
- young Cynthia route;
- Gym-linked story progression;
- Dragonair event;
- rain/Houndour aftermath;
- Zubat/Bagon material;
- fifth-badge boundary;
- first major time skip.

---

# Phase 11 — Chapter II production

Build:

- Cynthia mythology arc;
- 2.5-year search structure;
- Corvisquire scene(s);
- eighth badge;
- five-year transition;
- Lucas/Maya entry;
- Mt. Coronet anomalies;
- Team Galactic escalation;
- stronger Gym encounters;
- Veilstone HQ;
- Mega Metagross → Crobat battle structure.

---

# Phase 12 — Chapter III production

Build:

- Spear Pillar;
- Dialga/Palkia;
- Giratina intervention;
- Distortion World;
- time-distortion storytelling;
- Cyrus relationship with Giratina;
- protagonist route choice;
- Cyrus boss;
- Giratina boss;
- Solgaleo/Lunala arrival;
- Necrozma fused boss;
- Ultra Necrozma;
- collapse;
- Darkrai evacuation;
- Cyrus death.

---

# Phase 13 — Postgame

Build Darkrai memory system:

- location-based triggers;
- memory presentation;
- Pokémon origin memories;
- northern Sinnoh;
- Mega Houndoom first Mega;
- avoiding Cynthia;
- diary;
- yellow moon bookmark;
- final closure.

---

# Phase 14 — Polish

- balancing;
- AI tuning;
- audio finalization;
- animation;
- cinematic timing;
- performance;
- save migration;
- localization if used;
- accessibility;
- bug fixing;
- asset audit;
- legal/IP distribution review.
