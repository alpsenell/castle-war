# Kale Savaşı (iOS)

Two castles, two cannons. Players take turns firing; the castle that drops below 20 % of its
structure loses. Native Swift: SceneKit for the 3D scene, SwiftUI for the HUD and menus.

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

## Modes

| Mode | How it connects |
| --- | --- |
| Yapay zekâya karşı | Computer opponent, three difficulty levels |
| Aynı cihazda 2 kişi | Pass-and-play |
| Online: yakındaki oyuncu | MultipeerConnectivity, same Wi-Fi or Bluetooth, no account |
| Online: Game Center | Real-time `GKMatch` over the internet, friends or auto-match |

Game Center only works once the bundle ID (`com.alpsenel.kalesavasi`, change it in
`project.yml`) is registered in App Store Connect with Game Center enabled and the app is
signed with your team. Until then the lobby shows Game Center's own error.

## Layout

| File | Role |
| --- | --- |
| `Sources/Rules.swift` | Castle layout, ballistics, damage, computer player. No rendering. |
| `Sources/World.swift` | SceneKit scene: terrain, castle meshes, rubble physics, effects |
| `Sources/GameController.swift` | Turn flow, cameras, pull-to-shoot input, online protocol |
| `Sources/Views.swift` | SwiftUI app, HUD, menu, lobby and result cards |
| `Sources/Net.swift` | Game Center and nearby transports behind one protocol |
| `Sources/Sfx.swift` | Synthesized sound effects |
| `Tools/make-icon.swift` | Regenerates the app icon |

Online matches stay in sync because each shot is sent as its exact launch position and
velocity and both devices run the same fixed-step simulation in `Rules.swift`. Rubble physics
is cosmetic and may differ between devices.

Debug builds accept two launch arguments for unattended testing: `-autoNearby` opens the
nearby lobby at launch and `-autoPlay` lets the computer take this device's turns.

## Tuning

The constants at the top of `Rules.swift` (`K`) set castle size, distance, blast radius,
launch angle and speed range. `../../web-prototype` holds the earlier browser prototype with
the old brick look and slider controls; it is not kept in step with this app.
