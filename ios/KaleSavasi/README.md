# Castle War / Kale Savaşı (iOS)

Two castles, two cannons, two hearts. Players take turns firing; the first player whose heart
is shattered loses. Native Swift: SceneKit for the 3D scene, SwiftUI for the HUD and menus.
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

Every castle guards one heart: three courses of glowing crystal with a gem floating above it.
Destroying the enemy heart wins the match, however much of their castle is still standing.
The heart is tougher than stone: a blast only breaks heart crystal within half its usual
reach, so it takes a well-placed shot, or a wall knocked out of the way first. The bar under
each name shows the heart; the small number beside it is how much of the castle still stands.

### Build your castle

The castle you defend is your own design, and its job is to keep the heart out of reach. The
builder is a grid of 11 × 15 tiles seen from above, with a live 3D preview beside it. Six
pieces cost stone: low and high walls (one tile), towers, tall towers and bastions (2 × 2), and
the keep (3 × 3). The heart (one tile) is free. A castle needs exactly one heart, at most one
keep, at least 1,200 stone and at most 2,400. Castles saved before hearts existed get one
placed automatically on the free tile nearest the back centre. Tall towers and bastions unlock with campaign
stars. Online, each player's design is sent at the start of the match and checked against
these rules on arrival; anything that fails becomes the classic layout. Both devices must run
the same rules version, or the lobby says so and stops.

Design matters: in computer-versus-computer tests against the classic layout, the ready-made
castles won between 29 % and 59 % of matches.

### Special shots, balloons and match twists

| Mechanic | Rule |
| --- | --- |
| Cluster | Three smaller blasts in a row across the line of fire. |
| Piercer | Carries on through the stone and goes off about 6.5 units inside. |
| Homing | Steers toward the gold target on the way down. |
| Balloons | One drifts over the river from time to time. A shot that passes within 2.8 units grabs it and flies on: Repair rebuilds up to 110 cells, Shield cuts the next blast against you to 60 % radius, Charge adds half a mega meter. |
| Twists | Storm, still air, low gravity, mega rush and big blast change a whole match. They appear in campaign stages and in the daily siege. |

Each side carries one of each special shot per match.

### Campaign

Twelve stages against the computer, each with its own castle, skill level and twist. A win
earns one to three stars by how much of your castle is still standing (40 % and 60 % are the
steps), opens the next stage, and counts toward the building pieces.

### What makes a turn matter

| Mechanic | Rule |
| --- | --- |
| Gold target | Each turn one exposed block on the enemy castle is marked. Landing within 3.2 units of it is a critical hit: the blast is 25 % wider. |
| Mega shot | A meter fills as you deal damage, faster on a streak, and more slowly as you take damage. When full, the MEGA button arms a shot with a 45 % wider blast. |
| Streak | Consecutive damaging shots. Each step up to four speeds up the mega meter. A miss resets it. |
| Shot clock | 20 seconds per turn in online and same-device matches. A drawn pull fires when it runs out; otherwise the turn is lost. |

### Daily Siege

A solo score attack: eight shots at a castle that does not shoot back. The castle, the winds
and the gold targets (and, some days, a twist) come from the date, so every player gets the same siege that day and
scores are comparable. A shot scores 10 points per percent of damage, 50 for a critical and up
to 50 for the current streak; shattering the heart early adds 150 plus 75 per unused
shot. Today's best and the all-time record are kept, and the first run of the day pays 60 XP.

### Daily missions

Three goals per day, the same for everyone, drawn from a pool of seven (win a match, land hits
or criticals, fire mega shots, deal 12 % with one shot, reach a streak, play the siege).
Progress adds up across matches and the siege; each finished mission pays 40 XP.

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
| `Sources/Rules.swift` | Castle designs and pieces, ballistics, damage, special shots, balloons, twists, campaign stages, siege scoring, computer player. No rendering. |
| `Sources/World.swift` | SceneKit scene: terrain, castle meshes, rubble physics, effects |
| `Sources/Textures.swift` | Procedural stone, grass, water, roof and sky; the app ships no image files besides its icon |
| `Sources/GameController.swift` | Turn flow, shot clock, cameras, pull-to-shoot input, castle builder, online protocol |
| `Sources/Views.swift` | SwiftUI app and the in-match HUD |
| `Sources/Menus.swift` | Menu, campaign map, castle builder, profile, settings, lobby and result cards |
| `Sources/Profile.swift` | Level, trophies, leagues, streaks, missions and match rewards |
| `Sources/Strings.swift` | Turkish and English text |
| `Sources/Net.swift` | Game Center and nearby transports behind one protocol |
| `Sources/Sfx.swift` | Synthesized sound effects |
| `Tools/make-icon.swift` | Regenerates the app icon |

Online matches stay in sync because each shot is sent as its exact launch position and
velocity and both devices run the same fixed-step simulation in `Rules.swift`. The gold target,
mega meter and streaks are derived from that shared state, so they agree too. Rubble physics
is cosmetic and may differ between devices.

The scene is physically based: one generated sky panorama is both the backdrop and the light
source, with a sun casting cascaded shadows, ambient occlusion, HDR and a little bloom.

Debug builds accept launch arguments for unattended testing: `-autoNearby` opens the nearby
lobby at launch, `-autoPlay` lets the computer take this device's turns, and `-preset N` plays
with ready-made castle N.

## Tuning

The constants at the top of `Rules.swift` (`K`) set castle size, distance, blast radius,
launch angle, speed range, the critical and mega bonuses and the shot clock. Reward amounts
are in `Profile.swift`. `../../web-prototype` holds the earlier browser prototype with the old
brick look and slider controls; it is not kept in step with this app.
