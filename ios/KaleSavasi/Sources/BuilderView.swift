import SwiftUI

// The castle builder: the 3D canvas's tools, tray and HUD.

enum PieceLook {
    static func color(_ k: PieceKind) -> Color {
        switch k {
        case .wallLow: return Color(hex: 0xb7bcc0)
        case .wallHigh: return Color(hex: 0x858b91)
        case .tower: return Color(hex: 0x5b8fd6)
        case .tallTower: return Color(hex: 0x2459b8)
        case .bastion: return Color(hex: 0x9a7b52)
        case .keep: return Color(hex: 0xc62d1f)
        case .heart: return Paint.heart
        case .wallStrong: return Color(hex: 0x4e555c)
        case .shelter: return Color(hex: 0x8f7e66)
        case .moat: return Color(hex: 0x3f8fc4)
        case .decoy: return Color(hex: 0xe58bb0)
        }
    }
    static func icon(_ k: PieceKind) -> String {
        switch k {
        case .wallLow: return "rectangle.fill"
        case .wallHigh: return "rectangle.portrait.fill"
        case .tower: return "building.fill"
        case .tallTower: return "building.2.fill"
        case .bastion: return "square.fill"
        case .keep: return "crown.fill"
        case .heart: return "heart.fill"
        case .wallStrong: return "shield.fill"
        case .shelter: return "house.fill"
        case .moat: return "water.waves"
        case .decoy: return "heart"
        }
    }
}

/// The tile grid of a castle, seen from above with the enemy at the top.
struct DesignGrid: View {
    let design: CastleDesign
    let cell: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let rows = CastleDesign.rows, cols = CastleDesign.cols
            for r in 0...rows {
                var p = Path(); p.move(to: CGPoint(x: 0, y: CGFloat(r) * cell)); p.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * cell))
                ctx.stroke(p, with: .color(Paint.ink.opacity(0.14)), lineWidth: 1)
            }
            for c in 0...cols {
                var p = Path(); p.move(to: CGPoint(x: CGFloat(c) * cell, y: 0)); p.addLine(to: CGPoint(x: CGFloat(c) * cell, y: size.height))
                ctx.stroke(p, with: .color(Paint.ink.opacity(0.14)), lineWidth: 1)
            }
            // Shelters first: whatever sits in the middle of one is drawn on top.
            for piece in design.pieces.sorted(by: { ($0.kind == .shelter ? 0 : 1) < ($1.kind == .shelter ? 0 : 1) }) {
                let n = piece.kind.span
                // Row 0 is the back of the castle, drawn at the bottom.
                let rect = CGRect(x: CGFloat(piece.tz) * cell, y: CGFloat(rows - piece.tx - n) * cell, width: CGFloat(n) * cell, height: CGFloat(n) * cell).insetBy(dx: 1, dy: 1)
                ctx.fill(Path(roundedRect: rect, cornerRadius: n == 1 ? 3 : 5), with: .color(PieceLook.color(piece.kind)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: n == 1 ? 3 : 5), with: .color(Paint.ink), lineWidth: 1.5)
                if piece.kind == .shelter {
                    let hole = CGRect(x: rect.minX + cell - 1, y: rect.minY + cell - 1, width: cell, height: cell).insetBy(dx: 2, dy: 2)
                    ctx.fill(Path(roundedRect: hole, cornerRadius: 3), with: .color(Color(hex: 0xe9efe2)))
                    ctx.stroke(Path(roundedRect: hole, cornerRadius: 3), with: .color(Paint.ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    let mark = ctx.resolve(Image(systemName: PieceLook.icon(piece.kind)))
                    ctx.draw(mark, in: CGRect(x: rect.minX + 3, y: rect.minY + 3, width: cell * 0.7, height: cell * 0.7))
                } else if piece.kind == .heart || piece.kind == .decoy || piece.kind == .wallStrong || piece.kind == .moat {
                    var mark = ctx.resolve(Image(systemName: PieceLook.icon(piece.kind)))
                    mark.shading = .color(.white)
                    ctx.draw(mark, in: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18))
                } else if n > 1 {
                    let mark = ctx.resolve(Image(systemName: PieceLook.icon(piece.kind)))
                    ctx.draw(mark, in: rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.28))
                }
            }
        }
        .frame(width: cell * CGFloat(CastleDesign.cols), height: cell * CGFloat(CastleDesign.rows))
    }
}

struct BuilderView: View {
    @EnvironmentObject var game: GameController
    private let cell: CGFloat = 20

    var body: some View {
        let cost = game.draft.cost
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Tx.buildCastle).font(Paint.heavy(18)).foregroundStyle(Paint.ink)
                    Spacer()
                    Text(Tx.stone(cost, CastleDesign.budget)).font(Paint.text(13, .heavy)).monospacedDigit()
                        .foregroundStyle(cost > CastleDesign.budget ? Paint.red : Paint.ink)
                }
                Meter(value: Double(cost) / Double(CastleDesign.budget), color: cost < CastleDesign.minimum ? Paint.muted : Paint.green, height: 7)
                Text(Tx.builderFront).font(Paint.text(9, .heavy)).foregroundStyle(Paint.red).frame(maxWidth: .infinity)
                DesignGrid(design: game.draft, cell: cell)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xe9efe2)))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Paint.ink, lineWidth: 2))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let col = Int(v.location.x / cell), row = CastleDesign.rows - 1 - Int(v.location.y / cell)
                            game.paint(row: row, col: col, fresh: v.translation == .zero)
                        }
                        .onEnded { _ in game.strokeEnded() })
                    .accessibilityLabel(Tx.buildCastle)
                Text(Tx.builderBack).font(Paint.text(9, .heavy)).foregroundStyle(Paint.muted).frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: cell * CGFloat(CastleDesign.cols) + 24)
            .modifier(Plate(radius: 16))
            VStack(spacing: 4) {
                LazyVGrid(columns: [GridItem(.fixed(38), spacing: 4), GridItem(.fixed(38), spacing: 4)], spacing: 4) {
                    ForEach(PieceKind.allCases) { k in toolButton(k) }
                    Button { game.pick(tool: nil) } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "eraser.fill").font(.system(size: 13, weight: .bold))
                            Text(Tx.eraser).font(Paint.text(8, .heavy))
                        }
                        .foregroundStyle(Paint.ink).frame(width: 38, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8).fill(game.erasing ? Paint.yellow : Paint.track.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paint.ink, lineWidth: game.erasing ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Tx.eraser)
                }
            }
            .padding(8)
            .modifier(Plate(radius: 16))
            .padding(.leading, 6)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Button { game.closeBuilder() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(Paint.ink)
                        .frame(width: 38, height: 34).modifier(Plate(radius: 10))
                }
                .accessibilityLabel(Tx.close)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Tx.heartType).font(Paint.text(11, .heavy)).foregroundStyle(.white)
                    HStack(spacing: 5) {
                        ForEach(HeartKind.allCases) { h in heartButton(h) }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Paint.ink.opacity(0.7)))
                HStack(spacing: 8) {
                    if let code = game.draftCode {
                        ShareLink(item: Tx.shareMessage(code)) { Label(Tx.shareCastle, systemImage: "square.and.arrow.up") }
                            .buttonStyle(ChunkyButton(color: .white, dark: Paint.ink, fg: Paint.ink, size: 13, fill: false, compact: true))
                    }
                    PasteButton(payloadType: String.self) { strings in
                        DispatchQueue.main.async { game.pasteCastle(strings.first ?? "") }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .tint(Paint.ink)
                }
                Spacer()
                Text(game.builderNote ?? toolLine).font(Paint.text(13, .heavy)).foregroundStyle(.white).multilineTextAlignment(.trailing)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12).fill((game.builderNote == nil ? Paint.ink : Paint.red).opacity(0.85)))
                    .frame(maxWidth: 300, alignment: .trailing)
                HStack(spacing: 10) {
                    Button(Tx.classicLayout) { game.loadDraft(.classic) }
                        .buttonStyle(ChunkyButton(color: .white, dark: Paint.ink, fg: Paint.ink, size: 14, fill: false, compact: true))
                    Button(Tx.clearAll) { game.loadDraft(CastleDesign()) }
                        .buttonStyle(ChunkyButton(color: .white, dark: Paint.ink, fg: Paint.ink, size: 14, fill: false, compact: true))
                    Button { game.saveCastle() } label: { Label(Tx.save, systemImage: "checkmark") }
                        .buttonStyle(ChunkyButton(color: Paint.green, dark: Color(hex: 0x1f6e3a), size: 16, fill: false))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
    }

    private var toolLine: String {
        if game.erasing { return Tx.builderHint }
        guard let k = game.tool else { return Tx.builderHint }
        let line = "\(Tx.piece(k)) · \(CastleDesign.cost(of: k))"
        return Tx.pieceInfo(k).map { line + "\n" + $0 } ?? line
    }

    private func heartButton(_ h: HeartKind) -> some View {
        let owned = game.profile.owns(h), on = game.draft.heart == h
        return Button { game.pick(heart: h) } label: {
            ZStack {
                Image(systemName: "heart.fill").font(.system(size: 15, weight: .black)).foregroundStyle(Color(hex: Look.heartColors(h).glow))
                if !owned { Image(systemName: "lock.fill").font(.system(size: 8, weight: .black)).foregroundStyle(.white) }
            }
            .frame(width: 34, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Paint.yellow : .white.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paint.ink, lineWidth: on ? 2.5 : 1))
            .opacity(owned ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Tx.heart(h))\(owned ? "" : ", " + Tx.heartLocked(h.level))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toolButton(_ k: PieceKind) -> some View {
        let owned = game.profile.owns(k), on = !game.erasing && game.tool == k
        return Button { game.pick(tool: k) } label: {
            VStack(spacing: 1) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(PieceLook.color(k)).frame(width: 18, height: 14)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Paint.ink, lineWidth: 1))
                    if k == .heart { Image(systemName: "heart.fill").font(.system(size: 8, weight: .black)).foregroundStyle(.white) }
                    if !owned { Image(systemName: "lock.fill").font(.system(size: 8, weight: .black)).foregroundStyle(.white) }
                }
                Text("\(CastleDesign.cost(of: k))").font(Paint.text(9, .heavy)).monospacedDigit()
            }
            .foregroundStyle(Paint.ink).frame(width: 38, height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Paint.yellow : Paint.track.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paint.ink, lineWidth: on ? 2.5 : 1))
            .opacity(owned ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Tx.piece(k)), \(CastleDesign.cost(of: k))\(owned ? "" : ", " + Tx.locked)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
