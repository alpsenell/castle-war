import SwiftUI
import SceneKit

// The castle builder's actions. Its stored state lives in `GameController`.

extension GameController {
    func openBuilder() {
        sfx.play(.tick)
        draft = profile.castle
        tool = .wallLow; erasing = false; builderNote = nil; lastTile = nil
        screen = .builder
        cam = .target
        viewSeat = 0
        orbitA = 0.75; orbitH = 30; orbitR = 54; orbitR0 = 54
        world.preview(draft)
    }

    func pick(tool kind: PieceKind?) {
        guard kind == nil || profile.owns(kind!) else { builderNote = Tx.needStars(Profile.starsNeeded(kind!)); return }
        tool = kind
        erasing = kind == nil
        builderNote = nil
        sfx.play(.tick)
    }

    /// A touch on the builder grid. `fresh` is the first touch of a stroke; dragging on only lays walls or erases.
    func paint(row: Int, col: Int, fresh: Bool) {
        guard screen == .builder, row >= 0, row < CastleDesign.rows, col >= 0, col < CastleDesign.cols else { return }
        if !fresh, let t = lastTile, t == (row, col) { return }
        lastTile = (row, col)
        if erasing {
            if let i = draft.piece(atRow: row, col: col) { draft.pieces.remove(at: i); draftChanged() }
            return
        }
        guard let kind = tool else { return }
        if !fresh && kind.span > 1 { return }
        let n = kind.span
        let tx = min(max(row - (n - 1) / 2, 0), CastleDesign.rows - n), tz = min(max(col - (n - 1) / 2, 0), CastleDesign.cols - n)
        var next = draft
        if n == 1, let i = next.piece(atRow: row, col: col) {
            let old = next.pieces[i]
            if old.kind == kind { if fresh { next.pieces.remove(at: i); draft = next; draftChanged() }; return }   // tap again to take it away
            guard old.kind.span == 1 else { if fresh { builderNote = Tx.noRoom }; return }
            next.pieces.remove(at: i)                                                                              // swap one wall for the other
        }
        if kind == .keep || kind == .heart { next.pieces.removeAll { $0.kind == kind } }      // only one of each: placing it again moves it
        guard next.fits(kind, row: tx, col: tz) else { if fresh { builderNote = Tx.noRoom }; return }
        next.pieces.append(Piece(kind: kind, tx: tx, tz: tz))
        guard next.cost <= CastleDesign.budget else { builderNote = Tx.noStone; return }
        guard next.decoys <= CastleDesign.maxDecoys else { builderNote = Tx.problem(.manyDecoys); return }
        draft = next
        draftChanged()
    }

    func strokeEnded() { lastTile = nil }

    private func draftChanged() {
        builderNote = nil
        world.preview(draft)
    }

    func loadDraft(_ d: CastleDesign) { draft = d; draftChanged(); sfx.play(.tick) }

    func pick(heart h: HeartKind) {
        guard profile.owns(h) else { builderNote = Tx.heartLocked(h.level); return }
        var next = draft
        next.heart = h
        guard next.cost <= CastleDesign.budget else { builderNote = Tx.noStone; return }
        draft = next
        draftChanged()
        builderNote = Tx.heart(h) + ": " + Tx.heartInfo(h)
        sfx.play(.tick)
    }

    /// The draft as a code to send, once it is a castle that can be played.
    var draftCode: String? { draft.problem == nil ? CastleCode.encode(draft) : nil }

    func pasteCastle(_ text: String) {
        guard let d = CastleCode.decode(text) else { builderNote = Tx.codeInvalid; sfx.play(.thud); return }
        loadDraft(d)
        builderNote = Tx.codeLoaded
    }

    func saveCastle() {
        if let pr = draft.problem { builderNote = Tx.problem(pr); return }
        profile.design = draft.encoded
        profile.castlesSaved += 1
        let fresh = profile.unlockAchievements()
        profile.save()
        sfx.play(.charged)
        closeBuilder()
        show(toast: fresh.first.map(Tx.achievementDone) ?? Tx.saved)
    }

    func closeBuilder() {
        screen = .menu
        panel = .home
        cam = .menu
        menuA = Double(atan2(camPos.x, camPos.z))
        resetBackdrop()
    }
}
