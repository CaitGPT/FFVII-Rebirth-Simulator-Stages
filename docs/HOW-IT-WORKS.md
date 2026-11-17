# How it works

Reference for modders: what the mod does at each step, what it relies on, what was tested and what is known not to
work. The story of how we got here is in [HOW-WE-BUILT-IT.md](HOW-WE-BUILT-IT.md); each live session is in
[LIVE-RESULTS.md](LIVE-RESULTS.md); what the game's files show is in [research/VR-STAGE-AND-ARENAS.md](research/VR-STAGE-AND-ARENAS.md).

## The simulator's stage

The Combat Simulator's arena is not a map of its own. Each continent's world holds one streaming volume labelled
`COMMON_VR`, which streams the level `0000-COMON_VR` into the open world at the volume's `TargetLocation`: far off the
map and high in the air (east continent (-200000, -100000, 60000), west (-200000, -100000, 10000)). The level's origin
is the centre of the arena and its floor is at z = 0. The fight itself (territory, cameras, navigation and 264 named
points that enemy scripts use) belongs to that level and its sub-levels, so it stays where it is whatever we show
around it. The playable area is a circle of 24.4 m radius (measured: the party's capsule stops there in every
direction).

What makes the simulator look like the simulator:

| Part | Where |
| --- | --- |
| Floor, pillars and walls | Five actor classes (`BG0342_00_Floor_VR_C`, `BG1127_0x_BlockPillar_Standard_C`, `BG1128_0x_BlockWall_Standard_C`) in `0000-COMON_VR_Terrain_Strip` |
| The block skyline | The terrain level's massive-environment component (hiding the actors does not hide it) |
| Low blocks round the rim | Collision only, through the terrain level's `Spl_CST` collision actor |
| Lights and effects | The streaming levels `0000-COMON_VR_Light` and `0000-COMON_VR_Effect` |
| Sky | `0001-WORLD_VRSky` (`0001-WORLD_VRSky_Low` on low settings) |

## A visit, step by step

1. **Course selected** (`EndColosseumMenu:OnCourseMenuPressedItem`). The mod reads the course's title from the menu,
   which holds the text id (`$menu_Colosseum_CourseTitle_...`), and finds the course in `stage_data.lua`. It lists
   the stages the course can use and opens the picker: the game's own choice window
   (`UEndMenuAPI.ShowMessageWindow`). With fewer than two options it shows nothing.
2. **Course confirmed** (`OnYesButtonPressed`). The mod writes one load request per level of the chosen stage for the
   native helper. Each level is loaded as a new instance named `SimStage_<stage>_<n>_<height>_<visit>`, placed so the
   stage's anchor lands on the simulator's centre.
3. **Loading screen.** The party "arrives" when the game's in-simulator flag turns on, 5 to 9 s after the confirm. The
   screen stays black for about another 4 s (first visit: about 17 s from the confirm; later visits about 13 s).
   Behind it, once the package loader has been idle for a second:
   - the stage is stretched if it has a `fit`, and its hidden meshes are shown;
   - the simulator's floor, blocks, skyline and rim collision are found and hidden as soon as its floor exists;
   - the stage's lights wait until none of the simulator's lighting levels is showing (see Lighting below).
4. **The simulator's lighting.** Its lighting, effect and sky levels are told to hide on the first tick on which the
   game has loaded and shown all three. Telling one to hide while the game is still bringing it in can stop the start
   on the "Get Ready" screen.
5. **Leaving.** When the in-simulator flag has been off for 3 s, the mod asks the helper to unload every instance and
   shows the simulator's look again from the references it kept, without searching.

Every `FindAllOf` costs about 0.2 s on this game, whatever the class, because it walks the whole object table. The
mod makes all of its searches behind the loading screen and keeps references; from the swap on it only flips kept
objects.

## Lighting

A streamed stage arrives with parts switched off, because the game's own scripts switch them on during the boss fight:

| Arrives hidden | Shown by the mod |
| --- | --- |
| The sky level's sun and fog | `DirectionalLight`, `ExponentialHeightFog` |
| The light level's ambient light, reflection capture and fog volume | `PrecomputedLightEnvironmentActor`, `SphereReflectionCapture`, `VolumetricFogInjectionVolumeActor` |
| Some stages' meshes | the classes in the stage's `show_classes` |

Never shown: collision-only meshes (`CL_...`) and anything in the stage's `keep_hidden`.

The order matters. If the stage's lights come on while the simulator's own lighting levels are still showing, the
scene stays dull after those are hidden (seen on Inside the Lifestream). The mod switches the stage's lights on only
while none of the simulator's lighting levels is visible, or after 12 s regardless.

## The stages

`data/stages.json` describes each stage; `tools/build_lua_data.py` writes it into `Scripts/stage_data.lua`.

| Field | Meaning |
| --- | --- |
| `levels` | Level packages to load, in order |
| `sky_level` | Loaded last; when a stage brings a sky, the simulator's sky is hidden |
| `anchor` | The point in the stage's own coordinates that lands on the simulator's centre: the arena's centre at the height of its ground |
| `radius_m` | Clear radius the stage offers; a course is offered the stage if its enemies need no more |
| `show_classes`, `keep_hidden` | See Lighting |
| `fit` | Stretch along X and Y about the arena's centre, and which actors to stretch, move or leave alone |
| `unlock` | A story flag, a chapter progress, or the game finished |
| `experimental` | Not offered unless the `experimental` setting is on |

### Edge of Creation (`space_rock`)

Levels: `3120-CAPTL_Sephiroth_1Cosmo_Terrain_Strip`, `_Light`, `_Gimmick`, `_Effect`,
`3120-CAPTL_34Sephiroth1CosmoNatureMini_Terrain_Strip` and the far-land level
`LastBattle/FarLand/3120-CAPTL_Sephiroth_1Cosmo_Terrain_FarLand`. Sky: `0001-WORLD_IslandSky_Space`.

- The platform is the skeletal ground piece `BG2130_00` plus 39 ground meshes in the Gimmick level, all arriving
  hidden. Its walkable top is 98 to 134 cm above the level's z = 0, so the anchor height is 110.
- Its level top, read from the mesh file (`tools/rock_outline.py`), is an irregular oval of about 52 m by 35 m.
  `tools/rock_fit.py` finds the smallest stretch that puts level rock under every metre of the arena: 1.08 along X and
  1.70 along Y about the top's centre. Heights are left alone.
- The floating rocks are the far-land mesh (the whole island and the rocks round it, low detail) and four rock
  effects. They keep their true size and place. The far-land mesh carries a low-detail copy of the platform that would
  poke through the real one, so it is lowered by a metre.
- Cutscene props (`Quest_...`) stay hidden.

### Inside the Lifestream (`lifestream`)

Levels: `3120-CAPTL_Sephiroth_6LastSpace_Terrain_Strip`, `_Light`, then the sky level `0001-WORLD_OtherSky_White`, and
the sky `0001-WORLD_IslandSky_Galaxy`.

- The floor is 25 water meshes that arrive hidden, flat at z = 100 (the anchor height).
- The battle's sky is the Galaxy sky (the game's cutscene table names it for the scene tied to these levels). On its
  own it is too dark; loading the white sky level first, with its own sun and fog kept hidden, gives the look of the
  real fight. Of the Galaxy sky's ten fog variants only the centre one is shown.
- Its far-land level is not loaded: it is a flat water plane up to 40 cm above the floor.

### Planned stages that do not work yet

The six regional boss arenas and seven story-boss arenas are in `data/stages.json` with `experimental: true`. Streamed
to the simulator, their ground does not appear: it is the game's open-world (massive-environment) terrain, which did
not draw at the new place when we tried Nibel. Their skies are regional skies with many local fog volumes. Moving the
simulator to the arena instead (`route = move`, writing the arena's position into `TargetLocation`) was ignored once
the simulator had been visited; a first visit after starting the game is untested.

## The native helper

UE4SS 3.0.1's Lua cannot call `LevelStreamingDynamic.LoadLevelInstance` on this game (its `bool` out-parameter breaks
the argument stack), so a small C++ UE4SS mod does the loading. Lua and the helper talk through files in the mod's
folder:

| File | Written by | Holds |
| --- | --- | --- |
| `stages-helper.txt` | helper, twice a second | its tick, whether its checks passed, whether the package loader is busy |
| `stages-request.txt` | Lua | `load`, name, package, x, y, z, yaw; or `unload`, name |
| `stages-ack.txt` | helper | name, `loaded`, `unloaded` or `refused`, and a reason |

The helper serves one request per frame from a game-thread safe point, loads only while the package loader is idle
(or after 8 s), and unloads with `SetIsRequestingUnloadAndRemoval`. Its game-thread check, code-byte checks and
loader-idle check are copied from our Junon Colosseum helper by `tools/make_helper_source.py`; they know two game
builds (the January 2025 Steam build and 1.005 on the Epic Games Store) and switch the helper off on any other.

## Courses

`data/courses.json` (from the game's tables, by `tools/make_courses.py`) gives each of the 75 simulator courses its
title id, English title and the radius its enemies need: 12 m for ordinary rounds, up to 28.3 m for Phoenix. Courses
other mods add are in `data/mod_courses.json` (Training Dummy's three). The eight Shinra Manor courses (`_NIBLS_`) are
left out; they use the same simulator level through another content volume.

## Files the mod writes

In `ue4ss/Mods/SimulatorStages/`: `choices.txt` (the stage chosen for each course), `stages-log.txt` (what it did on
each visit, with times), and the three helper files above. Nothing goes into the save.

## What was tested

On FINAL FANTASY VII REBIRTH 1.005 (Epic Games Store), UE4SS 3.0.1 with our 1.005 fix, a save that has finished the
game. Fights were driven by a test harness with the game's Classic mode, and by the owner by hand.

- Both stages through the picker, many times, on Grasslands courses and the Training Dummy DPS course, solo and with a
  party of three, with a summon (Odin) called on Edge of Creation; levels released on leaving every time.
- Movement on both stages; ground heights measured by dropping the party's capsule on a grid.
- The swap: one screen frame a second from the confirm on a first visit.
- Six visits in a row in one session after the "Get Ready" fix.
- Inside the Lifestream's lighting on a first and a later visit after the lighting-order fix.

Not tested: the Steam version, other UE4SS builds or settings, a save that has not finished the game, the tutorial
courses, controller input in the picker, and playing the game's own Chapter 14 fights with the mod installed (the mod
acts only on Combat Simulator visits and only on its own copies of the levels).
