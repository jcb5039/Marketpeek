// 위젯이 타임라인을 만들 때 시세를 직접 받아, 앱이 써둔 스냅샷 위에 덮어쓴다.
// 앱을 열지 않아도 iOS가 위젯을 다시 불러올 때마다 새 값이 들어간다 (언제 다시 부를지는 iOS가 정한다).
// 받은 값은 App Group에 다시 쓰지 않는다. 앱이 쓰는 스냅샷과 서로 덮어쓰는 일을 피하기 위해서다.
import Foundation
import Security

/// 위젯 하나가 보여주는 시세 묶음. 갱신 시각은 고른 묶음을 모두 새로 받았을 때만 "지금"으로 바뀐다.
enum QuotePart: Hashable {
    case coins, stocks, fx, issue

    /// 자유 구성 위젯 칸 id("coin:BTC", "kr:005930", "stock:NVDA", "fx:USD")가 어느 묶음인지.
    static func of(itemId: String) -> QuotePart? {
        switch itemId.split(separator: ":").first.map(String.init) ?? "" {
        case "coin": return .coins
        case "kr", "stock": return .stocks
        case "fx": return .fx
        default: return nil
        }
    }
}

enum LiveQuotes {
    struct Price: Sendable {
        var value: Double
        var change: Double
    }

    struct ServerQuotes: Sendable {
        var fx: [String: Price]
        var issue: Snapshot.Issue?
    }

    struct StockQuotes: Sendable {
        var us: [String: Price]
        var kr: [String: Price]
    }

    /// 받을 게 없음(.nothing)은 새로 받은 것으로 친다. 실패(.failed)면 갱신 시각을 바꾸지 않는다.
    enum Fetch<T: Sendable>: Sendable {
        case nothing
        case ok(T)
        case failed

        var value: T? { if case .ok(let v) = self { v } else { nil } }
        var isFresh: Bool { if case .failed = self { false } else { true } }
    }

    static let timeout: TimeInterval = 8
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * 2
        return URLSession(configuration: c)
    }()

    static func refresh(_ snap: Snapshot, parts: Set<QuotePart>) async -> Snapshot {
        var s = snap
        let coinSymbols = s.coins.map(\.symbol)
        let fxCodes = Array(Set((s.fxList ?? []).map(\.code) + [s.fx?.code, "USD"].compactMap { $0 })).sorted()
        let us = s.stocks.map { ($0.ticker, $0.excd) }
        let kr = (s.krStocks ?? []).map(\.code)
        let base = s.settings.apiBaseUrl
        // 미국주식 원화 환산에 USD/KRW가 필요하므로 주식 위젯도 서버를 부른다.
        let wantServer = !parts.isDisjoint(with: [.fx, .issue]) || (parts.contains(.stocks) && !us.isEmpty)

        async let coinsR = parts.contains(.coins) ? fetchCoins(coinSymbols) : .nothing
        async let serverR = wantServer ? fetchServer(base: base, fx: fxCodes) : .nothing
        async let stocksR = parts.contains(.stocks) ? fetchStocks(us: us, kr: kr) : .nothing
        let (coins, server, stocks) = await (coinsR, serverR, stocksR)

        if let map = coins.value {
            for i in s.coins.indices {
                guard let p = map[s.coins[i].symbol] else { continue }
                s.coins[i].price = Fmt.krw(p.value)
                s.coins[i].priceShort = Fmt.krwShort(p.value)
                s.coins[i].change = p.change
            }
        }
        if let sv = server.value {
            func apply(_ fx: inout Snapshot.Fx) {
                guard let p = sv.fx[fx.code] else { return }
                fx.rate = Fmt.fxRate(p.value)
                fx.change = p.change
            }
            if var fx = s.fx { apply(&fx); s.fx = fx }
            if var list = s.fxList {
                for i in list.indices { apply(&list[i]) }
                s.fxList = list
            }
            if let usd = sv.fx["USD"]?.value { s.usdKrw = usd }
            s.issue = sv.issue
        }
        if let st = stocks.value {
            for i in s.stocks.indices {
                guard let p = st.us[s.stocks[i].ticker] else { continue }
                s.stocks[i].priceUsd = Fmt.usd(p.value)
                s.stocks[i].change = p.change
                if let rate = s.usdKrw {
                    let krw = Fmt.stockKrw(p.value, rate)
                    s.stocks[i].priceKrw = Fmt.krw(krw)
                    s.stocks[i].priceKrwShort = Fmt.krwShort(krw)
                }
            }
            if var list = s.krStocks {
                for i in list.indices {
                    guard let p = st.kr[list[i].code] else { continue }
                    list[i].price = Fmt.krw(p.value)
                    list[i].priceShort = Fmt.krwShort(p.value)
                    list[i].change = p.change
                }
                s.krStocks = list
            }
        }

        let fresh: [QuotePart: Bool] = [
            .coins: coins.isFresh, .stocks: stocks.isFresh,
            .fx: server.isFresh, .issue: server.isFresh,
        ]
        if !parts.isEmpty, parts.allSatisfy({ fresh[$0] ?? true }) {
            s.updatedAt = Date()
        }
        return s
    }

    // MARK: - 업비트 (키 없음)

    static func fetchCoins(_ symbols: [String]) async -> Fetch<[String: Price]> {
        if symbols.isEmpty { return .nothing }
        return await Reuse.shared.value("coins:" + symbols.joined(separator: ",")) {
            if let all = await upbit(symbols) { return all }
            // 상장폐지 등으로 없는 마켓이 하나라도 섞이면 요청 전체가 404가 되므로 하나씩 다시 받는다.
            guard symbols.count > 1 else { return nil }
            let merged = await withTaskGroup(of: [String: Price]?.self) { group in
                for sym in symbols { group.addTask { await upbit([sym]) } }
                var acc: [String: Price] = [:]
                for await part in group { acc.merge(part ?? [:]) { a, _ in a } }
                return acc
            }
            return merged.isEmpty ? nil : merged
        }
    }

    private static func upbit(_ symbols: [String]) async -> [String: Price]? {
        var c = URLComponents(string: "https://api.upbit.com/v1/ticker")!
        c.queryItems = [URLQueryItem(name: "markets", value: symbols.map { "KRW-\($0)" }.joined(separator: ","))]
        guard let list = await getJSON(URLRequest(url: c.url!)) as? [[String: Any]] else { return nil }
        var out: [String: Price] = [:]
        for item in list {
            guard let market = item["market"] as? String,
                  let price = num(item["trade_price"]),
                  let rate = num(item["signed_change_rate"]) else { continue }
            out[String(market.dropFirst(4))] = Price(value: price, change: rate * 100)
        }
        return out
    }

    // MARK: - 우리 서버 (환율·AI 이슈)

    static func fetchServer(base: String?, fx: [String]) async -> Fetch<ServerQuotes> {
        guard let base, var c = URLComponents(string: base) else { return .failed }
        c.path = "/quotes"
        c.queryItems = [URLQueryItem(name: "stocks", value: ""),
                        URLQueryItem(name: "fx", value: fx.joined(separator: ","))]
        guard let url = c.url else { return .failed }
        return await Reuse.shared.value("server:" + url.absoluteString) {
            guard let body = await getJSON(URLRequest(url: url)) as? [String: Any] else { return nil }
            var rates: [String: Price] = [:]
            for (code, v) in body["fx"] as? [String: Any] ?? [:] {
                guard let o = v as? [String: Any], let r = num(o["rateKrw"]), let ch = num(o["changePct"]) else { continue }
                rates[code] = Price(value: r, change: ch)
            }
            var issue: Snapshot.Issue?
            if let o = body["issue"] as? [String: Any], let text = o["text"] as? String,
               let at = (o["generatedAt"] as? String).flatMap(Snapshot.parseDate) {
                issue = Snapshot.Issue(text: text, short: o["shortText"] as? String, generatedAt: at)
            }
            return ServerQuotes(fx: rates, issue: issue)
        }
    }

    // MARK: - 한국투자증권 (사용자 키, 앱과 공유하는 Keychain)

    static let kisBase = "https://openapi.koreainvestment.com:9443"
    /// 초당 호출 한도(EGW00201)를 피하는 간격. Dart KisQuoteRepository.requestGap과 같다.
    static let kisGap: UInt64 = 350_000_000
    static let kisRetryDelay: UInt64 = 1_100_000_000

    /// 위젯은 토큰을 새로 발급하지 않는다. 위젯 여러 개가 동시에 발급하면 발급 한도(1분 1회)에 걸리기 때문이다.
    /// 앱이 받아 둔 토큰이 만료됐으면 실패로 보고 앱이 써둔 값을 그대로 둔다.
    static func fetchStocks(us: [(String, String?)], kr: [String]) async -> Fetch<StockQuotes> {
        let usJobs = us.compactMap { t, ex in ex.map { (t, $0) } }
        if usJobs.isEmpty && kr.isEmpty { return .nothing }
        guard let appKey = Keychain.read("kis.appKey"), let appSecret = Keychain.read("kis.appSecret") else {
            return .nothing  // 증권사 미연결: 위젯은 연결 안내를 보여준다.
        }
        guard let token = Keychain.read("kis.token"),
              let exp = Keychain.read("kis.tokenExpiresAt").flatMap(Snapshot.parseDate),
              exp > Date().addingTimeInterval(60) else { return .failed }

        let key = "kis:" + usJobs.map(\.0).joined(separator: ",") + "|" + kr.joined(separator: ",")
        let r: Fetch<StockQuotes> = await Reuse.shared.value(key) {
            let kis = KisCall(appKey: appKey, appSecret: appSecret, token: token)
            var out = StockQuotes(us: [:], kr: [:])
            let started = Date()
            var first = true
            jobs: for job in kr.map({ Either.kr($0) }) + usJobs.map({ Either.us($0.0, $0.1) }) {
                // iOS가 타임라인 계산에 주는 시간이 길지 않으므로 오래 걸리면 받은 것까지만 쓴다.
                if Date().timeIntervalSince(started) > 12 { break }
                if !first { try? await Task.sleep(nanoseconds: kisGap) }
                first = false
                switch await kis.price(job) {
                case .ok(let p):
                    switch job {
                    case .kr(let code): out.kr[code] = p
                    case .us(let t, _): out.us[t] = p
                    }
                case .tokenExpired: break jobs
                case .failed: continue
                }
            }
            return out.us.isEmpty && out.kr.isEmpty ? nil : out
        }
        return r
    }

    enum Either: Sendable {
        case kr(String)
        case us(String, String)
    }

    struct KisCall: Sendable {
        let appKey: String
        let appSecret: String
        let token: String

        enum Result { case ok(Price), tokenExpired, failed }

        func price(_ job: Either) async -> Result {
            var r = await once(job)
            if case .rateLimited = r {
                try? await Task.sleep(nanoseconds: LiveQuotes.kisRetryDelay)
                r = await once(job)
            }
            switch r {
            case .ok(let p): return .ok(p)
            case .tokenExpired: return .tokenExpired
            default: return .failed
            }
        }

        private enum Raw { case ok(Price), tokenExpired, rateLimited, failed }

        private func once(_ job: Either) async -> Raw {
            let (path, trId, query): (String, String, [String: String])
            switch job {
            case .kr(let code):
                (path, trId, query) = ("/uapi/domestic-stock/v1/quotations/inquire-price", "FHKST01010100",
                                       ["FID_COND_MRKT_DIV_CODE": "J", "FID_INPUT_ISCD": code])
            case .us(let t, let excd):
                (path, trId, query) = ("/uapi/overseas-price/v1/quotations/price", "HHDFS00000300",
                                       ["AUTH": "", "EXCD": excd, "SYMB": t])
            }
            var c = URLComponents(string: LiveQuotes.kisBase + path)!
            c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            var req = URLRequest(url: c.url!)
            for (k, v) in ["content-type": "application/json; charset=utf-8",
                           "authorization": "Bearer \(token)", "appkey": appKey, "appsecret": appSecret,
                           "tr_id": trId, "custtype": "P"] {
                req.setValue(v, forHTTPHeaderField: k)
            }
            guard let body = await LiveQuotes.getJSON(req, anyStatus: true) as? [String: Any] else { return .failed }
            switch body["msg_cd"] as? String {
            case "EGW00123", "EGW00121": return .tokenExpired
            case "EGW00201": return .rateLimited
            default: break
            }
            guard body["rt_cd"] as? String == "0", let o = body["output"] as? [String: Any] else { return .failed }
            switch job {
            case .kr:
                guard let price = LiveQuotes.num(o["stck_prpr"]), price != 0 else { return .failed }
                return .ok(Price(value: price, change: LiveQuotes.num(o["prdy_ctrt"]) ?? 0))
            case .us:
                guard let last = LiveQuotes.num(o["last"]), last != 0 else { return .failed }
                let base = LiveQuotes.num(o["base"])
                let rate = LiveQuotes.num(o["rate"]) ?? (base.map { $0 == 0 ? 0 : (last - $0) / $0 * 100 } ?? 0)
                return .ok(Price(value: last, change: rate))
            }
        }
    }

    // MARK: - 공통

    /// 200이 아니면 nil. [anyStatus]면 상태와 관계없이 본문을 돌려준다 (KIS는 오류 코드를 본문에 담는다).
    static func getJSON(_ req: URLRequest, anyStatus: Bool = false) async -> Any? {
        guard let (data, res) = try? await session.data(for: req) else { return nil }
        if !anyStatus, (res as? HTTPURLResponse)?.statusCode != 200 { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// 숫자 또는 "+1.23" 같은 문자열 숫자.
    static func num(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")
            return t.isEmpty ? nil : Double(t)
        }
        return nil
    }
}

/// 같은 확장 프로세스에서 위젯 여러 개가 연달아 다시 불러올 때 같은 요청을 한 번만 보낸다.
/// 성공한 결과는 잠깐(60초) 재사용하고, 실패하면 바로 버려 다음 요청이 다시 시도하게 한다.
actor Reuse {
    static let shared = Reuse()
    static let window: TimeInterval = 60

    private var entries: [String: (at: Date, task: Task<Any?, Never>)] = [:]

    func value<T: Sendable>(_ key: String,
                            _ make: @escaping @Sendable () async -> T?) async -> LiveQuotes.Fetch<T> {
        let task: Task<Any?, Never>
        if let e = entries[key], Date().timeIntervalSince(e.at) < Self.window {
            task = e.task
        } else {
            task = Task { await make() }
            entries[key] = (Date(), task)
        }
        if let v = await task.value as? T { return .ok(v) }
        if entries[key]?.task == task { entries[key] = nil }
        return .failed
    }
}

/// 앱(flutter_secure_storage, SecureKisCredentialStore)이 App Group 접근 그룹에 저장한 문자열을 읽는다.
enum Keychain {
    static let service = "flutter_secure_storage_service"

    static func read(_ account: String) -> String? {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: Snapshot.appGroupId,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess, let data = ref as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 표시 문자열 (lib/util/format.dart와 같은 규칙)

extension Fmt {
    /// formatKrw: 100원 미만은 소수 둘째 자리, 1원 미만은 유효숫자 4자리.
    static func krw(_ v: Double) -> String { "\(krwNumber(v))원" }

    static func krwNumber(_ v: Double) -> String {
        let a = abs(v)
        if a > 0 && a < 1 {
            let digits = max(0, 3 - Int(floor(log10(a))))
            return String(format: "%.\(digits)f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }
        return grouped(v, fraction: a < 100 ? 2 : 0)
    }

    /// formatKrwShort: 1억, 1.23억, 520만, 64.4만, 3,500
    static func krwShort(_ v: Double) -> String {
        func trim(_ s: String) -> String {
            s.contains(".") ? s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) : s
        }
        let a = abs(v)
        if a >= 1e8 { return "\(trim(String(format: "%.2f", v / 1e8)))억" }
        if a >= 1e5 { return "\(trim(String(format: a >= 1e6 ? "%.0f" : "%.1f", v / 1e4)))만" }
        return krwNumber(v)
    }

    /// formatFxRate: 정수면 소수 없이, 아니면 둘째 자리까지.
    static func fxRate(_ v: Double) -> String {
        "\(grouped(v, fraction: v == v.rounded() ? 0 : 2))원"
    }

    static func usd(_ v: Double) -> String { "$\(grouped(v, fraction: 2))" }

    /// 미국주식 원화 환산가. 항상 USD/KRW로 계산한다.
    static func stockKrw(_ usd: Double, _ usdKrw: Double) -> Double { (usd * usdKrw).rounded() }

    static func grouped(_ v: Double, fraction: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        f.decimalSeparator = "."
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        f.roundingMode = .halfUp
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(fraction)f", v)
    }
}
