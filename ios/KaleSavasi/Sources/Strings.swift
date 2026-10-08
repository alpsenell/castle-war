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
    static var gameName: String { "Keepfall" }
    static var logoTop: String { "KEEP" }
    static var logoBottom: String { "FALL" }
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
    static var decoyFound: String { p("Sahte kalpmiş!", "It was a decoy!") }
    static var stoneCracked: String { p("Demir duvar çatladı", "Iron wall cracked") }
    static var moat: String { p("Gülle hendeğe düştü", "Into the moat") }
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
        case .wallStrong: return p("Demir duvar", "Iron wall")
        case .shelter: return p("Sundurma", "Shelter")
        case .moat: return p("Hendek", "Moat")
        case .decoy: return p("Sahte kalp", "Decoy heart")
        }
    }
    static func pieceInfo(_ k: PieceKind) -> String? {
        switch k {
        case .wallStrong: return p("Her taşı iki patlamada kırılır", "Each stone takes two blasts")
        case .shelter: return p("Ortasına kalbi koy: yukarıdan gelen atışları durdurur", "Put the heart in the middle: stops shots from above")
        case .moat: return p("İçine düşen gülle patlamaz", "A shot that lands in it does not go off")
        case .decoy: return p("Rakip gerçeğinden ayıramaz. En çok \(CastleDesign.maxDecoys)", "Looks real to the enemy. Up to \(CastleDesign.maxDecoys)")
        case .heart: return p("Bedava. Korunacak olan bu", "Free. This is what you defend")
        default: return nil
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
        case .manyDecoys: return p("En çok \(CastleDesign.maxDecoys) sahte kalp olabilir.", "At most \(CastleDesign.maxDecoys) decoy hearts.")
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
            ("flame.fill", p("Fetih Yolu'nda kalen düşene kadar sırayla kaleler gelir. Başarımlar ve kalp türleri seni bekliyor.", "In the Gauntlet, castles keep coming until yours falls. Achievements and heart types wait for you.")),
            ("person.3.fill", p("Dört kale modunda herkes kendi için oynar: hedef düğmeleriyle saldıracağın kaleyi seç.", "In Four castles it is every castle for itself: pick which castle to attack with the target buttons.")),
            ("shield.lefthalf.filled", p("Sundurma kalbi yukarıdan korur, demir duvar iki darbe alır, hendek gülleyi yutar. Sahte kalplerle rakibi şaşırt.", "A shelter roofs the heart, iron walls take two blasts, moats swallow shots. Decoy hearts fool the enemy.")),
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

    // MARK: Heart types
    static var heartType: String { p("Kalp türü", "Heart type") }
    static func heart(_ h: HeartKind) -> String {
        switch h {
        case .crystal: return p("Kristal", "Crystal")
        case .living: return p("Canlı", "Living")
        case .aegis: return p("Kalkanlı", "Aegis")
        case .titan: return p("Dev", "Titan")
        }
    }
    static func heartInfo(_ h: HeartKind) -> String {
        switch h {
        case .crystal: return p("Sade kalp. Bedava.", "The plain heart. Free.")
        case .living: return p("Her turunun başında kayıp bir kristali geri büyütür.", "Grows back one lost crystal at the start of each of your turns.")
        case .aegis: return p("İlk çatladığında kaleni bir kez kalkanla korur.", "Throws a shield over your castle the first time it cracks.")
        case .titan: return p("Dört sıra kristal: kırmak daha zor, ama daha yüksek.", "Four courses of crystal: harder to break, but taller.")
        }
    }
    static func heartLocked(_ level: Int) -> String { p("Seviye \(level) gerekir", "Needs level \(level)") }
    static func heartUnlocked(_ name: String) -> String { p("Yeni kalp: \(name)", "New heart: \(name)") }
    static var heartRegrew: String { p("Kalp yeniden büyüdü", "The heart grew back") }
    static var aegisUp: String { p("Kalkanlı kalp: kalkan açıldı!", "Aegis heart: shield up!") }

    // MARK: Gauntlet
    static var gauntlet: String { p("Fetih Yolu", "Gauntlet") }
    static var gauntletPitch: String { p("Kalen düşene kadar sıradaki kale", "Castle after castle until yours falls") }
    static func gauntletBest(_ n: Int) -> String { p("En iyi: \(n)", "Best: \(n)") }
    static func gauntletRound(_ n: Int) -> String { p("\(n). kale", "Castle \(n)") }
    static func gauntletWon(_ n: Int) -> String { p("\(n). kale düştü!", "Castle \(n) toppled!") }
    static func gauntletCarry(_ n: Int) -> String {
        p("Hasarın sonraki kaleye taşınır. \(n) taş onarıldı.", "Your damage carries into the next fight. \(n) stones repaired.")
    }
    static var gauntletOver: String { p("Seferin sonu", "Run over") }
    static func gauntletToppled(_ n: Int) -> String { p("Bu seferde \(n) kale yıktın.", "You toppled \(n) castles this run.") }
    static var nextCastle: String { p("Sıradaki kale", "Next castle") }
    static var newRun: String { p("Yeni sefer", "New run") }
    static var gauntletNewBest: String { p("En uzun seferin!", "Your best run yet!") }

    // MARK: Castle codes
    static var shareCastle: String { p("Paylaş", "Share") }
    static var pasteCode: String { p("Kod yapıştır", "Paste code") }
    static var codeLoaded: String { p("Kale koddan yüklendi", "Castle loaded from code") }
    static var codeInvalid: String { p("Geçerli bir kale kodu bulunamadı", "No valid castle code found") }
    static var friendCastle: String { p("Arkadaşının kalesi", "Friend's castle") }
    static var friendHint: String { p("Kodunu yapıştır", "Paste their code") }
    static var friendName: String { p("Arkadaş", "Friend") }
    static func shareMessage(_ code: String) -> String {
        p("Kalbimi kırabilir misin? Keepfall'da bu kodu yapıştır: \(code)", "Can you break my heart? Paste this code in Keepfall: \(code)")
    }

    // MARK: Achievements
    static var achievementsTitle: String { p("Başarımlar", "Achievements") }
    static func achievementCount(_ n: Int, _ of: Int) -> String { p("Başarımlar \(n)/\(of)", "Achievements \(n)/\(of)") }
    static func achievementDone(_ a: Achievement) -> String { p("Başarım: \(achievement(a))", "Achievement: \(achievement(a))") }
    static func achievement(_ a: Achievement) -> String {
        switch a {
        case .firstWin: return p("İlk zafer", "First victory")
        case .tenWins: return p("Kalp kırıcı", "Heartbreaker")
        case .sniper: return p("Keskin nişancı", "Sharpshooter")
        case .mega: return p("Gürleyen top", "Thunder cannon")
        case .flawless: return p("Kusursuz", "Flawless")
        case .comeback: return p("Küllerinden", "From the ashes")
        case .trickster: return p("Hilekâr", "Trickster")
        case .gauntlet5: return p("Kale avcısı", "Castle hunter")
        case .gauntlet10: return p("Durdurulamaz", "Unstoppable")
        case .campaign: return p("Seferin sonu", "Campaign conqueror")
        case .allStars: return p("Yıldızlar", "Star collector")
        case .siege: return p("Kuşatma ustası", "Siege master")
        case .streak: return p("Seri katil", "On a roll")
        case .level10: return p("Usta topçu", "Master gunner")
        case .architect: return p("Mimar", "Architect")
        case .friend: return p("Dost kazığı", "Friendly fire")
        case .legend: return p("Efsane", "Legend")
        }
    }
    static func achievementGoal(_ a: Achievement) -> String {
        switch a {
        case .firstWin: return p("Bir maç kazan", "Win a match")
        case .tenWins: return p("10 maç kazan", "Win 10 matches")
        case .sniper: return p("25 kritik vuruş yap", "Land 25 critical hits")
        case .mega: return p("10 mega atış yap", "Fire 10 mega shots")
        case .flawless: return p("Kalbin hiç çatlamadan kazan", "Win without a crack in your heart")
        case .comeback: return p("Kalenin %30'u kalmışken kazan", "Win with under 30% of your castle standing")
        case .trickster: return p("Rakip 3 sahte kalbini kırsın", "Let the enemy break 3 of your decoys")
        case .gauntlet5: return p("Bir seferde 5 kale yık", "Topple 5 castles in one gauntlet run")
        case .gauntlet10: return p("Bir seferde 10 kale yık", "Topple 10 castles in one gauntlet run")
        case .campaign: return p("Seferin son bölümünü geç", "Clear the last campaign stage")
        case .allStars: return p("Seferin tüm yıldızlarını topla", "Collect every campaign star")
        case .siege: return p("Günün kuşatmasında 1500 puan yap", "Score 1500 in a daily siege")
        case .streak: return p("Üst üste 5 maç kazan", "Win 5 matches in a row")
        case .level10: return p("10. seviyeye ulaş", "Reach level 10")
        case .architect: return p("Kendi kaleni kaydet", "Save a castle of your own")
        case .friend: return p("Bir arkadaşının kalesini yık", "Break a friend's castle")
        case .legend: return p("Efsane ligine çık", "Reach the Legend league")
        }
    }

    // MARK: Final shot
    static var finalShot: String { p("SON ATIŞ", "FINAL SHOT") }

    // MARK: Four castles
    static var party: String { p("4 oyuncu", "4 players") }
    static var partyTitle: String { p("Dört kale", "Four castles") }
    static var partyPitch: String {
        p("Herkes kendi için: dört kale bir gölün çevresinde. Son ayakta kalan kalp kazanır; boş koltuklara bilgisayar oturur.",
          "Free-for-all: four castles around a lake. The last heart standing wins, and computers fill empty seats.")
    }
    static var partyComputers: String { p("3 bilgisayara karşı", "Against 3 computers") }
    static var partyGameCenter: String { p("Game Center (2–4 kişi)", "Game Center (2–4 players)") }
    static var partyHost: String { p("Yakında kur", "Host nearby") }
    static var partyJoin: String { p("Yakındakine katıl", "Join nearby") }
    static var hostWaiting: String { p("Oyuncular bekleniyor. Diğer cihazlarda Katıl'a dokunsunlar.", "Waiting for players. Ask them to tap Join on their devices.") }
    static var joinSearching: String { p("Yakındaki kurucu aranıyor…", "Looking for a nearby host…") }
    static func partyPlayers(_ n: Int) -> String { p("Oyuncular: \(n)/4 · gerisi bilgisayar", "Players: \(n)/4 · computers fill the rest") }
    static var startNow: String { p("Başlat", "Start") }
    static var waitingHost: String { p("Kurucu bekleniyor", "Waiting for the host") }
    static var hostLeft: String { p("Kurucu ayrıldı, maç bitti.", "The host left. The match is over.") }
    static func seatName(_ i: Int) -> String {
        [p("Kırmızı", "Red"), p("Mavi", "Blue"), p("Yeşil", "Green"), p("Sarı", "Yellow")][i % 4]
    }
    static func seatOut(_ name: String, _ place: Int) -> String { p("\(name) elendi (\(place). sıra)", "\(name) is out (#\(place))") }
    static func youOut(_ place: Int) -> String { p("Elendin! \(place). oldun", "You're out! You placed #\(place)") }
    static func placements(_ order: [String]) -> String {
        p("Sıralama: ", "Final order: ") + order.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " · ")
    }
    static var target: String { p("Hedef", "Target") }
    static var botTag: String { p("bilgisayar", "computer") }
    static func playerLeft(_ name: String) -> String { p("\(name) ayrıldı, yerine bilgisayar oynuyor", "\(name) left; a computer takes over") }

    // MARK: 2.0 builder
    static func brickProblem(_ pr: BrickProblem) -> String {
        switch pr {
        case .overlap: return p("Tuğlalar iç içe geçiyor.", "Some bricks overlap.")
        case .outOfBounds: return p("Bir tuğla arsanın dışında.", "A brick is outside the plot.")
        case .floating: return p("Kırmızı tuğlaların altında hiçbir şey yok.", "The red bricks have nothing under them.")
        case .noHeart: return p("Kalbi yerleştir: korunacak tek şey o.", "Place the heart: it is what you defend.")
        case .manyHearts: return p("Yalnızca bir kalp olabilir.", "Only one heart is allowed.")
        case .manyDecoys: return p("En çok \(BK.maxDecoys) sahte kalp olabilir.", "At most \(BK.maxDecoys) decoy hearts.")
        case .overBudget: return p("Altın sınırı aşıldı.", "Over the coin limit.")
        case .tooSmall: return p("Kale çok küçük: en az \(BK.minimum) altınlık tuğla kullan.", "Too small: spend at least \(BK.minimum) coins on bricks.")
        case .tooMany: return p("En çok \(BK.maxBricks) tuğla olabilir.", "At most \(BK.maxBricks) bricks.")
        }
    }
    static var builderReady: String { p("Kale hazır. Kaydet ya da yerçekimini dene.", "Ready to save. Try Test gravity first.") }
    static var builderHint3D: String { p("Bir parça seç, zemine ya da bir tuğlanın üstüne dokun.", "Pick a piece, then tap the ground or the top of a brick.") }
    static var eraseHint: String { p("Silmek için bir tuğlaya dokun.", "Tap a brick to remove it.") }
    static var lookHint: String { p("Sürükle: çevir · iki parmak: kaydır, yakınlaş", "Drag to orbit · two fingers to pan and zoom") }
    static var noCoins: String { p("Yeterli altın yok", "Not enough coins") }
    static var tooHigh: String { p("Kale bu kadar yükselemez", "That is above the height limit") }
    static var offPlot: String { p("Arsanın dışında", "Outside the plot") }
    static var aboveLayer: String { p("Kat sınırının üstünde", "Above the layer limit") }
    static var onMoat: String { p("Hendeğin üstüne bir şey konmaz", "Nothing can stand in a moat") }
    static var onRoof: String { p("Çatının üstüne bir şey konmaz", "Nothing can stand on a roof") }
    static var roofMaterials: String { p("Çatılar demirden olmaz; taş kullanılır.", "Roofs cannot be iron; stone is used.") }
    static var testGravity: String { p("Yerçekimi", "Test gravity") }
    static var gravityRunning: String { p("Yerçekimi deneniyor…", "Testing gravity…") }
    static var gravityStands: String { p("Kale ayakta kaldı!", "Your castle stands firm!") }
    static func gravityFell(_ n: Int) -> String { p("\(n) tuğla yerinden oynadı. Altlarını destekle.", n == 1 ? "1 brick moved. Give it better support." : "\(n) bricks moved. Give them better support.") }
    static var undo: String { p("Geri al", "Undo") }
    static var redo: String { p("Yinele", "Redo") }
    static var rotate: String { p("Döndür", "Rotate") }
    static var build: String { p("Kur", "Build") }
    static var look: String { p("Bak", "Look") }
    static var layer: String { p("Kat", "Layer") }
    static var paste: String { p("Yapıştır", "Paste") }
    static var coins: String { p("Altın", "Coins") }
    static var bricks: String { p("Tuğla", "Bricks") }
    static var stamps: String { p("Kalıplar", "Stamps") }
    static var castles: String { p("Kaleler", "Castles") }
    static func castleNumber(_ n: Int) -> String { p("Kale \(n)", "Castle \(n)") }
    static var decoy: String { p("Sahte kalp", "Decoy") }
    static var heartTool: String { p("Kalp", "Heart") }
    static var front3D: String { p("ÖN", "FRONT") }
    static func material(_ m: BrickMaterial) -> String {
        switch m {
        case .wood: return p("Ahşap", "Wood")
        case .stone: return p("Taş", "Stone")
        case .ice: return p("Buz", "Ice")
        case .iron: return p("Demir", "Iron")
        case .heart: return p("Kalp", "Heart")
        case .decoy: return p("Sahte kalp", "Decoy")
        }
    }
    static func materialInfo(_ m: BrickMaterial) -> String {
        switch m {
        case .wood: return p("Hafif ve ucuz", "Light and cheap")
        case .stone: return p("Ağır ve sağlam", "Heavy and sturdy")
        case .ice: return p("Hafif ama kırılgan", "Light but brittle")
        case .iron: return p("İki darbe dayanır", "Takes two hits")
        default: return ""
        }
    }
    static func shape(_ s: BrickShape) -> String {
        switch s {
        case .cube: return p("Küp", "Cube")
        case .half: return p("Yarım", "Half")
        case .beam2: return p("Kiriş 2", "Beam 2")
        case .beam3: return p("Kiriş 3", "Beam 3")
        case .beam4: return p("Kiriş 4", "Beam 4")
        case .plank: return p("Kalas", "Plank")
        case .pillar2: return p("Sütun 2", "Pillar 2")
        case .pillar3: return p("Sütun 3", "Pillar 3")
        case .wedge: return p("Rampa", "Wedge")
        case .arch: return p("Kemer", "Arch")
        case .coneRoof: return p("Külah çatı", "Cone roof")
        case .pyramidRoof: return p("Piramit çatı", "Pyramid roof")
        case .battlement: return p("Mazgal", "Battlement")
        case .window: return p("Pencere", "Window")
        case .moat: return p("Hendek", "Moat")
        }
    }
    static func stamp(_ s: Stamp) -> String {
        switch s {
        case .wall: return p("Duvar", "Wall")
        case .tallWall: return p("Yüksek duvar", "Tall wall")
        case .tower: return p("Kule", "Tower")
        case .tallTower: return p("Yüksek kule", "Tall tower")
        case .keep: return p("İç kale", "Keep")
        case .gatehouse: return p("Kapı kulesi", "Gatehouse")
        case .shrine: return p("Mabet", "Shrine")
        case .bridge: return p("Köprü", "Bridge")
        }
    }

    // MARK: 2.0 UI
    static var play: String { p("OYNA", "PLAY") }
    static var victory: String { p("ZAFER!", "VICTORY!") }
    static var defeat: String { p("YENİLGİ", "DEFEAT") }
    static var gameCenterPitch: String { p("Dünyadan rakipler", "Rivals worldwide") }
    static var nearbyPitch: String { p("Yanındaki biriyle", "Someone close by") }
    static var partyShort: String { p("Herkes kendi için", "Free-for-all") }
    static var localPitch: String { p("Tek cihaz, iki kişi", "One device, two players") }
    static var players: String { p("Oyuncular", "Players") }
}
