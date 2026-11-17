# What has been seen in the game

Newest first. Each line is something observed, with where the evidence is. Screenshots and logs are outside Git, in
`D:\FF7RebirthModding\Mods\SimulatorStages\evidence\`.

## 2026-11-17: seventh live session (which courses; the swap at the start of a fight; Epic 1.005, slot 25)

The owner: the tutorial and Training Dummy courses should have the stages too (the Shinra Manor courses stay left
out); and "there's 2 or 3 seconds where the original stage shows, kind of frozen, then our stage loads in".

**Courses**

- The eleven tutorial courses are in scope. Not run in the game yet.
- The three courses the Training Dummy mod adds are recognised (`data/mod_courses.json`): the mod reads the title that
  mod puts on screen ("Training Dummy: DPS"). Seen: the picker opens for it and both stages load
  (`100-dummy-on-edge.png`).
- The eight Shinra Manor courses stay left out. They use the same simulator level through another content volume
  (`VRContentNIBLS`) and another flag, and have not been tried.

**The swap**

- **Every object search costs about 0.2 s** (`FindAllOf` walks the whole object table: 160 to 210 ms for each of 13
  classes tried, whatever the class). The mod made eight at the moment it hid the simulator's look, which froze the
  screen on the simulator's stage for about two seconds, and eight more for the repeat "show" five seconds into the
  fight.
- **What the game does on the way in**, from the mod's log and one screen frame a second: the party "arrives" (the
  flag flips) about 5 to 9 s after the course is confirmed; the screen is black until about 4 s after that (17 s after
  the confirm on a first visit, 13 s on a later one); the simulator's lighting, effect and sky levels only exist 3 to
  7 s after arrival.
- **Now:** the stage's own parts are stretched and shown as soon as its levels are in and the loader is idle; the
  simulator's scenery (floor, pillars, walls, skyline, rim collision) is found and hidden as soon as its floor exists
  (one cheap search a second asks); its lighting, effect and sky levels are told to hide on the first tick the game
  has all three showing, from kept references; the repeat show re-shows kept actors. No search happens after the
  loading screen.
- **Seen on a first visit** (`103-entry-*.png`): black through second 16, and the first frame with a picture already
  shows the Edge of Creation with its rocks. The mod had finished 13 s after the confirm. The simulator's stage never
  appears.
- **Not seen on a later visit.** By the log the mod finishes about 5 s after arrival there and the plain simulator's
  first picture comes about 4 s after arrival, so up to a second of the simulator's look may still show. The harness
  refused taps on and off for the rest of the session (its telemetry samples were just over its 2 s age limit; a
  video encode was running), so no clean capture was made.
- **If more is wanted:** the remaining cost is the eleven or so searches for the stage's own actors. Their names are
  fixed by the level files, so the mod could look each one up by its full name (a hash lookup, no walk) from lists
  made offline. Not built.
- The "Get Ready" protection is unchanged in substance: nothing tells one of the simulator's levels to hide before
  the game has shown it. Hiding its actors early changes no level's state.

### Added the same evening: "the Lifestream stage seemed a bit dull again" (owner)

- The visit the owner found dull (19:12) loaded everything: four levels, 31 hidden parts shown. What differed is
  order. Its log has the stage's lights switched on at 19:12:34 with the simulator's own lighting levels already
  showing, and those hidden at 19:12:36. On the visits that looked right the stage's lights came on before the
  simulator's lighting levels existed (18:47, 19:36: 7 to 9 s before) or after they had been hidden (every visit
  before the swap was reordered, including the one the owner called a perfect match at 18:13).
- So since the reorder the look depended on timing: a visit where the simulator's lighting is already up when the
  stage's lights go on (typical of a later visit in one game session) comes out dull.
- **Change, tried in the game the same evening:** the stage's meshes are still shown as early as possible, but its lights
  (sun, fog, ambient light, reflection capture, fog volume) are switched on only while none of the simulator's
  lighting levels is visible: at once if none is, otherwise the moment they have been hidden; after 12 s they go on
  regardless. This rests on three visits with a known look, one of them dull.
- **Tried (19:50 and 19:53, through the picker, Grasslands course):** a first visit after a restart (the stage's
  lights came on at once: the simulator's lighting was not showing yet) and a later visit in the same session (log:
  `activate 25  lights wait: 6`, then `lights 6` the same second the simulator's levels were hidden). Both looked like
  the owner's reference: pale silver water, stars (`117-ls-fix-first.png`, `119-ls-fix-later.png`).
- No setting was involved. `force_stage` and `picker`, which I change for scripted runs and put back, only decide
  which stage is used and whether the picker opens.

## 2026-11-17: sixth live session (the Lifestream's sky; Epic 1.005, slot 25)

The owner: the sky of Inside the Lifestream is not right, the real one has sparkles; later, with a reference
screenshot of the real battle (pale silver water, stars and a galaxy cloud overhead), "the floor got raised, we're
wading in it".

- **The battle's sky is the Galaxy sky.** The game's cutscene table (`CutSceneList`, 8800-FOREE) names
  `0001-WORLD_IslandSky_Galaxy` as the sky of `EV_FOREE_8790`, the scene tied to this battle's levels.
  `OtherSky_White` was my guess; it has no stars.
- **The Galaxy sky alone is too dark.** Loaded as the stage's only sky it gives a dim green-grey scene with stars.
  The look of the reference came only with the white sky level loaded first (its own sun and fog kept hidden) and the
  Galaxy sky after it: silver-grey water with reflections and stars overhead (`97-lifestream-two-skies.png`).
  Which of the white level's parts does this was not isolated; the load order is what the stage now fixes.
- **The Galaxy sky has ten fog variants** (centre, "olg", eight "side"); only the centre one is shown. The others were
  not tried.
- **The Lifestream's FarLand level must not be loaded.** It is a flat water plane (35 vertices, 560 m across) lying up
  to 40 cm above the floor. With it the floor turns flat green and the party wades (owner; `90-...png`). I had added
  it by analogy with the Edge of Creation without checking where its surface lies inside the arena, only where its
  vertices are.
- Its Effect level is empty. Its Sound level (not loaded) probably holds the battle's ambience.
- Scripting note: Git Bash rewrites an argument that starts with `/Game/` into a Windows path; set
  `MSYS_NO_PATHCONV=1` when passing package paths on the command line.

## 2026-11-17: fifth live session (the "Get Ready" hang; Epic 1.005, slot 25)

The owner: "sometimes it lingers forever on the Get Ready screen".

- **What the log shows.** Two visits ended with the game being closed and no fight (15:47 and 16:42). Both were a
  later visit in one game session, both read `settled 1 s` or `2 s after arrival` and `dressing 20` where every visit
  that worked reads 4 to 9 s and `dressing 21`. The mod had acted before the simulator had finished coming in.
- **Why it acted early.** "Settled" meant "the package loader has been idle for 2 s". On a later visit the
  simulator's levels are cached, the loader never gets busy, and that is true from the first second.
- **What the game does on the way in** (measured with `tools/live/probe_sim_levels.lua` and the arming probes): the
  in-simulator flag flips before any of the simulator's own levels exist; its lighting and sky levels appear about a
  second later, not yet loaded; its effect level comes last; it destroys and recreates them on every visit.
- **Telling a level not to be visible before the game has shown it holds up the start.** Done to the lighting and sky
  levels at first sight, the fight took 15 s to start where it takes 8, and the game had re-shown them by then.
  A permanent hang was not reproduced on demand in six tries (the timing window is short and varies).
- **Fix.** The mod touches nothing of the simulator's until the game has loaded and shown all three of those levels
  and that has held for two seconds (`game.simulator_shown`, `SHOWN_FOR`), and it never tells a level that is not
  visible to hide. If they have not all shown 20 s after arrival the log says `waiting` and how many exist.
- **After the fix:** six visits in one game session through the picker, alternating Edge of Creation and Inside the
  Lifestream, all reached their fights; each reads `settled N s after arrival, shown for 2 s`, `dressing 21`.
- Also learnt: searching for objects every 100 ms during the load slowed it badly (a fight took 34 s to start).
  The mod's own check runs once a second and only with the loader idle.
- Not proven: that this was the only cause. If it happens again, the last lines of `stages-log.txt` now say what the
  mod was waiting for.

## 2026-11-17: fourth live session (names, a closer fit, the floating rocks; Epic 1.005, slot 25)

The owner: fit the rock to the arena exactly if possible; add the real floating rocks in their right places; name the
stages "Inside the Lifestream" and "Edge of Creation".

- **Names.** `lifestream` is "Inside the Lifestream", `space_rock` is "Edge of Creation", and "Arena" is capitalised in
  the others.
- **The rock's true shape comes from its mesh file.** `tools/rock_outline.py` reads the vertices of the cooked
  skeletal mesh `BG2130_00` (312,548 of them; its extents match the bounds read in the game). The platform is an
  irregular oval of about 52 m by 35 m with cracks between its five fragments and a sloping rim.
- **It cannot match a circle exactly, but it can be close.** `tools/rock_fit.py` finds the centre and the stretch
  along X and along Y for which every metre of the arena's 24.75 m circle has level rock under it, with the least
  rock left over: centre (0, -75) in the mesh's coordinates, 1.08 by 1.70. Level rock then reaches 0.2 to 6 m past
  the wall depending on the direction (one stretch for both directions would need 1.70 and leave up to 22 m).
  Through the mod: `fit 47`; rock under all four rim points (`75-final-*.png`).
- **The floating rocks are two things**, both now loaded at their true size and place:
  the `FarLand` level (one low-detail mesh, 9,622 vertices, 520 m by 440 m, of the whole island and the rocks about
  it), which the stage never loaded, and four hidden rock effects in the Effect level, now shown.
- **The far-land mesh includes a copy of the platform** that reaches 46 cm above the floor inside the arena. It is
  lowered a metre (`fit.keep`), which puts it under the real platform; beyond the platform it stands in for the
  island's northern terrain, which is massive-environment terrain and does not show when streamed.
- **A summon works on a streamed stage**: Odin was called during the fight on the Edge of Creation
  (`72-far-lowered-135.png`).
- Dead ends: the ground piece has only 14 bones (five fragments), so bones do not trace its shape; the visible meshes
  have no collision, so nothing dropped or swept can find their edge.
- **My mistakes this session.** (1) A probe called `SetCollisionProfileName` with one argument where it takes two;
  UE4SS raised an error mid-probe, after the probe had switched collision off, and the game had to be restarted.
  Probes that change state now restore it inside `pcall`. (2) I ran probes that move the leader without checking the
  fight had started; they ran in the open world and left Cloud hanging over the sea. Check `in_battle` and the
  leader's position first. (3) The owner had restarted the game and was playing while I changed its settings file.
- Left: at the south rim the rock's collision is 30 to 50 cm below the floor for the last few metres, so characters
  stand on the simulator's floor just above the rock there.

## 2026-11-17: third live session (the rock's invisible floor; Epic 1.005, slot 25)

The owner: "the rock stage has quite a big chunk of invisible floor".

- **The arena is a circle of 24.4 m radius.** The leader's capsule swept outwards from the centre stops at 2440 cm in
  all 24 directions tried.
- **The rock's visible slab is about 51 m by 33 m and sat 7.5 m south of the arena's centre**, so the northern third
  of the arena had no rock under it. Read from the bounding boxes of its 39 visible meshes and its skeletal ground
  piece (`tools/live/probe_footprint.lua`); confirmed by standing Cloud at rim points, where he hung in space beside
  the rock (`64-rim-000.png`, `64-rim-270.png`).
- **Its collision is not its outline.** The rock's terrain collision reaches well north of anything visible, so the
  height map (a capsule dropped on a grid) showed ground where there was nothing to see. My first fix, centring on
  the collision, moved the rock the wrong way. Measure the visible meshes for coverage and the collision for footing.
- **Fix: centre on the visible slab and stretch it 1.8 times sideways** (`fit` in `data/stages.json`,
  `game.fit_stage`). Each mesh and collision actor moves to centre + 1.8 x its offset and its X and Y scale are
  multiplied; heights are left alone, so bumps do not grow. Static actors are made movable first, or the engine
  refuses to move them. All 50 actors moved.
- **Through the mod** (`fit 50`, `activate 44`): ground within about 24 cm of the simulator floor across the whole
  arena, visible rock under all four rim points and from every side looked at (`66-mod-fit-*.png`,
  `67-rock-through-mod.png`). The stretched texture still reads as rock.
- **Each visit now loads its own copy** (the visit's number ends the instance name), so a stretched copy is never
  found and stretched again. Seen on the way: actors of a copy that was unloaded but not yet collected are still
  found by a search.
- The rock's two massive-environment actors are left where they are. Hiding them made no visible difference.
- Not done: the rock's collision south edge sits a little inside the arena's rim on one side (20 to 80 cm low in the
  last 3 m), where characters stand on the simulator's floor just above the rock.

## 2026-11-17: second live session (owner's play, then probes and a retest; Epic 1.005, slot 25)

The owner played both stages and reported two faults. Both came from one mistake: the stages were anchored about a
metre too low.

| Fault (owner) | Cause, as measured | Fix | Retest through the mod |
| --- | --- | --- | --- |
| On the rock, Cloud is locked to a tiny patch | The rock's ground is 98 to 134 cm above its own z 0, so the party stood inside its collision. Measured by dropping the leader's capsule on a 3 m grid. Placed on the surface he moved freely | Anchor z 110 | Ground 0 to 24 cm above the simulator floor across the arena; Cloud covered 5 m in 6 s; enemies on the rock (`52-rock-fixed.png`) |
| In the "void", characters are silhouettes | Its collision floor is flat at z 100, so the party stood under the floor; and its ambient light, reflection capture, fog volume and 25 floor meshes arrive hidden | Anchor z 100; those classes are shown on arrival | Grey water floor with reflections and lit characters, party of three; Cloud covered 8 m in 3 s (`54-lifestream-fixed.png`) |

- The "white void" is the Lifestream (owner). The stage is now `lifestream`, "Final battle: the Lifestream". The
  owner confirmed the grey water look (`38-void-z100-floor.png`).
- **The simulator's rim clutter keeps its collision when hidden**: low blocks of 30 to 50 cm round the edge, through
  the terrain level's `Spl_CST` collision actor. Its collision now goes off with the look and back on when leaving.
  With it off the floor is flat out to the pillars at about 24 m.
- **A level that was unloaded but not yet collected is reused at its old position.** Reloading the rock 105 cm lower
  under the same instance name left it where it was. The instance name now carries the height.
- **Collision-only meshes (`CL_...`) and cutscene props (`Quest_...`) must stay hidden** when a stage's meshes are shown.
- Left as it is: the rock is about 36 m across and the simulator floor about 48 m, so near the rim characters stand on
  the simulator's invisible floor past the rock's edge.
- Not possible with the harness: walking the leader during a fight (it refuses movement while a target is present).
  Movement was read from the leader's position while the game's Classic mode moved him.

## 2026-11-17: first live session (Epic 1.005, UE4SS 3.0.1, slot 23, Costa del Sol and Bill's Ranch Chadleys)

Driven by the harness in an offline session. The game was restarted five times to load script and helper changes.

### Works

| What | How it was seen |
| --- | --- |
| The helper starts and passes its checks on this build | `stages-helper.txt`: `ready 1`, tick moving; events log: `game_thread_guard_ready epic-1.005`, `loader_check_ready` |
| The simulator stands where the level files say | Leader at (−200151, −99858, 60090) in the east and (−199291, −100522, 10090) in the west: the `COMMON_VR` volumes' `TargetLocation`, feet on z 60000 and 10000 |
| `LoadLevelInstance` with a position | `stages-ack.txt`: every requested level `loaded`; the levels' actors are at their own coordinates plus the offset (the white sky's light at (−190325, −99538, 20037)) |
| Unloading | `unloaded` for each instance; the stage gone from view; the next stage loads after it |
| **The white void, end to end** | `24-white-void-by-itself.png`: picked in the picker, streamed, the simulator's look hidden, sun and fog shown, a normal course fought on it. Log: `stream white_void 3 levels`, `dressing 20`, `activate 2` |
| **The rock in space, end to end** | `25-rock-by-itself.png`: rock underfoot, nebula sky, shadows. Log: `stream space_rock 6 levels`, `activate 43` (sun, fog and its 41 meshes) |
| The picker | `21-picker.png`: the game's choice window, "Choose a stage", over the team screen right after a course is selected; D-pad and confirm work; the choice is saved to `choices.txt` and reused |
| Courses are recognised in any language | The menu's title field holds the text id (`$menu_Colosseum_CourseTitle_COL30_GRASA_01`), not the displayed title |
| Leaving puts everything back | Log: `restore left the simulator released 6 levels`; the next course on the simulator's own stage looks normal |
| No crash | Six simulator courses, about twenty level loads and unloads, three stage swaps inside one fight |

### Found and fixed on the way

- **A stage's sky arrives switched off.** A sky level's sun and fog are hidden until the game's sky system selects that
  sky; streamed on its own it gave a black scene. The mod shows them (`game.activate_stage`).
- **The rock in space's meshes arrive hidden** (all 41): the boss fight shows them. The stage lists them in
  `show_classes`.
- **The simulator's block skyline is not its block actors.** Hiding those left a black skyline; it is drawn by the
  terrain level's massive-environment component. Hiding that component clears it.
- **The white void's light level cuts exposure by 6 stops.** Right with its own bright sky, black without it.
- **The white void's floor is one-sided.** Loaded 60 cm above the party it was invisible and squeezed the camera.
- **This machine uses the low-spec sky** (`0001-WORLD_VRSky_Low`); the hide matches both.
- **A weak pointer made in the helper never resolved**, so the first unloads were refused. The helper keeps the
  stream's address and confirms it is still a live object before using it.
- **An object search at arrival was the same pattern that crashed Junon Colosseum.** The scripts now wait for the
  helper's "loader idle" before searching.
- **My own mistakes:** a clean-up cut four functions off `game.lua` (a test now checks every `game.` call is
  defined); a dev snippet called `ShouldBeVisible`, which is not a function of that object (the Lua state survived).

### Does not work yet

| What | What happened |
| --- | --- |
| Arena stages, streamed (tried: Nibel) | Five of six levels loaded and unloaded cleanly, and distant mountains showed, but no ground appeared under the fight: the arena's ground is massive-environment terrain, which did not show at the offset. Its sky level has 192 local fog volumes; all on whites the scene out, all off leaves it black. The thirteen arena stages are marked `experimental` and are not offered |
| Moving the simulator (`route = move`, tried: Corel) | The write to `TargetLocation` was accepted and read back, but the party arrived at the simulator's usual place. The simulator had already been visited in that session; a first visit after launch is untested |
| The harness reading the picker | The running harness build read only the picker's first two buttons, and `choose_message_window` refuses outside a fight. Menu taps work |
| One Nibel level | `2600-NIBLA_Water_Terrain_Strip`: `load_refused` |

### Not looked at yet

- A summon course, a multi-round course and a party of three on a streamed stage.
- The picker's cursor starts on the first option, not the remembered one (the remembered one carries a `>` mark).
- Lighting on characters in the white void: silhouetted from some angles.
- Memory and load time. The two final battle stages were ready within 2 s of arrival.
- The unlock rules with a real save state (`require_unlock = false` was used throughout).
- Steam, and any game version other than Epic 1.005.
