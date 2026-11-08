import SwiftUI
import WidgetKit

// kind 문자열은 lib/widget_bridge/widget_sync.dart의 widgetKinds와 일치해야 한다.
//
// 잠금화면 위젯 크기 (2주차 실기기 검증 대상):
//  - accessoryRectangular: 시계 아래 2칸. 4종 모두. 종목은 최대 3줄(3줄이면 제목 줄 생략될 수 있음).
//  - accessoryInline: 시계 위 한 줄(날짜 옆). 4종 모두.
//  - accessoryCircular: 시계 아래 1칸. 코인은 둥근 사각형에 1개(심볼 위·등락률 아래), 미국주식/환율은 원형 1개.
//  - systemSmall: 홈 화면 2×2. 4종 모두. 종목 1개를 크게(심볼·이름·가격·등락률).
//    자유 구성(MixWidget)은 2×2 전용: 칸 3개에 코인·주식·환율을 섞어서 고른다(Position.swift).
//  iOS 잠금화면 시계 아래는 4칸이 한도: 직사각형 2개 / 직사각형 1 + 원형 2 / 원형 4.
//
// 코인·미국주식은 "위젯 편집"으로 몇 번째 종목부터 보일지 고른다(Position.swift).
// 위젯 확장은 iOS 17+ (AppIntentConfiguration). 앱 본체는 16.0부터 설치된다.

/// 위젯 편집 순서가 가리키는 종목이 없을 때의 안내.
private func missingMessage(_ offset: Int, noun: String) -> String {
    offset == 0 ? "앱에서 \(noun)을 추가하세요" : "\(offset + 1)번째 \(noun)을 앱에서 추가하세요"
}

// MARK: - 코인

struct CoinWidget: Widget {
    let kind = "CoinWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CoinWidgetIntent.self, provider: CoinProvider()) { entry in
            CoinWidgetView(entry: entry).widgetBackground(squareSmall: true)
        }
        .configurationDisplayName("코인")
        .description("고른 코인의 원화 가격과 등락률. 길게 눌러 몇 번째 코인부터 보일지 고를 수 있어요.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall])
    }
}

struct CoinWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let coins = Array((entry.snapshot?.coins ?? []).dropFirst(entry.offset))
        if let snap = entry.snapshot, let c = coins.first {
            let scheme = snap.settings.colorScheme
            let rows = Array(coins.prefix(snap.settings.coinRowCount))
            switch family {
            case .accessoryInline:
                Text("\(c.symbol) \(c.price ?? "—") \(Fmt.change(c.change))")
            case .accessoryCircular:
                SmallSquareQuote(item: .init(symbol: c.symbol, change: c.change), scheme: scheme)
            case .systemSmall:
                SmallHomeCard(title: "코인", snapshot: snap, symbol: c.symbol, name: c.name,
                              prices: [c.price, Fmt.dropWon(c.price), c.priceShort].compactMap { $0 },
                              change: c.change, scheme: scheme)
            default:
                if entry.changeOnly {
                    ChangeOnlyRows(
                        items: coins.prefix(2).map { .init(symbol: $0.symbol, change: $0.change) },
                        scheme: scheme
                    )
                } else {
                    HeaderedRows {
                        WidgetHeader(title: "코인", snapshot: snap)
                    } rows: {
                        PriceGrid(variants: [
                            // 1) 100,000,000원  2) 100,000,000  3) 1억
                            rows.map { PriceRow(symbol: $0.symbol, price: $0.price ?? "—", change: $0.change) },
                            rows.map { PriceRow(symbol: $0.symbol, price: Fmt.dropWon($0.price) ?? "—", change: $0.change) },
                            rows.map { PriceRow(symbol: $0.symbol, price: $0.priceShort ?? Fmt.dropWon($0.price) ?? "—", change: $0.change) },
                        ], scheme: scheme)
                    }
                }
            }
        } else {
            EmptyHint(title: "코인", message: missingMessage(entry.offset, noun: "코인"))
        }
    }
}

// MARK: - 미국주식

struct StockWidget: Widget {
    let kind = "StockWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ListPositionIntent.self, provider: PositionProvider()) { entry in
            StockWidgetView(entry: entry).widgetBackground()
        }
        .configurationDisplayName("미국주식")
        .description("달러·원화 가격, 등락률, 미국장 상태. 길게 눌러 몇 번째 종목부터 보일지 고를 수 있어요.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall])
    }
}

struct StockWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let stocks = Array((entry.snapshot?.stocks ?? []).dropFirst(entry.offset))
        if let snap = entry.snapshot, !snap.settings.isStocksConnected,
           !stocks.isEmpty, stocks.allSatisfy({ $0.priceUsd == nil }) {
            // 증권사 미연결이라 가격이 하나도 없으면 "—" 대신 연결 안내.
            if family == .accessoryInline {
                Text("미국주식 · 앱에서 증권사 연결")
            } else {
                EmptyHint(title: "미국주식", message: "앱에서 증권사를 연결하세요")
            }
        } else if let snap = entry.snapshot, let st = stocks.first {
            let s = snap.settings
            let rows = Array(stocks.prefix(s.stockRowCount))
            let title = s.showMarketStatus ? "미국주식 · \(MarketHours.label(at: entry.date))" : "미국주식"
            switch family {
            case .accessoryInline:
                Text("\(st.ticker) \(st.priceUsd ?? "—") \(Fmt.change(st.change))")
            case .accessoryCircular:
                CircularQuote(symbol: st.ticker, change: st.change, scheme: s.colorScheme)
            case .systemSmall:
                SmallHomeCard(title: title, snapshot: snap, symbol: st.ticker, name: st.name,
                              prices: [st.priceUsd ?? "—"],
                              secondary: s.showStockKrw ? (st.priceKrw ?? st.priceKrwShort) : nil,
                              change: st.change, scheme: s.colorScheme)
            default:
                HeaderedRows {
                    WidgetHeader(title: title, snapshot: snap)
                } rows: {
                    if rows.count == 1 {
                        single(st, s)
                    } else {
                        PriceGrid(variants: stockVariants(rows, s), scheme: s.colorScheme)
                    }
                }
            }
        } else {
            EmptyHint(title: "미국주식", message: missingMessage(entry.offset, noun: "종목"))
        }
    }

    /// 1종목: 티커·등락률 / 달러·원화 두 줄
    private func single(_ st: Snapshot.Stock, _ s: Snapshot.Settings) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(st.ticker).font(.caption.weight(.bold))
                Spacer(minLength: 2)
                ChangeText(pct: st.change, scheme: s.colorScheme).font(.caption2)
            }
            HStack(spacing: 4) {
                Text(st.priceUsd ?? "—").font(.caption).trend(st.change)
                if s.showStockKrw {
                    Text(st.priceKrw ?? "—").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    /// 2~3종목: 한 줄씩. 달러+원화 → 달러+짧은 원화 → 달러만 순으로 맞춘다.
    private func stockVariants(_ stocks: [Snapshot.Stock], _ s: Snapshot.Settings) -> [[PriceRow]] {
        var v: [[PriceRow]] = []
        if s.showStockKrw {
            v.append(stocks.map { PriceRow(symbol: $0.ticker, price: $0.priceUsd ?? "—", extra: $0.priceKrw ?? "—", change: $0.change) })
            v.append(stocks.map { PriceRow(symbol: $0.ticker, price: $0.priceUsd ?? "—", extra: $0.priceKrwShort ?? "—", change: $0.change) })
        }
        v.append(stocks.map { PriceRow(symbol: $0.ticker, price: $0.priceUsd ?? "—", change: $0.change) })
        return v
    }
}

// MARK: - 환율

struct FxWidget: Widget {
    let kind = "FxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            FxWidgetView(entry: entry).widgetBackground()
        }
        .configurationDisplayName("환율")
        .description("앱에서 고른 통화의 원화 환율과 등락률")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall])
    }
}

struct FxWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snap = entry.snapshot, let fx = snap.fx {
            let scheme = snap.settings.colorScheme
            let pair = fx.unit == 1 ? "\(fx.code)/KRW" : "\(fx.unit) \(fx.code)"
            switch family {
            case .accessoryInline:
                Text("\(pair) \(fx.rate ?? "—") \(Fmt.change(fx.change))")
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text(fx.code).font(.system(size: 12, weight: .bold))
                        Text(Fmt.dropWon(fx.rate) ?? "—").font(.system(size: 11)).monospacedDigit()
                            .trend(fx.change)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 3)
                }
            case .systemSmall:
                SmallHomeCard(title: "환율", snapshot: snap, symbol: pair, name: fx.name,
                              prices: [fx.rate, Fmt.dropWon(fx.rate)].compactMap { $0 },
                              change: fx.change, scheme: scheme)
            default:
                VStack(alignment: .leading, spacing: 1) {
                    WidgetHeader(title: "환율 · \(pair)", snapshot: snap)
                    Text(fx.rate ?? "—")
                        .font(.headline)
                        .trend(fx.change)
                        .minimumScaleFactor(0.7)
                    ChangeText(pct: fx.change, scheme: scheme).font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyHint(title: "환율", message: "앱에서 통화를 고르세요")
        }
    }
}

// MARK: - AI 어제 이슈

struct IssueWidget: Widget {
    let kind = "IssueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            IssueWidgetView(entry: entry).widgetBackground()
        }
        .configurationDisplayName("AI 어제 이슈")
        .description("전날 가장 큰 시장 이슈를 매일 아침 한 줄로")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct IssueWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snap = entry.snapshot, let issue = snap.issue {
            switch family {
            case .accessoryInline:
                // 한 줄 칸은 iOS가 글자 크기를 고정하므로 들어가는 문장을 고르게 한다.
                ViewThatFits {
                    Text("✦ \(issue.text)")
                    if let short = issue.short { Text("✦ \(short)") }
                    Text(issue.firstClause)
                }
            case .systemSmall:
                VStack(alignment: .leading, spacing: 6) {
                    Text("✦ 어제 이슈 · AI").font(.caption2.weight(.semibold))
                    Text(issue.text)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(4)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("\(Fmt.hm(issue.generatedAt)) 갱신").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            default:
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("✦ 어제 이슈 · AI").font(.caption2.weight(.semibold))
                        Spacer(minLength: 0)
                        Text("\(Fmt.hm(issue.generatedAt)) 갱신").font(.caption2).foregroundStyle(.secondary)
                    }
                    .widgetAccentable()
                    Text(issue.text)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyHint(title: "✦ 어제 이슈 · AI", message: "앱을 한 번 열면 표시돼요")
        }
    }
}

// MARK: - Bundle

@main
struct MarketPeekWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoinWidget()
        StockWidget()
        FxWidget()
        IssueWidget()
        MixWidget()
    }
}

// MARK: - 자유 구성 (홈 2×2)

struct MixWidget: Widget {
    let kind = "MixWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: MixWidgetIntent.self, provider: MixProvider()) { entry in
            MixWidgetView(entry: entry).widgetBackground()
        }
        .configurationDisplayName("자유 구성")
        .description("칸 3개에 코인·국내주식·미국주식·환율을 골라 담아요. 길게 눌러 \u{201C}위젯 편집\u{201D}에서 바꿀 수 있어요.")
        .supportedFamilies([.systemSmall])
    }
}

/// 자유 구성 한 칸: 심볼 · 등락률 / 가격.
struct MixItem: Hashable {
    var symbol: String
    var price: String
    var change: Double?
    var missing = false

    static func resolve(_ id: String, in s: Snapshot) -> MixItem {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "", key = parts.count > 1 ? parts[1] : ""
        // 주식 가격이 없을 때: 증권사 미연결이면 연결 안내.
        let noPrice = s.settings.isStocksConnected ? "—" : "증권사 연결 필요"
        switch kind {
        case "coin":
            if let c = s.coins.first(where: { $0.symbol == key }) {
                return MixItem(symbol: c.symbol, price: c.priceShort ?? Fmt.dropWon(c.price) ?? "—", change: c.change)
            }
        case "kr":
            if let k = (s.krStocks ?? []).first(where: { $0.code == key }) {
                return MixItem(symbol: k.name, price: k.priceShort ?? Fmt.dropWon(k.price) ?? noPrice, change: k.change)
            }
        case "stock":
            if let st = s.stocks.first(where: { $0.ticker == key }) {
                return MixItem(symbol: st.ticker, price: st.priceUsd ?? noPrice, change: st.change)
            }
        case "fx":
            let fxs = s.fxList ?? (s.fx.map { [$0] } ?? [])
            if let fx = fxs.first(where: { $0.code == key }) {
                return MixItem(symbol: fx.unit == 1 ? fx.code : "\(fx.unit)\(fx.code)",
                               price: Fmt.dropWon(fx.rate) ?? "—", change: fx.change)
            }
        default: break
        }
        return MixItem(symbol: key.isEmpty ? "—" : key, price: "앱에서 추가하세요", change: nil, missing: true)
    }

    /// 아무 칸도 안 골랐을 때: 첫 코인 · 첫 종목 · 앱에서 고른 환율.
    static func defaults(in s: Snapshot) -> [String] {
        [s.coins.first.map { "coin:\($0.symbol)" },
         s.stocks.first.map { "stock:\($0.ticker)" },
         s.fx.map { "fx:\($0.code)" }].compactMap { $0 }
    }
}

struct MixWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snap = entry.snapshot {
            let picked = entry.selected.compactMap { $0 }
            let ids = picked.isEmpty ? MixItem.defaults(in: snap) : picked
            let items = ids.map { MixItem.resolve($0, in: snap) }
            let scheme = snap.settings.colorScheme
            if items.isEmpty {
                EmptyHint(title: "자유 구성", message: "앱에서 코인·종목·환율을 추가하세요")
            } else {
                // 세로가 모자라면 제목 줄을 빼고 항목만 보여준다.
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetHeader(title: "자유 구성", snapshot: snap)
                        rows(items, scheme)
                    }
                    rows(items, scheme)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            EmptyHint(title: "자유 구성", message: "앱을 한 번 열면 표시돼요")
        }
    }

    private func rows(_ items: [MixItem], _ scheme: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(item.symbol).font(.system(size: 14, weight: .bold))
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 2)
                        ChangeText(pct: item.change, scheme: scheme)
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                    Text(item.price)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.7)
                }
                .lineLimit(1)
            }
        }
    }
}

// MARK: - Previews
// Xcode Canvas(⌥⌘↩)에서 위젯 4종을 크기별로 확인한다. 값은 Snapshot.placeholder 예시.
// 사각형 미리보기는 두 번째 엔트리(snapshot: nil)로 빈 상태도 볼 수 있다.

#if DEBUG
private let previewEntry = SnapshotEntry(date: .now, snapshot: .placeholder)
private let emptyEntry = SnapshotEntry(date: .now, snapshot: nil)
/// 위젯 편집에서 "4번째부터"를 고른 경우.
private let fourthEntry = SnapshotEntry(date: .now, snapshot: .placeholder, offset: 3)
/// 위젯 편집에서 "이름·등락률 2개"를 고른 경우.
private let changeOnlyEntry = SnapshotEntry(date: .now, snapshot: .placeholder, changeOnly: true)

#Preview("코인 · 사각형", as: .accessoryRectangular) { CoinWidget() } timeline: { previewEntry; changeOnlyEntry; fourthEntry; emptyEntry }
#Preview("코인 · 한 줄", as: .accessoryInline) { CoinWidget() } timeline: { previewEntry }
#Preview("코인 · 작은 사각형", as: .accessoryCircular) { CoinWidget() } timeline: { previewEntry; fourthEntry }

#Preview("미국주식 · 사각형", as: .accessoryRectangular) { StockWidget() } timeline: { previewEntry; emptyEntry }
#Preview("미국주식 · 한 줄", as: .accessoryInline) { StockWidget() } timeline: { previewEntry }
#Preview("미국주식 · 원형", as: .accessoryCircular) { StockWidget() } timeline: { previewEntry }

#Preview("환율 · 사각형", as: .accessoryRectangular) { FxWidget() } timeline: { previewEntry; emptyEntry }
#Preview("환율 · 한 줄", as: .accessoryInline) { FxWidget() } timeline: { previewEntry }
#Preview("환율 · 원형", as: .accessoryCircular) { FxWidget() } timeline: { previewEntry }

#Preview("AI 이슈 · 사각형", as: .accessoryRectangular) { IssueWidget() } timeline: { previewEntry; emptyEntry }
#Preview("AI 이슈 · 한 줄", as: .accessoryInline) { IssueWidget() } timeline: { previewEntry }
#Preview("코인 · 홈 2×2", as: .systemSmall) { CoinWidget() } timeline: { previewEntry; fourthEntry; emptyEntry }
#Preview("미국주식 · 홈 2×2", as: .systemSmall) { StockWidget() } timeline: { previewEntry; emptyEntry }
#Preview("환율 · 홈 2×2", as: .systemSmall) { FxWidget() } timeline: { previewEntry; emptyEntry }
#Preview("자유 구성 · 기본값", as: .systemSmall) { MixWidget() } timeline: { previewEntry; emptyEntry }
#Preview("자유 구성 · 고른 항목", as: .systemSmall) { MixWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder, selected: ["coin:BTC", "stock:TSLA", "fx:JPY"])
    SnapshotEntry(date: .now, snapshot: .placeholder, selected: ["coin:ETH", nil, "coin:NONE"])
}
#Preview("AI 이슈 · 홈 2×2", as: .systemSmall) { IssueWidget() } timeline: { previewEntry; emptyEntry }

#endif
