import Foundation
import GameKit

/// Trophy brackets. The floor is the trophy count where the league starts.
enum League: Int, CaseIterable {
    case bronze, silver, gold, diamond, legend
    var floor: Int { [0, 100, 250, 500, 900][rawValue] }
    var tint: UInt32 { [0xb9773a, 0x8e9aa6, 0xe0ac1b, 0x3aa7dc, 0x8a4fd6][rawValue] }
    static func of(_ trophies: Int) -> League { allCases.last { trophies >= $0.floor } ?? .bronze }
    var next: League? { League(rawValue: rawValue + 1) }
}

/// Cosmetic cannonballs, unlocked by level.
struct BallStyle: Identifiable {
    let id: Int
    let level: Int
    let ball: UInt32
    let trail: UInt32
    static let all = [
        BallStyle(id: 0, level: 1, ball: 0x1b2a34, trail: 0xffffff),
        BallStyle(id: 1, level: 3, ball: 0x5a1a10, trail: 0xff8a1e),
        BallStyle(id: 2, level: 6, ball: 0x1c4a7a, trail: 0x8fe3ff),
        BallStyle(id: 3, level: 10, ball: 0xd9a514, trail: 0xffe27a),
    ]
}

struct MatchStats: Equatable {
    var shots = 0, hits = 0, crits = 0, bestHit = 0, megas = 0, topStreak = 0
    var accuracy: Int { shots == 0 ? 0 : Int((Double(hits) / Double(shots) * 100).rounded()) }
}

enum RewardMode {
    case computer(Difficulty)
    /// The opponent's trophy count, when they shared it.
    case online(opponent: Int?)

    var xpFactor: Double {
        switch self {
        case .computer(.kolay): return 0.6
        case .computer(.orta): return 1.0
        case .computer(.zor): return 1.4
        case .online: return 1.5
        }
    }

    /// Trophies at stake. Online they follow the rating gap: beating a stronger player pays more
    /// and losing to one costs less.
    func trophies(mine: Int) -> (win: Int, loss: Int) {
        switch self {
        case .computer(.kolay): return (6, 4)
        case .computer(.orta): return (12, 8)
        case .computer(.zor): return (20, 10)
        case .online(let theirs):
            guard let theirs else { return (25, 20) }
            let expected = 1 / (1 + pow(10, Double(theirs - mine) / 400))
            return (min(40, max(10, Int((50 * (1 - expected)).rounded()))), min(32, max(8, Int((40 * expected).rounded()))))
        }
    }
}

/// A goal for the day. Progress adds up across matches.
struct Mission: Identifiable, Equatable {
    let id: String
    let target: Int

    static let xp = 40
    static let bigHit = 12
    static let pool = [
        Mission(id: "win", target: 1), Mission(id: "hits", target: 8), Mission(id: "crits", target: 2),
        Mission(id: "megas", target: 2), Mission(id: "bighit", target: 1), Mission(id: "siege", target: 1),
        Mission(id: "streak", target: 4),
    ]

    /// Three missions per day, the same for every player.
    static func today(_ day: String) -> [Mission] {
        var r = Mulberry32(Challenge.seed(day: "missions-" + day))
        var left = pool, out: [Mission] = []
        for _ in 0..<3 { out.append(left.remove(at: min(left.count - 1, Int(r.next() * Double(left.count))))) }
        return out
    }
}

/// What one finished match changed in the profile; shown on the result card.
struct Reward: Equatable {
    var xp = 0
    var trophies = 0
    var firstWin = false
    var levelBefore = 1, levelAfter = 1
    var progressBefore = 0.0, progressAfter = 0.0
    var unlockedBall: Int?
    var promotedTo: League?
    var totalTrophies = 0
    var missions: [Mission] = []
    // Daily siege only
    var siegeFirstToday = false
    var siegeNewBest = false
    var siegeBest = 0, siegeRecord = 0
}

/// The player's lasting record: level, trophies, streaks and totals. Stored on the device.
struct Profile: Codable, Equatable {
    var name = ""
    var xp = 0, trophies = 0
    var wins = 0, losses = 0, streak = 0, bestStreak = 0
    var shots = 0, hits = 0, crits = 0, bestHit = 0
    var lastWinDay = "", lastPlayDay = "", dayStreak = 0
    var ballStyle = 0
    var siegeDay = "", siegeBest = 0, siegeRecord = 0
    var missionDay = "", missionProgress: [String: Int] = [:], missionsDone: [String] = []

    static let storageKey = "profile.v1"
    /// Game Center leaderboards. Create them in App Store Connect with these IDs.
    static let trophyBoard = "kalesavasi.trophies"
    static let siegeBoard = "kalesavasi.daily"
    static let nameLimit = 14

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ k: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: k)) ?? 0 }
        func str(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? "" }
        name = str(.name)
        xp = int(.xp); trophies = int(.trophies)
        wins = int(.wins); losses = int(.losses); streak = int(.streak); bestStreak = int(.bestStreak)
        shots = int(.shots); hits = int(.hits); crits = int(.crits); bestHit = int(.bestHit)
        lastWinDay = str(.lastWinDay); lastPlayDay = str(.lastPlayDay); dayStreak = int(.dayStreak)
        ballStyle = int(.ballStyle)
        siegeDay = str(.siegeDay); siegeBest = int(.siegeBest); siegeRecord = int(.siegeRecord)
        missionDay = str(.missionDay)
        missionProgress = (try? c.decodeIfPresent([String: Int].self, forKey: .missionProgress)) ?? [:]
        missionsDone = (try? c.decodeIfPresent([String].self, forKey: .missionsDone)) ?? []
    }

    static func xpToNext(_ level: Int) -> Int { 100 + 60 * (level - 1) }

    private var levelSplit: (level: Int, into: Int) {
        var l = 1, rest = xp
        while rest >= Profile.xpToNext(l) { rest -= Profile.xpToNext(l); l += 1 }
        return (l, rest)
    }
    var level: Int { levelSplit.level }
    var levelProgress: Double { Double(levelSplit.into) / Double(Profile.xpToNext(levelSplit.level)) }
    var league: League { League.of(trophies) }
    var accuracy: Int { shots == 0 ? 0 : Int((Double(hits) / Double(shots) * 100).rounded()) }
    func owns(_ ball: BallStyle) -> Bool { level >= ball.level }

    /// Keeps a name short and on one line; used for our own name and for names received from an opponent.
    static func cleanName(_ raw: String) -> String {
        let flat = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) }
        return String(String(String.UnicodeScalarView(flat)).trimmingCharacters(in: .whitespaces).prefix(nameLimit))
    }

    static func load() -> Profile {
        var p = Profile()
        if let data = UserDefaults.standard.data(forKey: storageKey), let saved = try? JSONDecoder().decode(Profile.self, from: data) { p = saved }
        if p.name.isEmpty {
            p.name = "\(Tx.gunner)-\(Int.random(in: 1000...9999))"
            p.save()
        }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Profile.storageKey) }
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(trophies, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Profile.trophyBoard]) { _ in }
        if siegeDay == Profile.dayString(), siegeBest > 0 {
            GKLeaderboard.submitScore(siegeBest, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Profile.siegeBoard]) { _ in }
        }
    }

    static func dayString(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Today's best siege score, or nil if it has not been played today.
    func siegeToday(_ day: String = Profile.dayString()) -> Int? { siegeDay == day ? siegeBest : nil }

    /// Today's missions with progress so far.
    func missionRows(_ day: String = Profile.dayString()) -> [(mission: Mission, progress: Int, done: Bool)] {
        Mission.today(day).map { m in
            let fresh = missionDay == day
            return (m, fresh ? min(m.target, missionProgress[m.id] ?? 0) : 0, fresh && missionsDone.contains(m.id))
        }
    }

    private mutating func touchDay(_ now: Date) -> String {
        let today = Profile.dayString(now)
        if lastPlayDay != today {
            let yesterday = Profile.dayString(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
            dayStreak = lastPlayDay == yesterday ? dayStreak + 1 : 1
            lastPlayDay = today
        }
        return today
    }

    private mutating func advanceMissions(stats: MatchStats, won: Bool, siege: Bool, day: String) -> [Mission] {
        if missionDay != day { missionDay = day; missionProgress = [:]; missionsDone = [] }
        var completed: [Mission] = []
        for m in Mission.today(day) where !missionsDone.contains(m.id) {
            var v = missionProgress[m.id] ?? 0
            switch m.id {
            case "win": v += won ? 1 : 0
            case "hits": v += stats.hits
            case "crits": v += stats.crits
            case "megas": v += stats.megas
            case "bighit": v = max(v, stats.bestHit >= Mission.bigHit ? 1 : 0)
            case "siege": v = max(v, siege ? 1 : 0)
            case "streak": v = max(v, stats.topStreak)
            default: break
            }
            v = min(v, m.target)
            missionProgress[m.id] = v
            if v >= m.target { missionsDone.append(m.id); completed.append(m) }
        }
        return completed
    }

    private mutating func settle(_ r: inout Reward, leagueBefore: League) {
        xp += r.xp
        trophies += r.trophies
        r.levelAfter = level
        r.progressAfter = levelProgress
        r.totalTrophies = trophies
        if league.rawValue > leagueBefore.rawValue { r.promotedTo = league }
        if r.levelAfter > r.levelBefore {
            r.unlockedBall = BallStyle.all.last { $0.level > r.levelBefore && $0.level <= r.levelAfter }?.id
        }
    }

    /// Books a finished match and returns what it earned. `forfeit` is a match the player walked out of.
    mutating func record(won: Bool, mode: RewardMode, stats: MatchStats, forfeit: Bool = false, now: Date = Date()) -> Reward {
        var r = Reward()
        r.levelBefore = level
        r.progressBefore = levelProgress
        let leagueBefore = league
        let today = touchDay(now)
        shots += stats.shots; hits += stats.hits; crits += stats.crits
        bestHit = max(bestHit, stats.bestHit)
        let stake = mode.trophies(mine: trophies)
        if won {
            wins += 1; streak += 1; bestStreak = max(bestStreak, streak)
            r.firstWin = lastWinDay != today
            lastWinDay = today
        } else {
            losses += 1; streak = 0
        }
        if !forfeit {
            var gain = 15.0 + (won ? 45 : 0) + Double(stats.accuracy) * 0.3 + Double(min(30, stats.crits * 6))
            if won { gain += Double(5 * min(streak, 5)) }
            r.xp = Int((gain * mode.xpFactor).rounded()) + (r.firstWin ? 50 : 0)
            r.missions = advanceMissions(stats: stats, won: won, siege: false, day: today)
            r.xp += r.missions.count * Mission.xp
        }
        r.trophies = won ? stake.win : -min(trophies, stake.loss)
        settle(&r, leagueBefore: leagueBefore)
        return r
    }

    /// Books a daily siege run. XP is paid once per day; the score counts every time.
    mutating func recordSiege(score: Int, stats: MatchStats, now: Date = Date()) -> Reward {
        var r = Reward()
        r.levelBefore = level
        r.progressBefore = levelProgress
        let leagueBefore = league
        let today = touchDay(now)
        shots += stats.shots; hits += stats.hits; crits += stats.crits
        bestHit = max(bestHit, stats.bestHit)
        r.siegeFirstToday = siegeDay != today
        if r.siegeFirstToday { siegeDay = today; siegeBest = 0 }
        r.siegeNewBest = score > siegeBest
        siegeBest = max(siegeBest, score)
        siegeRecord = max(siegeRecord, score)
        r.siegeBest = siegeBest
        r.siegeRecord = siegeRecord
        r.xp = r.siegeFirstToday ? 60 : 0
        r.missions = advanceMissions(stats: stats, won: false, siege: true, day: today)
        r.xp += r.missions.count * Mission.xp
        settle(&r, leagueBefore: leagueBefore)
        return r
    }
}
