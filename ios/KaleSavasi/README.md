# Castle War / Kale Savaşı (iOS)

Two castles, two cannons. Players take turns firing; the castle that drops below 20 % of its
structure loses. Native Swift: SceneKit for the 3D scene, SwiftUI for the HUD and menus.
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

### What makes a turn matter

| Mechanic | Rule |
| --- | --- |
| Gold target | Each turn one exposed block on the enemy castle is marked. Landing within 3.2 units of it is a critical hit: the blast is 25 % wider. |
| Mega shot | A meter fills as you deal damage, faster on a streak, and more slowly as you take damage. When full, the MEGA button arms a shot with a 45 % wider blast. |
| Streak | Consecutive damaging shots. Each step up to four speeds up the mega meter. A miss resets it. |
| Shot clock | 20 seconds per turn in online and same-device matches. A drawn pull fires when it runs out; otherwise the turn is lost. |

### Daily Siege

A solo score attack: eight shots at a castle that does not shoot back. The castle, the winds
and the gold targets come from the date, so every player gets the same siege that day and
scores are comparable. A shot scores 10 points per percent of damage, 50 for a critical and up
to 50 for the current streak; bringing the castle under 20 % early adds 150 plus 75 per unused
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
| Play the computer | Computer opponent, three difficulty levels |
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
| `Sources/Rules.swift` | Castle layout, ballistics, damage, gold target, mega meter, siege scoring, computer player. No rendering. |
| `Sources/World.swift` | SceneKit scene: terrain, castle meshes, rubble physics, effects |
| `Sources/GameController.swift` | Turn flow, shot clock, cameras, pull-to-shoot input, online protocol |
| `Sources/Views.swift` | SwiftUI app, HUD, menu, profile, lobby and result cards |
| `Sources/Profile.swift` | Level, trophies, leagues, streaks, missions and match rewards |
| `Sources/Strings.swift` | Turkish and English text |
| `Sources/Net.swift` | Game Center and nearby transports behind one protocol |
| `Sources/Sfx.swift` | Synthesized sound effects |
| `Tools/make-icon.swift` | Regenerates the app icon |

Online matches stay in sync because each shot is sent as its exact launch position and
velocity and both devices run the same fixed-step simulation in `Rules.swift`. The gold target,
mega meter and streaks are derived from that shared state, so they agree too. Rubble physics
is cosmetic and may differ between devices.

Debug builds accept two launch arguments for unattended testing: `-autoNearby` opens the
nearby lobby at launch and `-autoPlay` lets the computer take this device's turns.

## Tuning

The constants at the top of `Rules.swift` (`K`) set castle size, distance, blast radius,
launch angle, speed range, the critical and mega bonuses and the shot clock. Reward amounts
are in `Profile.swift`. `../../web-prototype` holds the earlier browser prototype with the old
brick look and slider controls; it is not kept in step with this app.
