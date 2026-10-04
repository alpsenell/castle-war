import Foundation

enum Language: String, CaseIterable, Identifiable {
    case tr, en
    var id: String { rawValue }
    var label: String { self == .tr ? "Türkçe" : "English" }
}

/// Every piece of text the player sees, in Turkish and English.
/// The language follows the device on first launch and can be switched from the menu.
enum Tx {
    private(set) static var lang: Language = {
        if let raw = UserDefaults.standard.string(forKey: "language"), let l = Language(rawValue: raw) { return l }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("tr") ? .tr : .en
    }()

    static func set(_ l: Language) {
        lang = l
        UserDefaults.standard.set(l.rawValue, forKey: "language")
    }

    private static func p(_ tr: String, _ en: String) -> String { lang == .tr ? tr : en }

    /// Turkish writes the percent sign first.
    static func pct(_ n: Int) -> String { lang == .tr ? "%\(n)" : "\(n)%" }

    // MARK: Menu
    static var gameName: String { p("Kale Savaşı", "Castle War") }
    static var logoTop: String { p("KALE", "CASTLE") }
    static var logoBottom: String { p("SAVAŞI", "WAR") }
    static var tagline: String { p("Sırayla ateş et, duvarları aş ve rakibin kalbini kır. Kalbi düşen kaybeder.", "Take turns firing, break through the walls and shatter the enemy heart. Lose your heart and you lose.") }
    static var vsComputer: String { p("Yapay zekâya karşı", "Play the computer") }
    static var difficulty: String { p("Zorluk", "Difficulty") }
    static func name(_ d: Difficulty) -> String {
        switch d {
        case .kolay: return p("Kolay", "Easy")
        case .orta: return p("Orta", "Medium")
        case .zor: return p("Zor", "Hard")
        }
    }
    static var onlineGameCenter: String { "Online: Game Center" }
    static var onlineNearby: String { p("Online: yakındaki oyuncu", "Online: nearby player") }
    static var localTwo: String { p("Aynı cihazda 2 kişi", "Two players, one device") }
    static var localShort: String { p("2 kişi", "2 players") }
    static var language: String { p("Dil", "Language") }

    // MARK: Players and turns
    static var you: String { p("Sen", "You") }
    static var computer: String { p("Yapay zekâ", "Computer") }
    static var opponent: String { p("Rakip", "Opponent") }
    static var red: String { p("Kırmızı", "Red") }
    static var blue: String { p("Mavi", "Blue") }
    static var yourTurn: String { p("Sıra sende", "Your turn") }
    static func turnOf(_ name: String) -> String { p("Sıra: \(name)", "\(name) to shoot") }
    static var computerAiming: String { p("Yapay zekâ nişan alıyor", "Computer is aiming") }
    static var opponentAiming: String { p("Rakip nişan alıyor", "Opponent is aiming") }
    static var inFlight: String { p("Gülle havada", "Shot in the air") }
    static var gameOver: String { p("Oyun bitti", "Game over") }
    static var opponentLeft: String { p("Rakip ayrıldı", "Opponent left") }
    static func wind(_ n: Int) -> String { p("Rüzgâr \(n)", "Wind \(n)") }

    // MARK: Aiming
    static var pullHint: String { p("Geri çek ve bırak", "Pull back and release") }
    static var goldHint: String { p("Altın hedefi vur: kritik vuruş", "Hit the gold target for a critical") }
    static var megaArmedHint: String { p("Mega atış kurulu: geri çek ve bırak", "Mega shot armed: pull back and release") }
    static var inspectHint: String { p("Sürükle: çevir · Kıstır: yakınlaş", "Drag to rotate · Pinch to zoom") }
    static var pullMore: String { p("Atış için aşağı çek", "Pull down to shoot") }
    static func pullLabel(power: Int, yaw: Double) -> String {
        let y = "\(yaw >= 0 ? "+" : "−")\(String(format: "%.1f", abs(yaw)))°"
        return p("GÜÇ \(power)   YÖN \(y)", "POWER \(power)   AIM \(y)")
    }
    static var inspect: String { p("Hedefe bak", "Inspect the target") }
    static var backToAim: String { p("Nişana dön", "Back to aiming") }
    static var mute: String { p("Sesi kapat", "Mute") }
    static var unmute: String { p("Sesi aç", "Unmute") }
    static var mainMenu: String { p("Ana menü", "Main menu") }
    static func health(_ name: String, _ heart: Int, _ n: Int) -> String {
        p("\(name), kalp yüzde \(heart), kalan yapı yüzde \(n)", "\(name), heart \(heart) percent, \(n) percent standing")
    }
    static var megaReady: String { p("Mega atış hazır", "Mega shot ready") }
    static var megaCharging: String { p("Mega atış doluyor", "Mega shot charging") }

    // MARK: Shot results
    static var miss: String { p("Iska!", "Miss!") }
    static var water: String { p("Gülle suya düştü", "Into the river") }
    static func hit(_ n: Int) -> String { p("İsabet! −%\(n)", "Hit! −\(n)%") }
    static func crit(_ n: Int) -> String { p("Kritik vuruş! −%\(n)", "Critical hit! −\(n)%") }
    static func megaHit(_ n: Int) -> String { p("Mega atış! −%\(n)", "Mega shot! −\(n)%") }
    static func streak(_ n: Int) -> String { p("Seri ×\(n)", "Streak ×\(n)") }
    static var ownCastle: String { p("Kendi kaleni vurdun!", "You hit your own castle!") }
    static var heartHit: String { p("Kalp çatladı!", "Heart cracked!") }
    static var heartBroken: String { p("Kalp kırıldı!", "Heart shattered!") }
    static var ownHeart: String { p("Kendi kalbini vurdun!", "You hit your own heart!") }
    static var timeUp: String { p("Süre doldu", "Time's up") }

    // MARK: Result card
    static var won: String { p("Kazandın!", "You win!") }
    static var lost: String { p("Kaybettin", "You lose") }
    static func sideWon(_ name: String) -> String { p("\(name) kazandı!", "\(name) wins!") }
    static func standing(_ a: String, _ pa: Int, _ b: String, _ pb: Int) -> String {
        p("Ayakta kalan yapı: \(a) \(pct(pa)), \(b) \(pct(pb)).", "Still standing: \(a) \(pct(pa)), \(b) \(pct(pb)).")
    }
    static func heartFell(_ name: String) -> String { p("\(name) kalbini kaybetti.", "\(name) lost their heart.") }
    static var forfeitWin: String { p("Rakip ayrıldı, maç senin.", "Your opponent left. The match is yours.") }
    static var rematchWanted: String { p("Rakip tekrar oynamak istiyor.", "Your opponent wants a rematch.") }
    static var rematchGone: String { p("Rakip ayrıldı. Ana menüden yeni bir eşleşme başlat.", "Your opponent left. Start a new match from the main menu.") }
    static var playAgain: String { p("Tekrar oyna", "Play again") }
    static var waitingOpponent: String { p("Rakip bekleniyor", "Waiting for opponent") }
    static var accuracy: String { p("İsabet", "Accuracy") }
    static var bestHit: String { p("En iyi vuruş", "Best hit") }
    static var criticals: String { p("Kritik", "Criticals") }
    static func xpGain(_ n: Int) -> String { "+\(n) XP" }
    static func level(_ n: Int) -> String { p("Seviye \(n)", "Level \(n)") }
    static func levelUp(_ n: Int) -> String { p("Seviye atladın: \(n)", "Level up: \(n)") }
    static var firstWin: String { p("Günün ilk galibiyeti: +50 XP", "First win of the day: +50 XP") }
    static func unlocked(_ ball: String) -> String { p("Yeni gülle açıldı: \(ball)", "New cannonball unlocked: \(ball)") }
    static func promoted(_ league: String) -> String { p("Lig atladın: \(league)", "Promoted to \(league)") }
    static func trophies(_ n: Int) -> String { p("\(n) kupa", n == 1 ? "1 trophy" : "\(n) trophies") }

    // MARK: Profile
    static var profile: String { p("Profil", "Profile") }
    static func league(_ l: League) -> String {
        switch l {
        case .bronze: return p("Bronz Lig", "Bronze League")
        case .silver: return p("Gümüş Lig", "Silver League")
        case .gold: return p("Altın Lig", "Gold League")
        case .diamond: return p("Elmas Lig", "Diamond League")
        case .legend: return p("Efsane Lig", "Legend League")
        }
    }
    static var wins: String { p("Galibiyet", "Wins") }
    static var losses: String { p("Mağlubiyet", "Losses") }
    static var winStreak: String { p("Galibiyet serisi", "Win streak") }
    static var bestStreak: String { p("En uzun seri", "Best streak") }
    static var dayStreak: String { p("Günlük seri", "Daily streak") }
    static func days(_ n: Int) -> String { p("\(n) gün", n == 1 ? "1 day" : "\(n) days") }
    static var cannonballs: String { p("Gülleler", "Cannonballs") }
    static func ball(_ id: Int) -> String {
        switch id {
        case 1: return p("Kor", "Ember")
        case 2: return p("Buz", "Frost")
        case 3: return p("Altın", "Gold")
        default: return p("Klasik", "Classic")
        }
    }
    static var close: String { p("Kapat", "Close") }
    static func nextLeague(_ n: Int, _ league: String) -> String { p("\(league) için \(n) kupa daha", "\(n) more to \(league)") }

    // MARK: Daily siege and missions
    static var dailySiege: String { p("Günün Kuşatması", "Daily Siege") }
    static var siegePitch: String { p("8 atış · herkes için aynı kale", "8 shots · same castle for everyone") }
    static func siegeToday(_ n: Int) -> String { p("Bugün: \(n)", "Today: \(n)") }
    static var targetCastle: String { p("Hedef kale", "Target castle") }
    static var score: String { p("Skor", "Score") }
    static func points(_ n: Int) -> String { p("+\(n) puan", "+\(n) pts") }
    static var siegeOver: String { p("Kuşatma bitti", "Siege over") }
    static var siegeCleared: String { p("Kalp kırıldı!", "Heart shattered!") }
    static func siegeScore(_ n: Int) -> String { p("Skorun: \(n)", "Your score: \(n)") }
    static func clearBonus(_ n: Int) -> String { p("Kalp bonusu +\(n)", "Heart bonus +\(n)") }
    static var todayBest: String { p("Bugünkü en iyi", "Today's best") }
    static var record: String { p("Rekor", "Record") }
    static var newBest: String { p("Bugünün en iyi skoru!", "New best for today!") }
    static var siegeFirst: String { p("Günün kuşatması tamam: +60 XP", "Daily siege done: +60 XP") }
    static var tryAgain: String { p("Tekrar dene", "Try again") }
    static var missions: String { p("Günlük görevler", "Daily missions") }
    static func mission(_ m: Mission) -> String {
        switch m.id {
        case "win": return p("Bir maç kazan", "Win a match")
        case "hits": return p("\(m.target) isabet yap", "Land \(m.target) hits")
        case "crits": return p("\(m.target) kritik vuruş yap", "Land \(m.target) criticals")
        case "megas": return p("\(m.target) mega atış yap", "Fire \(m.target) mega shots")
        case "bighit": return p("Tek atışta \(pct(Mission.bigHit)) hasar ver", "Deal \(pct(Mission.bigHit)) with one shot")
        case "siege": return p("Günün Kuşatması'nı oyna", "Play the Daily Siege")
        case "streak": return p("×\(m.target) seri yakala", "Reach a ×\(m.target) streak")
        case "pickup": return p("Bir balon kap", "Grab a balloon")
        case "special": return p("\(m.target) özel gülle kullan", "Use \(m.target) special shots")
        case "stage": return p("Bir sefer bölümü kazan", "Win a campaign stage")
        default: return m.id
        }
    }
    static func missionDone(_ title: String) -> String { p("Görev tamam: \(title) +\(Mission.xp) XP", "Mission done: \(title) +\(Mission.xp) XP") }

    // MARK: Identity
    static var gunner: String { p("Topçu", "Gunner") }
    static var playerName: String { p("Oyuncu adı", "Player name") }
    static func versus(_ name: String, _ league: String, _ level: Int) -> String { "\(name) · \(league) · \(Tx.level(level))" }
    static var online: String { "Online" }
    static var gameCenterShort: String { "Game Center" }
    static var nearbyShort: String { p("Yakındaki", "Nearby") }

    // MARK: Ammo, balloons, modifiers
    static func ammo(_ a: Ammo) -> String {
        switch a {
        case .standard: return p("Gülle", "Ball")
        case .cluster: return p("Saçma", "Cluster")
        case .piercer: return p("Delici", "Piercer")
        case .homing: return p("Güdümlü", "Homing")
        }
    }
    static func ammoHint(_ a: Ammo) -> String {
        switch a {
        case .standard: return ""
        case .cluster: return p("Saçma: yan yana üç patlama", "Cluster: three blasts side by side")
        case .piercer: return p("Delici: duvarı geçip içeride patlar", "Piercer: goes through the wall, bursts inside")
        case .homing: return p("Güdümlü: altın hedefe yönelir", "Homing: steers to the gold target")
        }
    }
    static func pickup(_ k: PickupKind) -> String {
        switch k {
        case .repair: return p("Onarım", "Repair")
        case .shield: return p("Kalkan", "Shield")
        case .charge: return p("Mega şarj", "Mega charge")
        }
    }
    static func grabbed(_ k: PickupKind) -> String { p("\(pickup(k)) kapıldı!", "\(pickup(k)) grabbed!") }
    static func balloonHint(_ k: PickupKind) -> String { p("Balon: \(pickup(k)). İçinden geç, kap.", "Balloon: \(pickup(k)). Shoot through it.") }
    static var shieldBroken: String { p("Kalkan kırıldı", "Shield broken") }
    static func modifier(_ m: Modifier) -> String {
        switch m {
        case .none: return p("Standart", "Standard")
        case .storm: return p("Fırtına", "Storm")
        case .calm: return p("Durgun hava", "Still air")
        case .lowGravity: return p("Hafif yerçekimi", "Low gravity")
        case .megaRush: return p("Mega yağmuru", "Mega rush")
        case .bigBlast: return p("Büyük patlama", "Big blast")
        }
    }
    static func modifierHint(_ m: Modifier) -> String {
        switch m {
        case .none: return ""
        case .storm: return p("Rüzgâr iki kat güçlü", "Wind is twice as strong")
        case .calm: return p("Rüzgâr yok", "No wind")
        case .lowGravity: return p("Gülleler daha uzağa gider", "Shots carry farther")
        case .megaRush: return p("Mega iki kat hızlı dolar", "Mega fills twice as fast")
        case .bigBlast: return p("Patlamalar daha geniş", "Blasts are wider")
        }
    }

    // MARK: Campaign
    static var campaign: String { p("Sefer", "Campaign") }
    static func stage(_ n: Int) -> String { p("Bölüm \(n)", "Stage \(n)") }
    static func campaignProgress(_ stage: Int, _ stars: Int, _ of: Int) -> String { p("Bölüm \(stage) · \(stars)/\(of) yıldız", "Stage \(stage) · \(stars)/\(of) stars") }
    static var quickMatch: String { p("Hızlı maç", "Quick match") }
    static var nextStage: String { p("Sonraki bölüm", "Next stage") }
    static var locked: String { p("Kilitli", "Locked") }
    static func stageWon(_ n: Int) -> String { p("Bölüm \(n) geçildi", "Stage \(n) cleared") }
    static func pieceUnlocked(_ name: String) -> String { p("Yeni yapı parçası: \(name)", "New building piece: \(name)") }
    static var campaignDone: String { p("Sefer tamamlandı!", "Campaign complete!") }

    // MARK: Castle builder
    static var buildCastle: String { p("Kaleni kur", "Build your castle") }
    static func piece(_ k: PieceKind) -> String {
        switch k {
        case .wallLow: return p("Alçak duvar", "Low wall")
        case .wallHigh: return p("Yüksek duvar", "High wall")
        case .tower: return p("Kule", "Tower")
        case .tallTower: return p("Yüksek kule", "Tall tower")
        case .bastion: return p("Tabya", "Bastion")
        case .keep: return p("İç kale", "Keep")
        case .heart: return p("Kalp", "Heart")
        }
    }
    static var eraser: String { p("Sil", "Erase") }
    static func stone(_ used: Int, _ of: Int) -> String { p("Taş \(used)/\(of)", "Stone \(used)/\(of)") }
    static var save: String { p("Kaydet", "Save") }
    static var classicLayout: String { p("Klasik", "Classic") }
    static var clearAll: String { p("Temizle", "Clear") }
    static var builderFront: String { p("ÖN (düşmana bakan)", "FRONT (faces the enemy)") }
    static var builderBack: String { p("ARKA", "BACK") }
    static var builderHint: String { p("Parça seç, ızgaraya dokun. Kalbi duvarların arkasına sakla.", "Pick a piece, tap the grid. Hide the heart behind your walls.") }
    static var saved: String { p("Kalen kaydedildi", "Castle saved") }
    static func needStars(_ n: Int) -> String { p("\(n) sefer yıldızı gerekir", "Needs \(n) campaign stars") }
    static func problem(_ pr: CastleDesign.Problem) -> String {
        switch pr {
        case .noHeart: return p("Kalbi yerleştir: korunacak tek şey o.", "Place the heart: it is what you defend.")
        case .manyHearts: return p("Yalnızca bir kalp olabilir.", "Only one heart is allowed.")
        case .manyKeeps: return p("Yalnızca bir iç kale olabilir.", "Only one keep is allowed.")
        case .tooSmall: return p("Kale çok küçük: en az \(CastleDesign.minimum) taş kullan.", "Too small: use at least \(CastleDesign.minimum) stone.")
        case .overBudget: return p("Taş sınırı aşıldı.", "Over the stone limit.")
        case .overlap: return p("Parçalar üst üste biniyor.", "Pieces overlap.")
        }
    }
    static var noStone: String { p("Yeterli taş yok", "Not enough stone") }
    static var noRoom: String { p("Buraya sığmıyor", "It does not fit here") }

    // MARK: Settings, help, leaving
    static var settings: String { p("Ayarlar", "Settings") }
    static var sound: String { p("Ses", "Sound") }
    static var haptics: String { p("Titreşim", "Vibration") }
    static var on: String { p("Açık", "On") }
    static var off: String { p("Kapalı", "Off") }
    static var howToPlay: String { p("Nasıl oynanır", "How to play") }
    static var gotIt: String { p("Anladım", "Got it") }
    static var tips: [(String, String)] {
        [
            ("hand.draw.fill", p("Ekrana dokun, geri çek ve bırak. Çekiş uzunluğu gücü, sağa sola çekmek yönü belirler.", "Touch the screen, pull back and release. Pull length sets power; pulling sideways turns the cannon.")),
            ("wind", p("Rüzgâr her tur değişir. Üstteki ok gülleyi ittiği yönü gösterir.", "Wind changes every turn. The arrow at the top shows which way it pushes the shot.")),
            ("scope", p("Altın hedefin yakınına isabet kritik vuruştur: patlama büyür.", "A hit near the gold target is a critical: the blast grows.")),
            ("bolt.fill", p("Hasar verdikçe MEGA dolar. Dolunca düğmeye bas, dev bir atış yap.", "Dealing damage fills MEGA. When it is full, tap the button for a giant shot.")),
            ("circle.grid.cross.fill", p("Her maçta üç özel güllen var: Saçma, Delici, Güdümlü.", "You carry three special shots per match: Cluster, Piercer, Homing.")),
            ("balloon.fill", p("Balonun içinden atış geçirirsen ödülü kaparsın: onarım, kalkan ya da mega şarj.", "Shoot through a balloon to grab its prize: repair, shield or mega charge.")),
            ("heart.fill", p("Her kalenin bir kalbi var. Rakibin kalbini kıran kazanır.", "Every castle guards a heart. Shatter the enemy heart to win.")),
            ("building.columns.fill", p("Kaleni kendin kur: kalbi duvarların, kulelerin arkasına sakla.", "Build your own castle: hide the heart behind walls and towers.")),
        ]
    }
    static var quitTitle: String { p("Maçtan çıkılsın mı?", "Leave the match?") }
    static var quitOnline: String { p("Online maçtan çıkmak yenilgi sayılır.", "Leaving an online match counts as a loss.") }
    static var quitPlain: String { p("Bu maçtaki ilerleme kaybolur.", "Progress in this match will be lost.") }
    static var leave: String { p("Çık", "Leave") }
    static var stay: String { p("Devam et", "Keep playing") }

    // MARK: Online lobby
    static var gameCenterTitle: String { p("Game Center eşleşmesi", "Game Center match") }
    static var nearbyTitle: String { p("Yakındaki oyuncu", "Nearby player") }
    static var preparing: String { p("Hazırlanıyor…", "Getting ready…") }
    static var retry: String { p("Yeniden dene", "Try again") }
    static var cancel: String { p("Vazgeç", "Cancel") }
    static var signingIn: String { p("Game Center'a giriş yapılıyor…", "Signing in to Game Center…") }
    static func gameCenterUnavailable(_ reason: String?) -> String {
        p("Game Center kullanılamıyor. ", "Game Center is unavailable. ") + (reason ?? p("Ayarlar'dan Game Center'a giriş yap.", "Sign in to Game Center in Settings."))
    }
    static var matchScreenFailed: String { p("Eşleşme ekranı açılamadı.", "Could not open matchmaking.") }
    static var searching: String { p("Rakip aranıyor…", "Looking for an opponent…") }
    static var matchCancelled: String { p("Eşleşme iptal edildi.", "Matchmaking was cancelled.") }
    static func matchFailed(_ reason: String) -> String { p("Eşleşme başarısız: ", "Matchmaking failed: ") + reason }
    static var nearbySearching: String { p("Yakındaki oyuncu aranıyor. Diğer cihazda da bu ekranı aç.", "Looking for a nearby player. Open this screen on the other device too.") }
    static func localNetworkFailed(_ reason: String) -> String { p("Yerel ağa erişilemedi: ", "Could not reach the local network: ") + reason }
    static var opponentFound: String { p("Rakip bulundu, oyun başlıyor…", "Opponent found. Starting…") }
    static var versionMismatch: String { p("Rakip oyunun farklı bir sürümünde. İkiniz de güncelleyin.", "Your opponent has a different version of the game. Both of you should update.") }
    static var connectionLost: String { p("Bağlantı koptu.", "Connection lost.") }
}
