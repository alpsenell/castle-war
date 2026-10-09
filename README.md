# Keepfall

A two-player castle battle. Each player builds a castle brick by brick around a glowing heart,
in wood, stone and ice, then the two take turns firing a cannon at each other. Every brick is a
rigid body, so shots topple towers and break bricks into fragments; the first heart to fall
loses. Play against the computer, on one device, or online, where the shooter's device settles
each shot for everyone.

- [`ios/KaleSavasi`](ios/KaleSavasi) is the game: a native iOS app in Swift (SceneKit and
  SwiftUI). Its [README](ios/KaleSavasi/README.md) covers running it, the controls, the 3D
  castle builder, the physics rules, online sync and the Game Center setup.
- [`web-prototype`](web-prototype) is the earlier browser prototype (Three.js). It keeps the
  first design, with slider controls, and is not kept in step with the app.

![Pull back and release to shoot](ios/KaleSavasi/Screenshots/1-pull-to-shoot.png)
