import SwiftUI
import SceneKit

// The castle builder's actions. Its stored state lives in `GameController`.

/// What a finger on the builder canvas does.
enum BuildTool: Equatable {
    case brick, stamp, heart, decoy, moat, erase, look
    /// Adds bricks where it is released.
    var places: Bool { self != .erase && self != .look }
}

/// The one-finger gesture in progress on the builder canvas.
enum BuildGesture {
    case idle, orbit(CGPoint), place(CGPoint), erase(Int?)
}

/// The builder's orbit camera around the castle plot.
struct BuildCam {
    var yaw = 0.62, pitch = 0.66, dist = 62.0
    /// Offset of the look-at point from the middle of the plot, world units.
    var focus = SIMD3<Float>(0, -3, 0)
}

extension GameController {
    // MARK: Opening and closing

    func openBuilder() {
        sfx.play(.tick)
        draft = profile.castle
        if !profile.owns(draft.heart) { draft.heart = .crystal }
        buildTool = .brick; buildRot = 0; buildLayer = BK.height
        builderNote = nil; undoStack = []; redoStack = []
        buildGesture = .idle; testingGravity = false
        buildCam = BuildCam()
        screen = .builder
        cam = .target
        viewSeat = 0
        bench?.remove()
        bench = world.openBench()
        refreshBench()
    }

    func closeBuilder() {
        bench?.remove()
        bench = nil
        screen = .menu
        panel = .home
        cam = .menu
        menuA = Double(atan2(camPos.x, camPos.z))
        resetBackdrop()
    }

    func saveCastle() {
        if let pr = draft.problem { flash(Tx.brickProblem(pr)); sfx.play(.thud); return }
        profile.design = draft.encoded
        profile.castlesSaved += 1
        let fresh = profile.unlockAchievements()
        profile.save()
        sfx.play(.charged)
        thump(.medium)
        closeBuilder()
        show(toast: fresh.first.map(Tx.achievementDone) ?? Tx.saved)
    }

    // MARK: Tools

    func pick(tool t: BuildTool) {
        buildTool = t
        bench?.hideGhost()
        sfx.play(.tick)
    }

    func pick(shape s: BrickShape) {
        buildShape = s
        buildTool = .brick
        if !s.materials.contains(buildMaterial) { flash(Tx.roofMaterials) }
        sfx.play(.tick)
    }

    func pick(stamp s: Stamp) { buildStamp = s; buildTool = .stamp; sfx.play(.tick) }

    func pick(material m: BrickMaterial) {
        buildMaterial = m
        if buildTool == .erase || buildTool == .look || buildTool == .heart || buildTool == .decoy { buildTool = .brick }
        sfx.play(.tick)
    }

    func rotate() {
        buildRot = (buildRot + 1) % 4
        sfx.play(.tick)
        thump(.light)
        if case .place(let p) = buildGesture { buildMove(p) }
    }

    func setLayer(_ n: Int) {
        let next = min(BK.height, max(1, n))
        guard next != buildLayer else { return }
        buildLayer = next
        sfx.play(.tick)
        refreshBench()
    }

    func pick(heart h: HeartKind) {
        guard profile.owns(h) else { flash(Tx.heartLocked(h.level)); return }
        var next = draft
        next.heart = h
        guard next.cost <= BK.budget else { flash(Tx.noCoins); return }
        commit(next)
        flash(Tx.heart(h) + ": " + Tx.heartInfo(h))
    }

    // MARK: Editing

    /// Replaces the draft, remembering the old one for Undo.
    func commit(_ next: BrickDesign) {
        guard next != draft else { return }
        undoStack.append(draft)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        draft = next
        refreshBench()
    }

    func undo() {
        guard let last = undoStack.popLast(), !testingGravity else { return }
        redoStack.append(draft)
        draft = last
        refreshBench()
        sfx.play(.tick)
        thump(.light)
    }

    func redo() {
        guard let next = redoStack.popLast(), !testingGravity else { return }
        undoStack.append(draft)
        draft = next
        refreshBench()
        sfx.play(.tick)
        thump(.light)
    }

    func clearDraft() { commit(BrickDesign(heart: draft.heart)); sfx.play(.thud) }

    func loadDraft(_ d: BrickDesign) {
        var d = d
        if !profile.owns(d.heart) { d.heart = .crystal }
        commit(d)
        sfx.play(.tick)
    }

    func refreshBench() {
        bench?.show(draft, layer: buildLayer, warn: draft.floating)
    }

    /// Shows a short note over the canvas for a moment.
    func flash(_ note: String) {
        builderNote = note
        buildNoteWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.builderNote = nil }
        buildNoteWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: w)
    }

    // MARK: Touches on the canvas (window coordinates)

    func buildDown(_ p: CGPoint) {
        guard screen == .builder, !testingGravity, let bench else { return }
        let hit = buildTool == .look ? nil : bench.probe(p)
        guard let hit else { buildGesture = .orbit(p); return }
        if buildTool == .erase {
            let i = brickIndex(hit)
            bench.mark(i)
            buildGesture = .erase(i)
        } else {
            buildGesture = .place(p)
            showGhost(for: hit)
        }
    }

    func buildMove(_ p: CGPoint) {
        guard let bench else { return }
        switch buildGesture {
        case .orbit(let last):
            buildCam.yaw += Double(p.x - last.x) * 0.009
            buildCam.pitch = min(1.45, max(0.08, buildCam.pitch + Double(p.y - last.y) * 0.006))
            buildGesture = .orbit(p)
        case .place:
            buildGesture = .place(p)
            if let hit = bench.probe(p) { showGhost(for: hit) } else { bench.hideGhost() }
        case .erase:
            let i = bench.probe(p).flatMap(brickIndex)
            bench.mark(i)
            buildGesture = .erase(i)
        case .idle: break
        }
    }

    func buildUp(_ p: CGPoint) {
        guard let bench else { return }
        let g = buildGesture
        buildGesture = .idle
        switch g {
        case .place:
            bench.hideGhost()
            guard let hit = bench.probe(p), let add = candidate(for: hit) else { return }
            var base = draft
            if buildTool == .heart { base.bricks.removeAll { $0.material == .heart } }
            if let why = verdict(adding: add, to: base) { flash(why); sfx.play(.thud); thump(.rigid); return }
            base.bricks += add
            commit(base)
            sfx.play(buildTool == .moat ? .splash : .tick)
            thump(buildTool == .stamp ? .medium : .light)
        case .erase(let i):
            bench.mark(nil)
            guard let i, i < draft.bricks.count else { return }
            var next = draft
            next.bricks.remove(at: i)
            commit(next)
            sfx.play(.hit)
            thump(.medium)
        default: break
        }
    }

    func buildCancel() {
        if case .place = buildGesture { bench?.hideGhost() }
        if case .erase = buildGesture { bench?.mark(nil) }
        buildGesture = .idle
    }

    /// Two-finger gestures: pinch zooms, drag pans across the plot, twist turns the view.
    func buildZoom(_ factor: CGFloat) { buildCam.dist = min(95, max(14, buildCam.dist / Double(max(0.2, factor)))) }

    func buildPan(_ d: CGSize) {
        let k = Float(buildCam.dist) * 0.0016
        let right = SIMD3<Float>(Float(-sin(buildCam.yaw)), 0, Float(cos(buildCam.yaw)))
        let back = SIMD3<Float>(Float(cos(buildCam.yaw)), 0, Float(sin(buildCam.yaw)))
        var f = buildCam.focus - right * Float(d.width) * k - back * Float(d.height) * k
        f.x = min(16, max(-16, f.x)); f.z = min(20, max(-20, f.z))
        buildCam.focus = f
    }

    func buildTwist(_ radians: CGFloat) { buildCam.yaw -= Double(radians) }

    /// Camera position and look-at point for the builder.
    func builderCamera() -> (SIMD3<Float>, SIMD3<Float>) {
        let c = world.arena.castleCenter(0).f
        let look = c + buildCam.focus
        let cp = cos(buildCam.pitch), d = buildCam.dist
        let pos = look + SIMD3(Float(cp * cos(buildCam.yaw) * d), Float(sin(buildCam.pitch) * d), Float(cp * sin(buildCam.yaw) * d))
        return (pos, look)
    }

    private func brickIndex(_ hit: BenchHit) -> Int? {
        if case .brick(let i, _, _) = hit { return i }
        return nil
    }

    private func showGhost(for hit: BenchHit) {
        guard let add = candidate(for: hit) else { bench?.hideGhost(); return }
        var base = draft
        if buildTool == .heart { base.bricks.removeAll { $0.material == .heart } }
        bench?.showGhost(add, valid: verdict(adding: add, to: base) == nil)
    }

    // MARK: Placement rules

    /// The brick the current tool lays, at the origin.
    private var toolBrick: PlacedBrick? {
        switch buildTool {
        case .brick:
            let m = buildShape.materials.contains(buildMaterial) ? buildMaterial : .stone
            return PlacedBrick(shape: buildShape, material: m, x: 0, y: 0, z: 0, rot: buildRot)
        case .heart: return PlacedBrick(shape: .cube, material: .heart, x: 0, y: 0, z: 0)
        case .decoy: return PlacedBrick(shape: .cube, material: .decoy, x: 0, y: 0, z: 0)
        case .moat: return PlacedBrick(shape: .moat, material: .stone, x: 0, y: 0, z: 0)
        default: return nil
        }
    }

    /// The bricks the current tool would add for a touch, snapped to the grid.
    func candidate(for hit: BenchHit) -> [PlacedBrick]? {
        let s = Float(BK.step)
        let ext: (x: Int, z: Int)
        if buildTool == .stamp {
            let f = buildStamp.footprint
            ext = buildRot % 2 == 0 ? (f.x, f.z) : (f.z, f.x)
        } else if let b = toolBrick {
            ext = (b.extent.x, b.extent.z)
        } else { return nil }

        func snap(_ v: Float, _ e: Int, _ limit: Int) -> Int { min(max(Int((v / s - Float(e) / 2).rounded()), 0), max(0, limit - e)) }
        var x: Int, z: Int, below: Int
        switch hit {
        case .ground(let p):
            x = snap(p.x, ext.x, BK.maxX); z = snap(p.z, ext.z, BK.maxZ); below = 0
        case .brick(let i, let p, let n):
            let b = draft.bricks[i], e = b.extent
            if n.y > 0.6 || buildTool == .moat {
                x = snap(p.x, ext.x, BK.maxX); z = snap(p.z, ext.z, BK.maxZ); below = b.y + e.y
            } else if abs(n.x) >= abs(n.z) {
                x = n.x > 0 ? b.x + e.x : b.x - ext.x
                z = snap(p.z, ext.z, BK.maxZ)
                below = Int((p.y / s).rounded(.down))
            } else {
                z = n.z > 0 ? b.z + e.z : b.z - ext.z
                x = snap(p.x, ext.x, BK.maxX)
                below = Int((p.y / s).rounded(.down))
            }
        }
        if buildTool == .moat { return [PlacedBrick(shape: .moat, material: .stone, x: x, y: 0, z: z)] }
        let y = restingHeight(x: x, z: z, ext: ext, atMost: below)
        if buildTool == .stamp {
            return buildStamp.bricks(x: x, z: z, rot: buildRot, material: buildMaterial).map { var b = $0; b.y += y; return b }
        }
        guard var b = toolBrick else { return nil }
        b.x = x; b.y = y; b.z = z
        return [b]
    }

    /// The top of the highest visible brick under a footprint whose top is no higher than `atMost`.
    private func restingHeight(x: Int, z: Int, ext: (x: Int, z: Int), atMost: Int) -> Int {
        let limit = buildLayer * BK.steps
        var best = 0
        for b in draft.bricks where !b.shape.isDecal && b.y < limit {
            let e = b.extent, top = b.y + e.y
            guard top <= atMost, top > best, b.x < x + ext.x, x < b.x + e.x, b.z < z + ext.z, z < b.z + e.z else { continue }
            best = top
        }
        return best
    }

    /// Why these bricks cannot be added to a design, or nil when they can.
    func verdict(adding add: [PlacedBrick], to d: BrickDesign) -> String? {
        func flat(_ a: PlacedBrick, _ b: PlacedBrick) -> Bool {
            let p = a.extent, q = b.extent
            return a.x < b.x + q.x && b.x < a.x + p.x && a.z < b.z + q.z && b.z < a.z + p.z
        }
        for b in add {
            if !b.inBounds { return b.y + b.extent.y > BK.maxY ? Tx.tooHigh : Tx.offPlot }
            if b.y >= buildLayer * BK.steps { return Tx.aboveLayer }
        }
        var next = d
        for b in add {
            guard next.fits(b) else { return Tx.noRoom }
            if b.shape.isDecal, next.bricks.contains(where: { !$0.shape.isDecal && $0.y == 0 && flat($0, b) }) { return Tx.noRoom }
            if !b.shape.isDecal, b.y == 0, next.bricks.contains(where: { $0.shape.isDecal && flat($0, b) }) { return Tx.onMoat }
            next.bricks.append(b)
        }
        let fresh = Set(d.bricks.count..<next.bricks.count)
        let floating = next.floating.filter(fresh.contains)
        if let i = floating.first {
            let b = next.bricks[i]
            let onTop = next.bricks.contains { $0.shape.isTop && $0.y + $0.extent.y == b.y && flat($0, b) }
            return onTop ? Tx.onRoof : Tx.brickProblem(.floating)
        }
        if next.bricks.count > BK.maxBricks { return Tx.brickProblem(.tooMany) }
        if next.decoys > BK.maxDecoys { return Tx.brickProblem(.manyDecoys) }
        if next.cost > BK.budget { return Tx.noCoins }
        return nil
    }

    // MARK: Test gravity

    func testGravity() {
        guard !testingGravity, let bench, !draft.bricks.isEmpty else { return }
        buildCancel()
        testingGravity = true
        sfx.play(.fire)
        thump(.heavy)
        bench.testGravity(seconds: 3) { [weak self] moved in
            guard let self else { return }
            self.testingGravity = false
            self.refreshBench()
            self.flash(moved == 0 ? Tx.gravityStands : Tx.gravityFell(moved))
            if moved > 0 { self.sfx.play(.hit) }
        }
    }

    // MARK: Codes

    /// The draft as a code to send, once it is a castle that can be played.
    var draftCode: String? { draft.problem == nil ? CastleCode.encode(draft) : nil }

    func pasteCastle(_ text: String) {
        guard let d = CastleCode.decode(text) else { flash(Tx.codeInvalid); sfx.play(.thud); return }
        loadDraft(d)
        flash(Tx.codeLoaded)
    }

    // MARK: Debug launch arguments

    #if DEBUG
    /// "-screen builder" opens the builder at launch; "-demoCastle N" loads a demo into it
    /// (0 showcase, 1… presets, 50 every stamp, 60 a broken castle); "-demoGhost" shows a ghost
    /// brick at the middle of the screen; "-demoGravity" runs Test gravity; "-demoSave" saves after 8 s; "-demoTool erase|stamp|look",
    /// "-demoShape N", "-demoMaterial N" and "-demoLayer N" set the tray.
    func builderLaunchHooks() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        guard value("-screen") == "builder" || value("-demoCastle") != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            panel = .home
            openBuilder()
            if let n = value("-demoCastle").flatMap(Int.init), let d = BuilderDemo.design(n) { draft = d; refreshBench() }
            if let n = value("-demoShape").flatMap(Int.init), let s = BrickShape(rawValue: n) { buildShape = s }
            if let n = value("-demoMaterial").flatMap(Int.init), let m = BrickMaterial(rawValue: n) { buildMaterial = m }
            if let n = value("-demoLayer").flatMap(Int.init) { setLayer(n) }
            if let n = value("-demoRot").flatMap(Int.init) { buildRot = n & 3 }
            switch value("-demoTool") {
            case "erase": buildTool = .erase
            case "stamp": buildTool = .stamp; if let n = value("-demoStamp").flatMap(Int.init), let s = Stamp(rawValue: n) { buildStamp = s }
            case "look": buildTool = .look
            case "heart": buildTool = .heart
            case "moat": buildTool = .moat
            default: break
            }
            if let at = value("-demoGhost") {
                let parts = at.split(separator: ",").compactMap { Double($0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                    let size = UIScreen.main.bounds.size
                    let p = parts.count == 2 ? CGPoint(x: size.width * parts[0], y: size.height * parts[1]) : CGPoint(x: size.width / 2, y: size.height / 2)
                    buildDown(p)
                }
            }
            if args.contains("-demoGravity") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in testGravity() }
            }
            if args.contains("-demoSave") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in saveCastle() }
            }
        }
    }
    #endif
}

/// Ready-made castles offered in the builder tray.
enum BuilderCatalog {
    static var castles: [BrickDesign] { Presets.all }
}

#if DEBUG
/// Castles for screenshots and manual testing.
enum BuilderDemo {
    static func design(_ n: Int) -> BrickDesign? {
        switch n {
        case 0: return showcase
        case 50: return stampSampler
        case 60: return broken
        default: return BuilderCatalog.castles.indices.contains(n - 1) ? BuilderCatalog.castles[n - 1] : nil
        }
    }

    /// Towers with cone roofs at the corners, two-course walls with battlements, an iron gate
    /// arch, a roofed keep around the heart, a decoy and a moat at the gate.
    static var showcase: BrickDesign {
        var d = BrickDesign(heart: .crystal)
        func add(_ s: BrickShape, _ m: BrickMaterial, _ x: Int, _ y: Int, _ z: Int, rot: Int = 0) {
            d.bricks.append(PlacedBrick(shape: s, material: m, x: x, y: y, z: z, rot: rot))
        }
        // Corner towers: stone below, wood above, windows at the front, cone roofs.
        for (x, z, front) in [(0, 0, false), (0, 26, false), (18, 0, true), (18, 26, true)] {
            for level in 0..<3 {
                for (dx, dz) in [(0, 0), (2, 0), (0, 2), (2, 2)] {
                    let m: BrickMaterial = level == 0 || (front && level == 1) ? .stone : .wood
                    let shape: BrickShape = front && level == 1 && dx == 2 ? .window : .cube
                    add(shape, m, x + dx, level * 2, z + dz)
                }
            }
            add(.coneRoof, front ? .stone : .wood, x, 6, z)
        }
        // Front wall with an iron gate arch and battlements.
        add(.beam4, .stone, 18, 0, 4); add(.arch, .iron, 18, 0, 12); add(.beam4, .stone, 18, 0, 18)
        add(.beam4, .wood, 18, 2, 4); add(.beam4, .wood, 18, 2, 18)
        for z in stride(from: 4, through: 24, by: 4) { add(.battlement, .stone, 18, 4, z) }
        // Side walls: stone below, wood on the left and ice on the right above.
        for (z, top) in [(0, BrickMaterial.wood), (28, .ice)] {
            add(.beam4, .stone, 4, 0, z, rot: 1); add(.beam3, z == 0 ? .wood : .stone, 12, 0, z, rot: 1)
            add(.beam4, top, 4, 2, z, rot: 1); add(.beam3, top, 12, 2, z, rot: 1)
        }
        // Back wall in wood.
        for y in [0, 2] { add(.beam4, .wood, 0, y, 4); add(.beam3, .wood, 0, y, 12); add(.beam4, .wood, 0, y, 18) }
        // The keep: a ring of wood around the heart under a pyramid roof.
        add(.cube, .heart, 10, 0, 14)
        for (dx, dz) in [(0, 0), (2, 0), (4, 0), (0, 2), (4, 2), (0, 4), (2, 4), (4, 4)] { add(.cube, .wood, 8 + dx, 0, 12 + dz) }
        add(.pyramidRoof, .wood, 9, 2, 13)
        // A decoy on a little wedge-roofed platform, and a moat before the gate.
        add(.half, .stone, 5, 0, 22); add(.cube, .decoy, 5, 1, 22)
        add(.wedge, .wood, 7, 0, 22, rot: 0)
        add(.moat, .stone, 20, 0, 13); add(.moat, .stone, 20, 0, 15)
        return d
    }

    /// Every stamp once, packed across the plot.
    static var stampSampler: BrickDesign {
        var d = BrickDesign(heart: .crystal)
        var x = 0, z = 0, row = 0
        for s in Stamp.allCases {
            let f = s.footprint
            if z + f.z > BK.maxZ { z = 0; x += row + 1; row = 0 }
            guard x + f.x <= BK.maxX else { break }
            d.bricks += s.bricks(x: x, z: z, rot: 0, material: s.rawValue % 2 == 0 ? .stone : .wood)
            z += f.z + 1; row = max(row, f.x)
        }
        return d
    }

    /// No heart and a floating beam: shows the validation note and the red warning glow.
    static var broken: BrickDesign {
        var d = showcase
        d.bricks.removeAll { $0.material == .heart }
        d.bricks.append(PlacedBrick(shape: .beam3, material: .wood, x: 8, y: 6, z: 2))
        return d
    }
}
#endif
