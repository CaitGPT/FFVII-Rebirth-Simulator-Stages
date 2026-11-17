# FFVII Rebirth Simulator Stages

A FINAL FANTASY VII REBIRTH PC mod that lets you fight Chadley's Combat Simulator courses on other stages. Pick a
course, choose a stage, and the fight takes place there instead of on the simulator's block arena. Two stages from the
final battle are in this version: **Edge of Creation**, the rock platform among floating rocks in space, and **Inside
the Lifestream**, the still, silver water under a starry sky.

**Spoiler note:** both stages, their names and the pictures of them come from the game's final battle.

An AI coding agent built this mod: Claude (Anthropic), in Claude Code, did the research, wrote the code and tested it
in the game through a test harness. The channel owner set the design and playtested it. [How we built it](docs/HOW-WE-BUILT-IT.md)
tells the story, dead ends included.

## What it adds

- **A stage picker.** When you select a course, the game's own choice window asks you to choose a stage. The first
  option is the normal Combat Simulator. The mod remembers your choice for each course and marks it with `>` the next
  time.
- **Edge of Creation.** The rock platform, its floating rocks and the nebula sky from the final battle. The platform
  is stretched to cover the simulator's arena, a circle of about 24 m radius.
- **Inside the Lifestream.** The water floor and the starry sky from the final battle.
- **Which courses.** Every Combat Simulator course, including the Combat Training tutorials and the three courses our
  [Training Dummy](https://github.com/CaitGPT/FFVII-Rebirth-Training-Dummy) mod adds. The eight Shinra Manor courses
  are left as they are. A stage is only offered for courses whose enemies have room on it; both stages fit every course.
- **Unlocking.** Both stages unlock when you have finished the game (once Chapter Select is open).

Nothing is written to your save. The mod changes no game files: it loads the stage's own levels beside the simulator
while you fight, and removes them when you leave.

## Requirements

- FINAL FANTASY VII REBIRTH for PC, game version **1.005**. We tested on the Epic Games Store version only.
- [RE-UE4SS FF7R](https://www.nexusmods.com/finalfantasy7rebirth/mods/267) (UE4SS 3.0.1) with a fix for game version
  1.005. We tested with our [UE4SS 1.005 Fix](https://www.nexusmods.com/finalfantasy7rebirth/mods/2521).
- The mod includes a small native helper (`dlls/main.dll`) built for that UE4SS. It loads the stage's levels, which
  UE4SS's Lua cannot do on this game. It checks the game code it relies on before acting and switches itself off if it
  does not recognise it: the game and the simulator run normally, but no picker appears.
- A save that has finished the game.

## Install

1. Close the game.
2. Extract the release zip into the game folder, the one that holds `End`. It adds
   `End/Binaries/Win64/ue4ss/Mods/SimulatorStages/` (scripts, the native helper, `enabled.txt` and `settings.txt`)
   and a readme, licence and changelog beside `End`, which you can delete.
3. If `End/Binaries/Win64/ue4ss/Mods/mods.txt` lists `SimulatorStages : 0`, change it to `1`. Otherwise the included
   `enabled.txt` turns the mod on.

## Uninstall

Close the game and delete `End/Binaries/Win64/ue4ss/Mods/SimulatorStages`.

## How to use it

1. Talk to Chadley and open the Combat Simulator.
2. Select a course. The **Choose a stage** window opens.
3. Pick a stage, then choose your team and start as usual.

To change a course's stage later, select the course again. Choices are kept in `SimulatorStages/choices.txt`.

## Settings

`SimulatorStages/settings.txt` is read each time it is needed, so changes take effect without a restart.

| Setting | Values | What it does |
| --- | --- | --- |
| `enabled` | `true`, `false` | `false` leaves the simulator as the game ships it |
| `picker` | `select`, `key`, `off` | When to show the picker: when you select a course; only when you press F7 on a highlighted course; or never (courses use the stage last chosen for them) |
| `require_unlock` | `true`, `false` | `false` offers every stage whether or not you have finished the game |
| `experimental` | `false` | Leave off. `true` also offers the planned arena stages, which do not work yet |

The other settings in the file are for development.

## Known issues

<!-- Keep this list in step with the release notes; remove items as they are fixed. -->
- **The simulator's stage can show for a moment.** On the first visit after starting the game, the new stage is in
  place when the screen first shows a picture. On a later visit in the same session the simulator's own stage may show
  for up to about a second before the swap. We have not captured that case.
- **"Get Ready" screen that never ends.** We found and fixed one cause in the mod. The game can also stop on a black
  "Get Ready" or loading screen in its own simulator fights, without any mod. Restart the game.
- **The edge of Edge of Creation.** The platform is not round. It reaches 0.2 to 6 m past the simulator's invisible
  wall depending on direction, and along part of the south rim characters stand a little above the rock.
- **Game updates.** An update can change the code the native helper relies on. The helper then switches itself off
  and no stages are offered until we update the mod.
- Don't use UE4SS hot reload (Ctrl+R): it crashes this game.

## What is next

The design includes each region's boss arena, unlocked by beating that region's boss, and the arenas of story bosses
such as the Mythril Golem, Gi Nattak, Reno and Rude, and Gilgamesh. They are in `data/stages.json` but do not work
yet: their ground is open-world terrain, which does not show when its level is loaded elsewhere. [How it works](docs/HOW-IT-WORKS.md)
says what we tried.

## Build from source

This repository contains no game files.

- **Scripts.** The Lua mod is in `ue4ss/SimulatorStages/`. `data/stages.json`, `data/courses.json` and
  `data/mod_courses.json` describe the stages and the courses; `python tools/build_lua_data.py` turns them into
  `Scripts/stage_data.lua`. `tools/make_courses.py` rebuilds `data/courses.json` from your own export of the game's
  tables.
- **Native helper.** C++ in `native/`, built against the UE4SS 3.0.1 sources. See [native/README.md](native/README.md).
- **Release zip.** `python tools/make_release.py <version> --dll <built main.dll>`.
- **Tests** run offline: `python -m pip install lupa`, then `python tests/run_tests.py`.

## Documentation

- [How it works](docs/HOW-IT-WORKS.md): the stages, the picker, the native helper, timing, what was tested and the limits
- [How we built it](docs/HOW-WE-BUILT-IT.md): the whole story, dead ends included
- [Test log](docs/LIVE-RESULTS.md): every live session, with what was seen
- [Research](docs/research/VR-STAGE-AND-ARENAS.md): what the game's files show about the simulator and the arenas
- [Changelog](CHANGELOG.md)

## Credits

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) and the FF7 Rebirth build of it on Nexus Mods
- [retoc](https://github.com/trumank/retoc) by Truman Kilen and Archengius, and its FF7R patches, for reading the
  game's level files
- FModel and CUE4Parse, for reading the game's files
- The native helper reuses the game-thread, code-check and loader-idle parts of our
  [Junon Colosseum](https://github.com/CaitGPT/FFVII-Rebirth-Junon-Colosseum) helper
- The Rebirth modding community

## Requests

We take requests: changes to this mod, or ideas for new Rebirth mods. Open an issue here.

## Licence

The source code is MIT licensed ([LICENSE](LICENSE)). The repository contains no game files; the mod loads the game's
own levels from your copy of the game.

FINAL FANTASY VII REBIRTH and its assets belong to Square Enix. This is an unofficial fan project, not affiliated with
or endorsed by Square Enix.
