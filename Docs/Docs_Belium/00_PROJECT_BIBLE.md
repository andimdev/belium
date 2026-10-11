# Belium — Project Bible

## 1. High concept

**Belium** is a narrative-driven Pokémon fangame centered on the intertwined origin stories of **Cyrus** and **Cynthia**.

The project does not aim to merely retell Pokémon Platinum. Its purpose is to create a long-form prehistory and reinterpretation that explains:

- who Cyrus was before becoming Cyrus;
- why Belium disappeared;
- how Cynthia grew from a young trainer into the woman known in the canonical era;
- how their friendship, separation, and later confrontation shaped both of them;
- how the events of Platinum acquire a different meaning when seen through several perspectives;
- how Giratina and Necrozma fit into a larger dimensional story;
- why Cyrus's final act becomes a sacrifice rather than an escape.

The emotional thesis is not that Cyrus is absolved of everything he did. The story instead seeks to make the player understand the person behind him.

## 2. Core narrative rule

> **Decisions change the path, information, and experience — not the final destiny.**

The game contains route bifurcations, multiple playable protagonists, exclusive dialogue, exclusive scenes, conditional flashbacks, different knowledge states, variable battle conditions, and different Cyrus team configurations.

However, the ending is fixed:

> **Cyrus/Belium dies.**

There is no alternate survival route.

## 3. Structural identity

Belium is best described as:

- a branching-but-convergent narrative;
- a multi-protagonist Pokémon RPG;
- a character study of Cyrus and Cynthia;
- a prequel/reinterpretation that eventually intersects with Platinum;
- a game in which repeated playthroughs can reveal different information;
- a story whose postgame completes missing pieces rather than changing the ending.

## 4. The three main chapters

### Chapter I — Youth / rupture

Primary era:

- Belium: 16 years old.
- Cynthia: 14 years old.

The chapter contains at least ~3 hours of story content excluding combat, leveling, exploration overhead, and optional content.

Playable perspective can include:

- young Belium;
- young Cynthia.

The central rupture is the death of Belium's Dragonair.

The chapter continues beyond the death long enough to establish the consequences, Belium's disappearance, and Cynthia's progression before the first major time skip.

### Chapter II — Search / transformation / Platinum approach

After the Chapter I period:

- a four-year time skip occurs;
- Cynthia has spent time studying Sinnoh mythology;
- she follows traces/pistas related to Belium/Cyrus but cannot find him;
- this search/investigation period spans ~2.5 years;
- the closest she gets is seeing a **Corvisquire** watching her from the top of a tree;
- after obtaining her eighth badge, she enters intense League training;
- another five years pass;
- the story then moves to Lucas/Maya in the era approaching the familiar Platinum storyline.

This preserves enough elapsed time for:

- Cyrus ≈ 28 years old;
- Cynthia ≈ 26 years old.

### Chapter III — Distortion / revelation / sacrifice

Cyrus attempts to create his new world by controlling Dialga and Palkia.

Giratina drags Cyrus into the Distortion World.

The chapter explores:

- Cyrus's relationship with Giratina;
- unusual time behavior in the Distortion World;
- subtle signs of Necrozma;
- a major battle against Cyrus;
- a boss battle against an exceptionally boosted Giratina;
- Necrozma's reveal;
- Solgaleo/Lunala;
- Necrozma's fused form;
- Ultra Necrozma;
- dimensional collapse;
- Cyrus's final sacrifice;
- Darkrai evacuating the survivors.

## 5. Postgame identity

The postgame is not intended to undo the ending.

It acts as **historical reconstruction**.

Darkrai leads the player through physical locations in Sinnoh and enables memories/flashbacks from Belium/Cyrus's missing years.

Important postgame material includes:

- how Belium met several of his Pokémon;
- the first battle in which Houndoom Mega Evolves;
- adventures in northern Sinnoh;
- how Cyrus repeatedly avoided being found by Cynthia;
- other missing events from the years between Belium and Cyrus;
- Cynthia finding Cyrus's personal diary;
- the diary still carrying the name **Belium** on the cover;
- the yellow moon-shaped bookmark Cynthia gave Belium when they were young.

## 6. Emotional anchors

The story repeatedly contrasts what Cyrus says with what his relationships prove.

Examples:

- Crobat's evolution requires friendship.
- Houndoom is emotionally irreplaceable to him.
- Darkrai follows him without ownership.
- Corviknight connects directly to the years in which he watched Cynthia from afar.
- Gholdengo can symbolize the act of treasuring things of value despite denying attachment.
- Cyrus tries to reject emotion while continuing to protect the beings he values most.

## 7. Giratina and Necrozma

### Giratina

Giratina is **not the hidden villain**.

It is:

- an observer;
- fascinated by Cyrus;
- interested in Cyrus as an unusual and potentially useful person;
- eventually connected to Cyrus during the Distortion World arc;
- aware that something else is wrong;
- capable of noticing signs of Necrozma.

### Necrozma

Necrozma is the hidden larger threat.

Its presence should be foreshadowed long before the reveal.

In Chapter I, a mysterious Pokémon can be seen through dark dimensional cracks during important events. The presentation should encourage the player to assume Giratina is responsible.

Later, the player learns that the observer/force behind those signs was Necrozma.

## 8. Belium's visual identity

Young Belium is visually distinct from adult Cyrus.

Confirmed traits:

- black, medium-length hair;
- bangs/fringe covering or partially covering the eyes;
- introverted presence.

## 9. Production pillars

1. **Narrative clarity**
2. **Multiple perspectives**
3. **Strong character continuity**
4. **Cinematic presentation beyond DS-era limitations**
5. **Animated battle sprites**
6. **Data-driven story systems**
7. **Reusable Godot architecture**
8. **A postgame that resolves the story rather than trivializing the ending**

## 10. Current implementation status

Confirmed progress:

- Godot project started.
- Two interfaces already created.
- The project owner knows how to create maps in Godot.
- A large TileSet is being assembled with Pokémon Centers, shops, houses, bridges, and other world assets.
- Young Belium custom sprite work has begun.
- A spreadsheet already tracks mechanics/dynamics, map events, locations, and other production items.
- Figma is being considered as a visual production bible for screens, maps, sprites, cinematics, and references.
- Cyrus's principal team and four alternate/repechage Pokémon are defined.

## 11. Technical direction history

Approaches discussed before choosing Godot:

- Pokémon Platinum / White 2 ROM hacking;
- `pret/pokeplatinum` decompilation;
- extending DS-era systems with animated sprites / Mega Evolution / Ultra Beasts;
- custom desktop/Android engine approaches;
- RPG Maker XP + Pokémon Essentials;
- Godot.

Godot was preferred because:

- it is free;
- it offers a modern 2D workflow;
- it supports desktop/Android targets;
- it allows cinematic systems beyond original DS constraints;
- it suits a programmer comfortable with architecture and modular systems.

## 12. Source-of-truth rule

This repository's Markdown documentation should become the source of truth for the project.

Memory in ChatGPT/Codex is useful, but narrative canon and implementation contracts must live in version control.
