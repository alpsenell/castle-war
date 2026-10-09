# Keepfall (iOS)

Two castles, two cannons, two hearts. Castles are built brick by brick from wood, stone and
ice, and every brick is a rigid body: a cannonball knocks bricks loose, topples towers and
breaks bricks into fragments. Players take turns firing; the first player whose heart falls
loses. Native Swift: SceneKit for the 3D scene and its physics, SwiftUI for the HUD and menus.
The game ships in Turkish and English.

## Run

```bash
xcodegen generate
```

```bash
open KaleSavasi.xcodeproj
```

Pick an iPhone simulator and press Run. `./run.sh <simulator-udid>` builds and launches from
the command line. Requires Xcode 26 and iOS 17 or later; the app is landscape only.

## How to play

Touch anywhere on the scene, pull back (down) and release, slingshot style:

- pull length sets the power,
- pulling left or right turns the cannon the opposite way,
- the dotted arc shows the first part of the flight, the dashed ring marks where your previous
  shot was released.

Wind changes every turn (arrow in the top plate, up means toward the target). The binoculars
button orbits the enemy castle; drag to rotate, pinch to zoom.

### The heart

Every castle guards one heart: a glowing crystal brick with a gem floating above it. A heart
falls, and its castle loses, when

- it shatters: it takes two hard knocks (a titan heart three),
- it is knocked more than 3 units (one and a half bricks) off its spot, or
- less than a third of its castle still stands: the castle comes down and takes the heart
  with it.

The bar under each name shows the heart; the small number beside it is how much of the castle
still stands. That share is by mass: a brick counts while it is in one piece, within 0.6 units
of where it was built and the right way up.

A shot that is going to break a heart plays out as the **final shot**: the camera swings to the
side of the ball, time slows to 0.3×, cinema bars close in, and the blast lingers in slow
motion before the result card.

#### Heart types

Picked in the builder; each one unlocks with player level and costs coins on top of the castle.
Decoys take on the colour of the castle's heart type, so they still pass for the real one.

| Heart | Level | Coins | Effect |
| --- | --- | --- | --- |
| Crystal | 1 | 0 | The plain heart: two knocks. |
| Living | 4 | 80 | At the start of each of its owner's turns, mends one crack. |
| Aegis | 7 | 80 | The first time it cracks without falling, throws the shield over its castle (once per match). |
| Titan | 10 | 100 | Takes three knocks instead of two. |

### Build your castle

The castle you defend is your own design, and its job is to keep the heart out of reach. The
builder is a full-screen 3D view of your plot, 15 bricks wide, 11 deep and 9 high. Pick a shape
and a material in the tray, then tap the ground or the top or side of a brick: a ghost brick
shows where it will go, green when it fits and red when it does not. Drag to orbit, use two
fingers to pan, zoom and turn. The tools are Rotate, Erase, Undo and Redo, a layer slider that
hides the levels above, Stamps (wall, tall wall, tower, tall tower, keep, gatehouse, shrine,
bridge) and Castles (every ready-made castle as a starting point). **Test gravity** lets the
castle stand under real physics for three seconds, counts the bricks that moved, and puts
everything back.

Shapes: cube, half brick, beams of 2, 3 and 4, plank, pillars of 2 and 3, wedge, arch, cone and
pyramid roofs, battlement, window block and moat.

| Material | Coins a brick | Weight | Breaks |
| --- | --- | --- | --- |
| Wood | 6 | light | under a medium knock |
| Stone | 9 | heavy | under a hard knock |
| Ice | 7 | light | under a light knock, and shatters |
| Iron | 15 | heaviest | after two hard knocks: the first cracks it |

Prices are for one cube's worth of volume; roofs, wedges, arches, battlements and windows cost
by how much of their box is solid. A castle needs exactly one heart, at most two decoys (25
coins each), at most 260 bricks, nothing floating and nothing stacked on a roof or a
battlement, and it must cost between 900 and 3,600 coins. A moat (30 coins) is water on the
ground: a shot that lands in it splashes. A decoy looks and breaks exactly like the heart;
knocking it out gives it away (its gem pops and the crystal goes grey) but wins nothing. The
computer cannot tell decoys from the heart either.

Castles saved by version 1 (tiles) are rebuilt in bricks from the stamps on first launch. Online,
each player's design travels in the opening hello and is checked against these rules on
arrival; anything that fails becomes the classic castle. Both devices must run the same rules
version, or the lobby says so and stops.

Design matters: in computer-versus-computer tests at medium against the classic castle, the
ready-made castles won 36 % of 84 matches (between 25 % and 50 % each). Those duels took 13
shots at the median, and about one in forty was over within two shots. The stockade and the layers hide behind moats,
the layers, spires, citadel, frost and stronghold hide decoys, the citadel and the bulwark have
iron in their front walls, and the frost castle is built of ice on a stone footing.

### Special shots, balloons and match twists

| Mechanic | Rule |
| --- | --- |
| Cluster | Three balls side by side across the line of fire. |
| Piercer | A dense ball that carries on straight through the first two bricks it meets. |
| Homing | Steers toward the gold target on the way down. |
| Balloons | One drifts over the river from time to time. A shot that passes within 2.8 units grabs it and flies on: Repair puts back up to 12 % of your castle (by mass, lowest bricks first, where there is room), Shield softens every knock against your castle to 60 % until it is hit, Charge adds half a mega meter. |
| Twists | Storm, still air, low gravity, mega rush and big blast change a whole match. They appear in campaign stages and in the daily siege. |

Each side carries one of each special shot per match.

### Campaign

Twelve stages against the computer, each with its own castle, skill level and twist. A win
earns one to three stars by how much of your castle is still standing (40 % and 60 % are the
steps) and opens the next stage.

### What makes a turn matter

| Mechanic | Rule |
| --- | --- |
| Gold target | Each turn one exposed brick on the enemy castle is marked. Landing within 3.2 units of it is a critical hit: the ball strikes 25 % heavier. |
| Mega shot | A meter fills as you deal damage, faster on a streak, and more slowly as you take damage. When full, the MEGA button arms a ball 2.2 times as heavy, with a shock wave where it lands. |
| Streak | Consecutive damaging shots. Each step up to four speeds up the mega meter. A miss resets it. |
| Shot clock | 20 seconds per turn in online and same-device matches. A drawn pull fires when it runs out; otherwise the turn is lost. |

### Daily Siege

A solo score attack: eight shots at a castle that does not shoot back. The castle, the winds
and the gold targets (and, some days, a twist) come from the date, so every player gets the same siege that day and
scores are comparable. A shot scores 10 points per percent of damage, 50 for a critical and up
to 50 for the current streak; bringing the heart down early adds 150 plus 75 per unused
shot. Today's best and the all-time record are kept, and the first run of the day pays 60 XP.

### Daily missions

Three goals per day, the same for everyone, drawn from a pool of seven (win a match, land hits
or criticals, fire mega shots, deal 12 % with one shot, reach a streak, play the siege).
Progress adds up across matches and the siege; each finished mission pays 40 XP.

### Four castles

A free-for-all for up to four players. The castles stand on the four sides of a square field
around a round lake (a shot that lands in it splashes), each cannon in front of its own castle.
Players take turns round the field; whoever's heart breaks is out and the turn skips them, and
the last heart standing wins. On your turn the target buttons pick which castle to attack: the
cannon swings round to face it and the pull aims relative to that castle. The gold target can
sit on any enemy castle. The computer goes for the weakest heart a little over half the time
and picks at random otherwise.

| Way to play | How seats fill |
| --- | --- |
| Against 3 computers | You and three computer castles, at the chosen difficulty |
| Game Center | Matchmaking for 2 to 4 players; empty seats get computers |
| Host nearby / Join nearby | One device hosts and presses Start once at least one other player has joined (up to three); the rest are computers |

Online, the host seats everyone and runs the computer castles, sending their shots like a
player's, and settles their shots; every device follows the same seed, shots and settles, as in a duel. Each
device sends a heartbeat every 1.5 s. When a player goes quiet for 7 s, a computer takes over
their castle; when the host does, the match ends for everyone else. Nearby joiners only talk
to the host, which passes their messages on.

Finishing places pay XP (1.4× for first down to 0.6× for fourth, plus the online bonus) and
trophies: online +30, +10, −8, −15; against computers +12, +4, −3, −6. Your place is booked the
moment your heart breaks, so you can keep watching or leave without a penalty. Leaving earlier
in an online match counts as the worst place still open.

### Gauntlet

Castle after castle until yours falls. Each round is a ready-made castle chosen from the run's
seed; the computer is easy for castles 1–3, medium for 4–7 and hard after that. From castle 8
the enemy brings a living heart, from castle 11 an aegis heart, and every third castle from
the fourth adds a match twist. Damage to your castle carries into the next fight; each win
puts back up to 40 % of its mass. Every fight pays XP (20 plus 6 per castle toppled so far for a
win, 10 for the loss that ends the run), and the best run is kept.

### Castle codes

The builder's Share button turns the castle (bricks and heart type) into a text code such as
`KS2-0A3F…` (about 23 bits a brick in base32, with a checksum) and opens the share sheet with
a short invitation. Paste loads a code into the builder. On the menu, Friend's castle pastes a
code and starts a match against that castle at the chosen difficulty. A code is checked
against the building rules, so a mistyped or tampered code is refused. Version 1 codes
(`KS-…`) still load and are rebuilt in bricks.

### Achievements

Seventeen one-time goals, each worth 50 XP: first win, 10 wins, 25 criticals, 10 mega shots, a
flawless win (heart untouched), a win with under half of the castle standing, 3 decoys broken
by the enemy, 5 and 10 castles in one gauntlet run, clearing the campaign, all 36 stars, 1,500
in a daily siege, a 5-win streak, level 10, saving your own castle, beating a friend's castle,
and reaching the Legend league. The profile opens a panel with every goal and its progress.
With Game Center, each one is reported as `kalesavasi.<id>` (for example
`kalesavasi.flawless`), and the best gauntlet run goes to the leaderboard `kalesavasi.gauntlet`.

### What carries over between matches

The profile (stored on the device) keeps level and XP, trophies and league, win streak, daily
streak, accuracy and totals. A match pays XP for playing, winning, accuracy, criticals and the
current win streak, scaled by opponent (easy 0.6×, medium 1×, hard 1.4×, online 1.5×), plus
50 XP for the first win of the day. Trophies move up on a win and down on a loss; leaving an
online match in progress counts as a loss, and the player who stays gets the win. Levels 3, 6
and 10 unlock cannonball styles. Same-device matches do not touch the profile.

Online, players exchange name, level and trophies when the match starts. The trophies at stake
follow the gap between the two counts: an even match is +25 / −20, beating a much stronger
player pays up to +40, and losing to one costs as little as 8. The name is editable in the
profile. The result card puts both players' accuracy, best hit and criticals side by side.

When the player is signed in to Game Center, trophies go to the leaderboard
`kalesavasi.trophies` and the day's best siege score to `kalesavasi.daily`. Both have to be
created in App Store Connect; the daily one should be a recurring leaderboard that resets
every day.

## Modes

| Mode | How it connects |
| --- | --- |
| Campaign | Twelve stages against the computer |
| Quick match | Computer opponent, three difficulty levels, random enemy castle |
| Two players, one device | Pass-and-play |
| Daily Siege | Solo score attack, same castle for everyone each day |
| Gauntlet | Endless run of computer castles, damage carries over |
| Friend's castle | Computer match against a castle pasted as a code |
| Four castles | Free-for-all for up to four: against computers, Game Center, or nearby host and join |
| Online: nearby player | MultipeerConnectivity, same Wi-Fi or Bluetooth, no account |
| Online: Game Center | Real-time `GKMatch` over the internet, friends or auto-match |

Game Center only works once the bundle ID (`com.alpsenel.kalesavasi`, change it in
`project.yml`) is registered in App Store Connect with Game Center enabled and the app is
signed with your team. Until then the lobby shows Game Center's own error.

## Languages

All player-facing text lives in `Sources/Strings.swift`, one entry per string with the Turkish
and English wording side by side. The language follows the device on first launch and can be
switched from the main menu. The app name on the Home Screen is localized through
`Sources/tr.lproj` and `Sources/en.lproj`.

## Layout

| File | Role |
| --- | --- |
| `Sources/Bricks.swift` | The brick model: shapes, materials, placed bricks, designs and their rules, snapshots and the binary pose delta sent online, the physics protocol |
| `Sources/Stamps.swift` | Prefab stamps, the ready-made and campaign castles, and the rebuild of version 1 tile castles |
| `Sources/Legacy.swift` | The version 1 tile castle, kept to read old saves and codes |
| `Sources/Rules.swift` | Ballistics up to first contact, castle state read from settled bricks (standing, heart, decoys, support), special shots, balloons, twists, campaign, gauntlet, siege scoring, castle codes, computer player. No rendering. |
| `Sources/Physics.swift` | The match physics: waking castles on impact, balls by ammo type, impulse breaking, fragments, settling and freezing, adopting poses from another device |
| `Sources/World.swift` | SceneKit scene: terrain, castles drawn as one merged copy while at rest, cannons and effects |
| `Sources/World+Builder.swift` | The builder's 3D bench: preview, hit testing, ghost bricks, Test gravity, tray icons |
| `Sources/BrickGeometry.swift` | Brick meshes, looks and body shapes, cached per shape and material |
| `Sources/Textures.swift` | Procedural wood, stone, ice, grass, water, roof and sky; the app ships no image files besides its icon |
| `Sources/GameController.swift` | Turn flow, shot clock, cameras, pull-to-shoot input, online protocol and shot sync |
| `Sources/GameController+Builder.swift` | Builder actions: placing, erasing, undo, stamps, codes, saving |
| `Sources/Theme.swift` | The carved wood, stone and parchment UI theme |
| `Sources/Views.swift` | SwiftUI app and the in-match HUD |
| `Sources/Menus.swift` | Menu, campaign map, profile, settings, lobby and result cards |
| `Sources/BuilderView.swift` | The builder's tray, tools and top bar |
| `Sources/Profile.swift` | Level, trophies, leagues, streaks, missions, match rewards and the saved castle |
| `Sources/Strings.swift` | Turkish and English text |
| `Sources/Net.swift` | Game Center and nearby transports behind one protocol |
| `Sources/Sfx.swift` | Synthesized sound effects, a break sound per material |
| `Tools/make-icon.swift` | Regenerates the app icon |

Online matches stay in sync because the shooter's device decides each shot. The shot is sent as
its exact launch position and velocity, so every device flies the same arc to the first touch
(`Rules.swift`, fixed step). From there each device plays its own physics for the show. Once the
shooter's castles have settled, it sends a `settle` message: for every castle, the bricks that
moved, each as an id, a position to the centimetre, a packed rotation and its hit points (15
bytes a brick, base64 in the message; a few kilobytes in practice). Every device, the shooter
included, rules on those same rounded poses, so hearts, standing, the gold target, the mega
meter and streaks agree exactly. The others ease their bricks onto the shooter's poses over
0.4 s, and the next turn starts only once the settle has been applied; if it has not come
10 s after a device's own physics settled, that device carries on with its own result. In
four-castle matches the host relays every message and settles the computer seats' shots.

The scene is physically based: one generated sky panorama is both the backdrop and the light
source, with a sun casting cascaded shadows, ambient occlusion, HDR and a little bloom. While
nothing moves, each castle is drawn as one merged copy of its bricks; a shot wakes the castles
near it, and the bricks freeze again once everything rests (at most 6 s).

Debug builds accept launch arguments for unattended testing:

| Argument | Effect |
| --- | --- |
| `-autoPlay` | The computer takes this device's turns |
| `-autoNearby` | Opens the nearby duel lobby at launch (with `-autoPlay`, two simulators play on and rematch) |
| `-autoParty host` / `-autoParty join` | A nearby four-castle match; the host starts as soon as someone joins |
| `-demoMatch`, `-party`, `-siege`, `-gauntlet`, `-stage N` | Starts that mode at launch |
| `-preset N` | Plays with ready-made castle N instead of the saved one |
| `-balance [N]` | N computer-versus-computer matches (medium), each ready-made castle against the classic one, logged as `BALANCE …` lines and to `Documents/balance.txt` |
| `-stats` | SceneKit statistics (frame rate) |
| `-inspect`, `-knocks` | Swing round to the enemy castle; log every knock in the physics |
| `-screen builder`, `-demoCastle N`, `-demoGravity` | Opens the builder, loads a demo castle (0 is a showcase), runs Test gravity |
| `-screen …`, `-panel …` | Jumps to a screen or menu panel for screenshots |

## Tuning

The constants at the top of `Rules.swift` (`K`) set distance, launch angle, speed range, ball
mass, the critical and mega bonuses, how far a heart may be knocked (`heartReach`), the
standing share below which a castle loses its heart (`heartFloor`), the settle time and the
shot clock. `BK` and `BrickMaterial` in `Bricks.swift` set the plot size, the coin limits and
each material's weight, strength and price; `K.breakScale` scales every material's strength at
once. Reward amounts are in `Profile.swift`. `../../web-prototype` holds the earlier browser
prototype with slider controls; it is not kept in step with this app.
