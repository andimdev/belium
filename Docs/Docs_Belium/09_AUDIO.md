# Belium — Audio and Music

# 1. Music direction

The project owner prefers music associated with **Pokémon Brilliant Diamond / Shining Pearl** over relying only on original DS Diamond/Pearl audio.

Music is expected to loop continuously in typical Pokémon fashion.

---

# 2. Runtime formats

Current workflow direction:

- keep FLAC as archival/master source where available;
- convert runtime music to OGG Vorbis;
- WAV is appropriate for short SFX;
- MP3 can be used, but OGG is preferred for game music workflow.

FLAC source files may not import natively as expected in Godot, hence conversion.

---

# 3. Loop structure

Many tracks have:

```text
INTRO
↓
LOOP START
↓
LOOP SECTION
↓
return to LOOP START indefinitely
```

The intro should play once.

The loop should not restart from the beginning unless intended.

Each track should record:

- file;
- scene/use;
- loop-start time/sample;
- loop-end time/sample if necessary;
- bus;
- volume;
- notes.

---

# 4. Audio tracking sheet

Recommended spreadsheet columns:

- Track ID
- Track name
- Source/master
- Runtime file
- Narrative use
- Scene/location
- Intro duration
- Loop start
- Loop end
- Bus
- Base volume
- Alternate versions/stems
- License/provenance notes
- Implementation status

---

# 5. Audio buses

Suggested Godot buses:

- `Music`
- `SFX`
- `UI`
- `Ambience`
- `Voices`

Additional buses can be added later for cinematic layering.

---

# 6. Narrative variants of the same theme

A major creative direction is to reuse the same musical identity in different emotional forms.

Example concept:

- early Belium/Cynthia encounter: soft piano;
- later version: fuller arrangement;
- darker Cyrus transformation;
- final/restored variation near redemption.

This can create musical continuity between character eras.

---

# 7. Stems

Discussed approach:

```text
theme_piano.ogg
theme_strings.ogg
theme_choir.ogg
theme_percussion.ogg
```

All stems:

- same length;
- same tempo;
- same loop points;
- start in sync.

Godot can crossfade/layer them in real time.

Potential narrative use:

- add strings when Cynthia enters;
- remove layers for isolation;
- introduce ominous layers around dimensional phenomena;
- evolve a theme without restarting it.

This is a strong design option, not a mandatory requirement for every song.

---

# 8. Stem separation tools discussed

Free/community tools discussed:

- Ultimate Vocal Remover (UVR)
- Demucs
- MIDI community recreations
- MuseScore

Important limitation:

AI stem separation is imperfect, especially on complex orchestral mixes.

For clean rearrangements, high-quality MIDI/community transcriptions can be more flexible when legally/ethically appropriate.

---

# 9. MIDI workflow concept

If a reliable MIDI recreation exists:

```text
MIDI
→ MuseScore / DAW
→ mute/re-orchestrate instruments
→ export stems or full mix
→ OGG
→ Godot
```

Possible uses:

- piano-only Cynthia/Belium version;
- dark orchestral Cyrus version;
- final transformed motif.

---

# 10. Leitmotif concept

Discussed thematic possibility:

- Belium motif;
- transformed Cyrus version;
- emotionally restored/final version.

Astronomy imagery and music can reinforce each other.

This remains an artistic direction rather than locked score design.

---

# 11. Audio player types

General Godot direction:

- `AudioStreamPlayer` — menus/global music/UI;
- `AudioStreamPlayer2D` — positional 2D map audio;
- `AudioStreamPlayer3D` — only if 3D content eventually requires it.

---

# 12. Copyright / IP

Pokémon soundtrack redistribution carries copyright/IP risk.

Do not assume that possessing or finding a track means it can legally be distributed in the final game.

Keep master/source and runtime provenance documented.
