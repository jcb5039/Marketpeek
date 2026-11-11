import Foundation

/// Flutter 앱(lib/widget_bridge/widget_sync.dart)이 App Group에 쓰는 JSON.
/// 필드를 바꾸면 양쪽을 함께 고치고 schemaVersion을 올린다.
struct Snapshot: Codable {
    static let appGroupId = "group.com.yoonhyukju.marketpeek"
    static let key = "snapshot"

    struct Settings: Codable {
        var colorScheme: String  // "korean" | "global"
        var showStockKrw: Bool
        var showMarketStatus: Bool
        var showUpdatedAt: Bool
        var coinRows: Int?   // v4: 사각형 한 칸에 보일 코인 수
        var stockRows: Int?  // v4
        var stocksConnected: Bool?  // v7: 증권사(한투) 연결 여부
        var apiBaseUrl: String?  // v8: 위젯이 환율·AI 이슈를 직접 받을 서버 주소. 없으면 받지 않는다.

        /// v6 이하 스냅샷에는 값이 없으니 연결된 것으로 본다.
        var isStocksConnected: Bool { stocksConnected ?? true }
        var coinRowCount: Int { min(max(coinRows ?? 2, 1), 3) }
        var stockRowCount: Int { min(max(stockRows ?? 1, 1), 3) }
    }

    struct Coin: Codable, Hashable {
        var symbol: String
        var name: String
        var price: String?
        var priceShort: String?  // v2
        var change: Double?
    }

    struct Stock: Codable, Hashable {
        var ticker: String
        var name: String
        var priceUsd: String?
        var priceKrw: String?
        var priceKrwShort: String?  // v2
        var change: Double?
        var excd: String?  // v8: KIS 해외주식 거래소 코드 (NAS·NYS·AMS)
    }

    /// v6: 국내주식
    struct KrStock: Codable, Hashable {
        var code: String
        var name: String
        var price: String?
        var priceShort: String?
        var change: Double?
    }

    struct Fx: Codable {
        var code: String
        var name: String
        var unit: Int
        var rate: String?
        var change: Double?
    }

    struct Issue: Codable {
        var text: String
        var short: String?  // v3: 한 줄 칸용 짧은 요약
        var generatedAt: Date

        /// 쉼표 앞 첫 구절. 짧은 요약도 안 들어갈 때의 마지막 대안.
        var firstClause: String {
            let base = short ?? text
            return base.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? base
        }
    }

    var schemaVersion: Int
    var updatedAt: Date?
    var settings: Settings
    var coins: [Coin]
    var stocks: [Stock]
    var fx: Fx?
    var issue: Issue?
    /// v5: 앱에서 고른 통화 전체, 고른 순서 (자유 구성 위젯용). v4 스냅샷에는 없다.
    var fxList: [Fx]? = nil
    /// v6: 국내주식 (홈 목록 앞 6개). v5 이하 스냅샷에는 없다.
    var krStocks: [KrStock]? = nil
    /// v8: USD/KRW 원값. 위젯이 미국주식만 새로 받았을 때 원화 환산에 쓴다.
    var usdKrw: Double? = nil

    static func load() -> Snapshot? {
        guard
            let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: key),
            let data = raw.data(using: .utf8)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: s))
        }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    /// Dart `toIso8601String()` 형식("2026-11-11T03:04:05.123456Z")과 서버 ISO 문자열을 읽는다.
    /// 소수 초가 7자리 이상 등으로 안 읽히면 소수 초를 떼고 다시 읽는다.
    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: s) { return date }
        f.formatOptions = [.withInternetDateTime]
        if let date = f.date(from: s) { return date }
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return trimmed == s ? nil : f.date(from: trimmed)
    }

    /// 위젯 갤러리 미리보기용 예시 (기획서 6장 예시 값, 실제 시세 아님).
    static let placeholder = Snapshot(
        schemaVersion: 8,
        updatedAt: Date(),
        settings: .init(colorScheme: "korean", showStockKrw: true, showMarketStatus: true, showUpdatedAt: true,
                        coinRows: 3, stockRows: 1),
        coins: [
            .init(symbol: "BTC", name: "비트코인", price: "100,000,000원", priceShort: "1억", change: 2.5),
            .init(symbol: "XRP", name: "리플", price: "3,500원", priceShort: "3,500", change: -1.2),
            .init(symbol: "ETH", name: "이더리움", price: "5,200,000원", priceShort: "520만", change: 0.8),
            .init(symbol: "SOL", name: "솔라나", price: "250,000원", priceShort: "25만", change: -3.4),
            .init(symbol: "DOGE", name: "도지코인", price: "250원", priceShort: "250", change: 5.1),
            .init(symbol: "PEPE", name: "페페", price: "0.00694원", priceShort: "0.00694", change: 6.9),
        ],
        stocks: [.init(ticker: "TSLA", name: "테슬라", priceUsd: "$450.00", priceKrw: "643,500원", priceKrwShort: "64.4만", change: 3.1)],
        fx: .init(code: "USD", name: "미국 달러", unit: 1, rate: "1,430.50원", change: 0.4),
        issue: .init(text: "FOMC 금리 동결, 나스닥·코인 동반 상승", short: "FOMC 동결, 증시 상승", generatedAt: Date()),
        fxList: [
            .init(code: "USD", name: "미국 달러", unit: 1, rate: "1,430.50원", change: 0.4),
            .init(code: "JPY", name: "일본 엔", unit: 100, rate: "950원", change: -0.3),
            .init(code: "EUR", name: "유로", unit: 1, rate: "1,560.20원", change: 0.1),
        ],
        krStocks: [
            .init(code: "005930", name: "삼성전자", price: "98,500원", priceShort: "9.9만", change: 1.24),
            .init(code: "000660", name: "SK하이닉스", price: "412,000원", priceShort: "41.2만", change: -0.72),
        ]
    )
}
