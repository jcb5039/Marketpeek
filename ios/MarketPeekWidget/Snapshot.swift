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

    static func load() -> Snapshot? {
        guard
            let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: key),
            let data = raw.data(using: .utf8)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: s))
        }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    /// 위젯 갤러리 미리보기용 예시 (기획서 6장 예시 값, 실제 시세 아님).
    static let placeholder = Snapshot(
        schemaVersion: 3,
        updatedAt: Date(),
        settings: .init(colorScheme: "korean", showStockKrw: true, showMarketStatus: true, showUpdatedAt: true),
        coins: [
            .init(symbol: "BTC", name: "비트코인", price: "100,000,000원", priceShort: "1억", change: 2.5),
            .init(symbol: "XRP", name: "리플", price: "3,500원", priceShort: "3,500", change: -1.2),
        ],
        stocks: [.init(ticker: "TSLA", name: "테슬라", priceUsd: "$450.00", priceKrw: "643,500원", priceKrwShort: "64.4만", change: 3.1)],
        fx: .init(code: "USD", name: "미국 달러", unit: 1, rate: "1,430.50원", change: 0.4),
        issue: .init(text: "FOMC 금리 동결, 나스닥·코인 동반 상승", short: "FOMC 동결, 증시 상승", generatedAt: Date())
    )
}
