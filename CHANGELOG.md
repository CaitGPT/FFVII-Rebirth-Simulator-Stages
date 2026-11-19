# Changelog

## 1.2.0 (2026-11-19)

- **Midgar Outskirts**: the rocky ground outside Sector 5's wall where Zack fights Shinra's soldiers in the prologue,
  with its fires, fences, the plate overhead and the reactor, under the prologue's sky. It stands on its own ground and
  has room for every summon course except Phoenix's. Offered from the start. The downed helicopters from that fight are not included:
  the story places them, and the mod cannot load their model.

## 1.1.0 (2026-11-18)

- **Gilgamesh's Garden**: the garden where Gilgamesh holds his legendary trials. Unlocks once Gilgamesh's quests are complete.
- **Shinra Manor**: the basement where the Galian Beast is fought, with its props, its own floor and walls, and the
  floor door closed as in that fight.
- **Mythril Mine**: where the Mythril Golem is fought, lit by the mine's own light levels and the mountain cave sky.
- **Cave of the Gi**: where Gi Nattak is fought.
- Stages of more than 64 levels load and unload in full: the mod asks the helper for them in batches. Before, leaving
  a very large stage could leave its sky loaded, which turned later stages white.
- No invisible walls or floor: the simulator's hidden pillars and walls no longer collide on any stage, and on the
  three interiors (Mythril Mine, Cave of the Gi, Shinra Manor) its flat floor goes too, so they
  stand on their own floors and end at their own edges.
- Cave of the Gi: its lit walls and the rest of its parts, from the levels the game itself loads there.
- Faster: levels stream in and out with larger per-frame budgets while a stage loads or unloads, and a stage unloads
  after the game is back at the course list. Leaving the largest stage tried (77 levels) went from 59 s to 48 s back to the course list
  (the plain simulator takes 43 s); the Cave of the Gi is in about 3 s sooner.
- No flicker on arrival: a stage now arrives behind a black screen of the game's own, lifted once it is fully in
  and set up. The simulator never shows on the way. The largest stage tried is on screen at about 17 s after confirming,
  against about 27 s before; small stages are unchanged (about 12 s).
- Shinra Manor and Cave of the Gi: lit by their regions' skies (Nibelheim's night, the mountain cave), which light
  their walls and sides as in their boss fights.
- Fewer crashes: the mod no longer checks objects the game may already have destroyed, which crashed the game inside
  UE4SS. Everything kept for a visit is dropped when the next one starts, and the simulator's levels, which the game
  can replace while it loads, are looked up again by name every time.
- Summon courses: tested on the stages with all six summon fights (Titan, Phoenix, Alexander, Kujata, Bahamut Arisen,
  Odin), with the stage kept for every round of a course.
- After a visit the stage unloads in the background at the game's own pace, with its memory freed a little at a time.
- A stage's lights now always wait until the simulator's own lighting is hidden. Before, a stage that loaded very
  quickly could occasionally look dull.

## 1.0.0 (2026-11-17)

First release.

- Choose a stage for any Combat Simulator course after selecting it, in the game's own choice window. The choice is
  remembered per course.
- Two stages from the final battle: **Edge of Creation** (fitted to the simulator's arena, with its floating rocks) and
  **Inside the Lifestream**. Both unlock once the game is finished.
- All simulator courses can use them, including the Combat Training tutorials and Training Dummy's three courses; the
  eight Shinra Manor courses are left as they are.
- A native helper loads the stage's levels; it switches itself off on game builds it does not recognise.
- Tested on the Epic Games Store version of game version 1.005.
