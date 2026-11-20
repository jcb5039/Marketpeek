import Charts
import SwiftUI
import WidgetKit
import ActivityKit

// kind 문자열은 lib/widget_bridge/widget_sync.dart의 widgetKinds와 일치해야 한다.
//
// 잠금화면 위젯 크기 (2주차 실기기 검증 대상):
//  - accessoryRectangular: 시계 아래 2칸. 4종 모두. 종목은 최대 3줄(3줄이면 제목 줄 생략될 수 있음).
//  - accessoryInline: 시계 위 한 줄(날짜 옆). 4종 모두.
//  - accessoryCircular: 시계 아래 1칸. 코인은 둥근 사각형에 1개(심볼 위·등락률 아래), 미국주식/환율은 원형 1개.
//  - systemSmall: 홈 화면 2×2. 4종 모두. 종목 1개를 크게(심볼·이름·가격·등락률).
//    자유 구성(MixWidget)은 2×2 전용: 칸 3개에 코인·주식·환율을 섞어서 고른다(Position.swift).
//  - systemMedium(4×2)·systemLarge(4×4): 코인·미국주식·환율. 목록(3줄/6줄) 또는 "한 종목 크게"(코인·미국주식만,
//    위젯 편집 "큰 위젯 모양"). 홈 위젯 제목 줄의 › 버튼은 다음 종목(2×2·한 종목)/다음 묶음(목록)으로 넘긴다.
//    스냅샷에는 종목이 6개까지라 4×4 목록은 버튼 없이 다 보인다.
//  iOS 잠금화면 시계 아래는 4칸이 한도: 직사각형 2개 / 직사각형 1 + 원형 2 / 원형 4.
//
// 코인·미국주식은 "위젯 편집"에서 보여줄 종목을 이름으로 고른다(Position.swift).
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
            CoinWidgetView(entry: entry).widgetBackground(squareSmall: true, backdrop: .coin(entry))
        }
        .configurationDisplayName("코인")
        .description("고른 코인의 원화 가격과 등락률. 길게 눌러 코인과 배경을 고를 수 있어요.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular,
                            .systemSmall, .systemMedium, .systemLarge])
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
            case .systemSmall where entry.layout == .single && Backdrop.coin(entry) != nil:
                // 로고 배경을 고른 2×2는 로고 배경용 카드.
                SmallHomeCard(title: "코인", snapshot: snap, now: entry.date, symbol: c.symbol, name: c.name,
                              prices: [c.price, Fmt.dropWon(c.price), c.priceShort].compactMap { $0 },
                              change: c.change, scheme: scheme, icon: .coin(c.symbol), next: entry.pagingId)
            case .systemSmall, .systemMedium, .systemLarge:
                HomeCard(title: "코인", entry: entry, snapshot: snap,
                         items: snap.coins.map { HomeItem.coin($0, snap) })
            default:
                if entry.changeOnly {
                    ChangeOnlyRows(
                        items: coins.prefix(2).map { .init(symbol: $0.symbol, change: $0.change) },
                        scheme: scheme
                    )
                } else {
                    HeaderedRows {
                        WidgetHeader(title: "코인", snapshot: snap, now: entry.date)
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
            StockWidgetView(entry: entry).widgetBackground(backdrop: .stock(entry))
        }
        .configurationDisplayName("미국주식")
        .description("달러·원화 가격, 등락률, 미국장 상태. 길게 눌러 종목과 배경을 고를 수 있어요.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular,
                            .systemSmall, .systemMedium, .systemLarge])
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
            case .systemSmall where entry.layout == .single && Backdrop.stock(entry) != nil:
                SmallHomeCard(title: title, snapshot: snap, now: entry.date, symbol: st.ticker, name: st.name,
                              prices: [st.priceUsd ?? "—"],
                              // 원화는 달러 옆에 (들어가면 전체, 아니면 "53만"). 원화 환율이 없으면 달러만.
                              inlineSecondary: s.showStockKrw ? [st.priceKrw, st.priceKrwShort].compactMap { $0 } : [],
                              change: st.change, scheme: s.colorScheme,
                              icon: .stock(id: "us-\(st.ticker)", letter: st.ticker), next: entry.pagingId)
            case .systemSmall, .systemMedium, .systemLarge:
                HomeCard(title: title, entry: entry, snapshot: snap,
                         items: snap.stocks.map { HomeItem.stock($0, snap, now: entry.date) })
            default:
                HeaderedRows {
                    WidgetHeader(title: title, snapshot: snap, now: entry.date)
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
        AppIntentConfiguration(kind: kind, intent: FxWidgetIntent.self, provider: FxProvider()) { entry in
            FxWidgetView(entry: entry).widgetBackground(backdrop: .fx(entry))
        }
        .configurationDisplayName("환율")
        .description("앱에서 고른 통화의 원화 환율과 등락률. 홈 화면에서는 › 버튼으로 다음 통화를 봐요.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular,
                            .systemSmall, .systemMedium, .systemLarge])
    }
}

struct FxWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private static func pair(_ fx: Snapshot.Fx) -> String {
        fx.unit == 1 ? "\(fx.code)/KRW" : "\(fx.unit) \(fx.code)"
    }

    var body: some View {
        let fxs = entry.snapshot.map { $0.fxList ?? ($0.fx.map { [$0] } ?? []) } ?? []
        // 잠금화면은 앱에서 고른 대표 통화. 홈 화면은 대표 통화부터 다음 버튼을 누른 만큼(FxProvider).
        if let snap = entry.snapshot, let fx = snap.fx {
            let scheme = snap.settings.colorScheme
            let pair = Self.pair(fx)
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
            case .systemSmall, .systemMedium, .systemLarge:
                HomeCard(title: "환율", listTitle: "환율 · 원화 기준", entry: entry, snapshot: snap,
                         items: fxs.map { HomeItem.fx($0, snap) })
            default:
                VStack(alignment: .leading, spacing: 1) {
                    WidgetHeader(title: "환율 · \(pair)", snapshot: snap, now: entry.date)
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
        StaticConfiguration(kind: kind, provider: SnapshotProvider(part: .issue)) { entry in
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

// MARK: - 홈 화면 시안 (코인·미국주식·환율·자유 구성 공통)
// 라이트·다크는 iOS 설정을 따른다(Shared.swift `HomePalette`). 아래 "어제 이슈" 줄은 이슈가 있을 때만 나오고,
// 없으면 그 자리를 가격·목록이 채운다. 차트 선 자리는 다음 작업에서 채운다.

/// 홈 위젯 한 종목. 한 종목 모양은 [price]·[sub], 목록은 [listPrice]·[listSub]를 쓴다.
struct HomeItem: Hashable {
    var icon: ItemIcon.Kind
    var symbol: String
    var name: String
    /// 한 종목 모양의 큰 가격 ("9917만원", "$390.84", "1,336.70원")
    var price: String
    /// 한 종목 모양의 가격 아래 ("업비트 · 원화", "522,436원", "1 USD 기준")
    var sub: String? = nil
    /// 목록 가격 ("9917만", "$390.84", "1,336.70")
    var listPrice: String
    /// 4×4 목록 가격 아래 (미국주식 원화)
    var listSub: String? = nil
    var change: Double?
    /// 4×4 한 종목 아래 정보 칸 3개 (이름, 값)
    var info: [Pair] = []

    struct Pair: Hashable {
        var label: String
        var value: String
    }

    /// 환율 항목인지 (국기 아이콘). 2×2 한 종목에서 환율 전용 배치를 쓴다.
    var isFx: Bool {
        if case .flag = icon { return true }
        return false
    }

    init(icon: ItemIcon.Kind, symbol: String, name: String, price: String, sub: String? = nil,
         listPrice: String, listSub: String? = nil, change: Double?, info: [Pair] = []) {
        self.icon = icon; self.symbol = symbol; self.name = name; self.price = price; self.sub = sub
        self.listPrice = listPrice; self.listSub = listSub; self.change = change; self.info = info
    }

    private static func updated(_ s: Snapshot) -> Pair {
        Pair(label: "마지막 갱신", value: s.updatedAt.map(Fmt.hm) ?? "—")
    }

    static func coin(_ c: Snapshot.Coin, _ s: Snapshot) -> HomeItem {
        let short = c.priceShort.map { $0.hasSuffix("원") ? $0 : "\($0)원" }
        return HomeItem(icon: .coin(c.symbol), symbol: c.symbol, name: c.name,
                        price: short ?? c.price ?? "—", sub: "업비트 · 원화",
                        listPrice: c.priceShort ?? Fmt.dropWon(c.price) ?? "—", change: c.change,
                        info: [Pair(label: "시세 출처", value: "업비트"),
                               Pair(label: "기준 통화", value: "원화 KRW"), updated(s)])
    }

    static func stock(_ st: Snapshot.Stock, _ s: Snapshot, now: Date) -> HomeItem {
        let krw = s.settings.showStockKrw ? st.priceKrw : nil
        let noPrice = s.settings.isStocksConnected ? "—" : "증권사 연결 필요"
        let open = MarketHours.isOpen(at: now)
        return HomeItem(icon: .stock(id: "us-\(st.ticker)", letter: st.ticker), symbol: st.ticker, name: st.name,
                        price: st.priceUsd ?? noPrice, sub: krw,
                        listPrice: st.priceUsd ?? "—", listSub: krw, change: st.change,
                        info: [Pair(label: "장 상태", value: open ? "장중" : "장 마감 · 종가"),
                               Pair(label: "적용 환율 USD/KRW",
                                    value: s.usdKrw.flatMap { Fmt.dropWon(Fmt.fxRate($0)) } ?? "—"),
                               updated(s)])
    }

    static func fx(_ fx: Snapshot.Fx, _ s: Snapshot) -> HomeItem {
        HomeItem(icon: .flag(fx.code), symbol: fx.code,
                 name: fx.unit == 1 ? fx.name : "\(fx.name) (\(fx.unit))",
                 price: fx.rate ?? "—", sub: "\(fx.unit) \(fx.code) 기준",
                 listPrice: Fmt.dropWon(fx.rate) ?? "—", change: fx.change,
                 info: [Pair(label: "통화쌍", value: "\(fx.code)/KRW"),
                        Pair(label: "기준 단위", value: "\(fx.unit) \(fx.code)"), updated(s)])
    }
}

/// 홈 위젯 시안 카드: 제목 줄 / 한 종목 또는 목록 / (이슈가 있으면) 어제 이슈 줄.
struct HomeCard: View {
    let title: String
    var listTitle: String? = nil
    let snapshot: Snapshot
    /// 전체 항목. [offset]부터 한 화면 개수만큼 보여준다(끝을 지나면 처음부터).
    let items: [HomeItem]
    /// 풀어 둔 모양 (한 종목 / 목록)
    let layout: HomeLayout
    var offset = 0
    var next: String? = nil
    /// 한 종목 모양의 차트 (오래된 가격부터). nil이면 차트 없이.
    var chart: PriceChart? = nil
    /// 목록 줄마다 색 (자유 구성 위젯 편집 "배경"). 기본이면 시안 목록.
    var rowStyle: MixBackground = .plain
    @Environment(\.widgetFamily) private var family

    init(title: String, listTitle: String? = nil, snapshot: Snapshot, items: [HomeItem],
         layout: HomeLayout, offset: Int = 0, next: String? = nil, chart: PriceChart? = nil,
         rowStyle: MixBackground = .plain) {
        self.title = title; self.listTitle = listTitle; self.snapshot = snapshot; self.items = items
        self.layout = layout; self.offset = offset; self.next = next; self.chart = chart
        self.rowStyle = rowStyle
    }

    init(title: String, listTitle: String? = nil, entry: SnapshotEntry, snapshot: Snapshot, items: [HomeItem]) {
        self.init(title: title, listTitle: listTitle, snapshot: snapshot, items: items,
                  layout: entry.layout, offset: entry.offset, next: entry.pagingId, chart: entry.chart)
    }

    /// 차트. 색은 등락률과 같은 상승·하락 색, 점선은 등락률 기준 가격(코인: 오늘 오전 9시).
    /// 축은 크기별로: 4×4 시간·가격, 4×2 가격, 2×2 없음.
    @ViewBuilder
    private func sparkline(_ item: HomeItem) -> some View {
        if let chart, chart.points.count >= 2 {
            PriceChartView(chart: chart, change: item.change, scheme: scheme,
                           axes: family == .systemLarge ? .full : (family == .systemMedium ? .price : .none))
        }
    }

    private var scheme: String { snapshot.settings.colorScheme }

    var body: some View {
        let issue = snapshot.issue
        let hasIssue = issue != nil
        let shown = WidgetPaging.window(items, start: offset,
                                        size: WidgetPaging.pageSize(family, layout: layout, hasIssue: hasIssue))
        // 환율 2×2 한 종목: 차트·이슈 줄 없이 이름·환율 / 기준·등락률 / 최근 업데이트 (시각은 아래로).
        let fxSmall = family == .systemSmall && layout == .single && (shown.first?.isFx ?? false)
        VStack(alignment: .leading, spacing: 0) {
            header(layout == .list ? (listTitle ?? title) : title, showTime: !fxSmall)
            Group {
                if fxSmall, let item = shown.first {
                    fxSingleSmall(item)
                } else if layout == .single, let item = shown.first {
                    switch family {
                    case .systemLarge: singleLarge(item)
                    case .systemMedium: singleMedium(item)
                    default: singleSmall(item)
                    }
                } else if rowStyle != .plain {
                    tintedList(shown, hasIssue: hasIssue)
                } else {
                    switch family {
                    case .systemLarge: listLarge(shown, hasIssue: hasIssue)
                    case .systemMedium: listMedium(shown, hasIssue: hasIssue)
                    default: listSmall(shown, hasIssue: hasIssue)
                    }
                }
            }
            if let issue, !fxSmall { issueFooter(issue) }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 다음 종목으로 넘길 때 숫자·차트가 서서히 바뀌는 iOS 기본 효과를 끄고 바로 바꾼다.
        .contentTransition(.identity)
        .transaction { $0.animation = nil }
    }

    // MARK: 제목 줄: 제목 ······ 15:35 ↻ ›

    private func header(_ text: String, showTime: Bool = true) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if showTime, snapshot.settings.showUpdatedAt, let t = snapshot.updatedAt {
                Text(Fmt.hm(t)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
            RefreshButton()
            if let next { PageButtons(pagingId: next) }
        }
        .widgetAccentable()
    }

    // MARK: 어제 이슈 줄

    private func issueFooter(_ issue: Snapshot.Issue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HomePalette.line.frame(height: 1).padding(.bottom, 4)
            if family != .systemSmall {
                Text("✦ 어제 이슈 · AI").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text(issue.text)
                .font(.system(size: family == .systemSmall ? 10 : 11, weight: .medium))
                .lineLimit(family == .systemMedium ? 1 : 2)
                .minimumScaleFactor(0.9)
        }
    }

    // MARK: 한 종목

    private func nameLine(_ item: HomeItem, icon: CGFloat, font: CGFloat, showName: Bool) -> some View {
        HStack(spacing: 5) {
            ItemIcon(kind: item.icon, size: icon)
            Text(item.symbol).font(.system(size: font, weight: .bold))
            if showName {
                Text(item.name).font(.system(size: font * 0.65)).foregroundStyle(.secondary)
            }
        }
        .minimumScaleFactor(0.7)
    }

    private func change(_ pct: Double?, _ size: CGFloat) -> some View {
        ChangeText(pct: pct, scheme: scheme).font(.system(size: size, weight: .semibold)).monospacedDigit()
    }

    private func bigPrice(_ s: String, _ size: CGFloat) -> some View {
        Text(s).font(.system(size: size, weight: .bold)).monospacedDigit().minimumScaleFactor(0.5)
    }

    /// 환율 2×2 한 종목: 🇺🇸 USD ··· 1,333.7 / 1 USD 기준 ··· ▲0.10% / 최근 업데이트: 15:35
    private func fxSingleSmall(_ item: HomeItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            // 아래 줄에 "1 USD 기준"이 있으니 가격은 '원'을 빼고 크게.
            // 이름(국기·코드)은 줄이지 않고, 가격이 남는 폭에 맞춰 줄어든다.
            // 가격은 폭이 좁은 기본 숫자(monospacedDigit 아님)로 한 글자라도 크게.
            HStack(spacing: 4) {
                nameLine(item, icon: 14, font: 13, showName: false)
                    .fixedSize()
                Spacer(minLength: 2)
                Text(Self.oneDecimal(item.price))
                    .font(.system(size: 20, weight: .bold))
                    .minimumScaleFactor(0.5)
            }
            HStack(spacing: 4) {
                if let sub = item.sub { Text(sub).font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer(minLength: 2)
                change(item.change, 13)
            }
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if snapshot.settings.showUpdatedAt {
                Text("최근 업데이트: \(snapshot.updatedAt.map(Fmt.hm) ?? "—")")
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    /// 환율 2×2 가격: '원'을 빼고 소수점 한 자리로 반올림 ("1,331.10원" → "1,331.1"). 숫자가 아니면 그대로.
    static func oneDecimal(_ price: String) -> String {
        let raw = Fmt.dropWon(price) ?? price
        guard let v = Double(raw.replacingOccurrences(of: ",", with: "")) else { return raw }
        return v.formatted(.number.precision(.fractionLength(1)).grouping(.automatic))
    }

    private func singleSmall(_ item: HomeItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Spacer(minLength: 4)
            if snapshot.issue != nil {
                // 이슈 줄이 있으면 차트는 이름 오른쪽에 작게.
                HStack(spacing: 6) {
                    nameLine(item, icon: 16, font: 13, showName: false)
                    Spacer(minLength: 4)
                    sparkline(item).frame(width: 52, height: 16)
                }
            } else {
                nameLine(item, icon: 16, font: 13, showName: false)
                sparkline(item).frame(maxWidth: .infinity, maxHeight: 30).padding(.vertical, 4)
            }
            Spacer(minLength: 4)
            bigPrice(item.price, 20)
            HStack(spacing: 4) {
                if let sub = item.sub { Text(sub).font(.system(size: 9)).foregroundStyle(.secondary) }
                Spacer(minLength: 2)
                change(item.change, 11)
            }
            .minimumScaleFactor(0.7)
            Spacer(minLength: snapshot.issue == nil ? 0 : 6)
        }
    }

    private func singleMedium(_ item: HomeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 4)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    nameLine(item, icon: 18, font: 14, showName: true)
                    bigPrice(item.price, 24)
                    if let sub = item.sub { Text(sub).font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    sparkline(item).frame(width: 130, height: 46)
                    change(item.change, 14)
                }
            }
            Spacer(minLength: snapshot.issue == nil ? 0 : 6)
        }
    }

    private func singleLarge(_ item: HomeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                nameLine(item, icon: 20, font: 16, showName: true)
                Spacer(minLength: 6)
                change(item.change, 15)
            }
            .padding(.top, 10)
            bigPrice(item.price, 34).padding(.top, 8)
            if let sub = item.sub { Text(sub).font(.system(size: 11)).foregroundStyle(.secondary) }
            if chart != nil {
                sparkline(item).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.vertical, 12)
            } else {
                Spacer(minLength: 8)
            }
            HomePalette.line.frame(height: 1)
            HStack(alignment: .top, spacing: 6) {
                ForEach(item.info, id: \.self) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.label).font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(p.value).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    }
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: 목록

    /// 한 줄: 심볼 | 가격 | 등락률 (2×2, 4×2 이슈 있음)
    private func compactRows(_ rows: [HomeItem], spacing: CGFloat) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                GridRow {
                    Text(r.symbol).font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.listPrice).font(.system(size: 11)).monospacedDigit()
                        .gridColumnAlignment(.trailing)
                    change(r.change, 11).gridColumnAlignment(.trailing)
                }
            }
        }
        .minimumScaleFactor(0.6)
    }

    /// 두 줄: 심볼·이름 | 가격·등락률 (4×2 이슈 없음)
    private func stackedRows(_ rows: [HomeItem]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                GridRow {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.symbol).font(.system(size: 11, weight: .bold))
                        Text(r.name).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(r.listPrice).font(.system(size: 11)).monospacedDigit()
                        change(r.change, 10)
                    }
                    .gridColumnAlignment(.trailing)
                }
            }
        }
        .minimumScaleFactor(0.6)
    }

    private func listSmall(_ rows: [HomeItem], hasIssue: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            compactRows(rows, spacing: hasIssue ? 4 : 5).padding(.top, 8)
            Spacer(minLength: hasIssue ? 6 : 0)
        }
    }

    private func listMedium(_ rows: [HomeItem], hasIssue: Bool) -> some View {
        let left = Array(rows.prefix(3)), right = Array(rows.dropFirst(3))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                if hasIssue {
                    compactRows(left, spacing: 4)
                    compactRows(right, spacing: 4)
                } else {
                    stackedRows(left)
                    stackedRows(right)
                }
            }
            .padding(.top, 8)
            Spacer(minLength: hasIssue ? 6 : 0)
        }
    }

    /// 자유 구성 "줄마다 색" 큰 목록: 줄마다 로고·국기 색을 깐다(2×2 줄마다 색과 같은 3가지 모양).
    /// 4×2는 2열, 4×4는 1열.
    private func tintedList(_ rows: [HomeItem], hasIssue: Bool) -> some View {
        let large = family == .systemLarge
        let columns = large ? [rows] : [Array(rows.prefix(3)), Array(rows.dropFirst(3))]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                    VStack(spacing: large ? 5 : 4) {
                        ForEach(Array(col.enumerated()), id: \.offset) { _, r in tintedRow(r, large: large) }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.top, 8)
            Spacer(minLength: hasIssue ? 6 : 0)
        }
    }

    private func tintedRow(_ r: HomeItem, large: Bool) -> some View {
        HStack(spacing: 6) {
            ItemIcon(kind: r.icon, size: large ? 22 : 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(r.symbol).font(.system(size: large ? 12 : 11, weight: .bold))
                if large { Text(r.name).font(.system(size: 9)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(r.listPrice).font(.system(size: large ? 12 : 10)).monospacedDigit()
                change(r.change, large ? 11 : 9)
            }
        }
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6)
        .padding(.vertical, large ? 4 : 3)
        .background {
            if let c = ItemTint.color(for: r.icon) {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                switch rowStyle {
                case .rowCard:
                    shape.fill(Color.white.opacity(0.08)).overlay(shape.strokeBorder(c.opacity(0.9), lineWidth: 1.5))
                case .rowFade:
                    shape.fill(LinearGradient(colors: [c.opacity(0.8), c.opacity(0)], startPoint: .leading, endPoint: .trailing))
                default:
                    shape.fill(c.opacity(0.55))
                }
            }
        }
    }

    private func listLarge(_ rows: [HomeItem], hasIssue: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: hasIssue ? 7 : 9) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    GridRow {
                        HStack(spacing: 8) {
                            ItemIcon(kind: r.icon, size: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(r.symbol).font(.system(size: 12, weight: .bold))
                                Text(r.name).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(r.listPrice).font(.system(size: 12)).monospacedDigit()
                            if let s = r.listSub {
                                Text(s).font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .gridColumnAlignment(.trailing)
                        change(r.change, 12).gridColumnAlignment(.trailing)
                    }
                }
            }
            .minimumScaleFactor(0.6)
            .padding(.top, 10)
            Spacer(minLength: hasIssue ? 8 : 0)
        }
    }
}

/// 가격 차트 (Swift Charts): 선 + 아래 옅은 색 채움 + 기준 가격 점선. 색은 한 가지(등락률 색).
/// 기준 가격 = 지금 가격 ÷ (1 + 등락률). 코인은 오늘 오전 9시 가격(업비트 기준), 환율은 전 영업일 환율,
/// 미국주식은 전일 종가가 되어 선 끝이 점선 위면 등락률 +, 아래면 −로 숫자·색·그림이 항상 맞는다.
struct PriceChartView: View {
    enum Axes { case none, price, full }

    let chart: PriceChart
    let change: Double?
    let scheme: String
    var axes: Axes = .none

    private var base: Double? {
        guard let change, let last = chart.points.last?.price, change > -100 else { return nil }
        return last / (1 + change / 100)
    }

    var body: some View {
        let color = Fmt.color(change, scheme: scheme)
        let prices = chart.points.map(\.price) + (base.map { [$0] } ?? [])
        let lo = prices.min() ?? 0, hi = prices.max() ?? 1
        let pad = max((hi - lo) * 0.08, hi * 0.0005)
        let domain = (lo - pad)...(hi + pad)
        Chart {
            ForEach(chart.points, id: \.date) { p in
                AreaMark(x: .value("시각", p.date),
                         yStart: .value("바닥", domain.lowerBound),
                         yEnd: .value("가격", p.price))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("시각", p.date), y: .value("가격", p.price))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if let base {
                RuleMark(y: .value("기준", base))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis(axes == .full ? .visible : .hidden)
        .chartYAxis(axes == .none ? .hidden : .visible)
        .chartXAxis {
            if axes == .full {
                AxisMarks(values: xStride) { v in
                    AxisGridLine().foregroundStyle(HomePalette.line)
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(xLabel(d)).font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if axes != .none {
                AxisMarks(position: .trailing, values: [lo, hi]) { v in
                    AxisValueLabel {
                        if let y = v.as(Double.self) {
                            Text(yLabel(y)).font(.system(size: 8)).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// x축 간격: 코인 6시간, 환율 1주, 미국주식 2시간.
    private var xStride: AxisMarkValues {
        switch chart.kind {
        case .coin: .stride(by: .hour, count: 6)
        case .fx: .stride(by: .day, count: 7)
        case .stock: .stride(by: .hour, count: 2)
        }
    }

    /// 시간은 "15시", 날짜는 "11/5".
    private func xLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if chart.kind == .fx {
            return "\(cal.component(.month, from: d))/\(cal.component(.day, from: d))"
        }
        return "\(cal.component(.hour, from: d))시"
    }

    /// y축: 코인 "9917만", 환율 "1,430.5", 미국주식 "$390.8".
    private func yLabel(_ v: Double) -> String {
        switch chart.kind {
        case .coin: Fmt.krwShort(v)
        case .fx: Fmt.grouped(v, fraction: v >= 100 ? 1 : 2)
        case .stock: "$" + Fmt.grouped(v, fraction: v >= 100 ? 1 : 2)
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
        MarketLiveActivity()
    }
}

// MARK: - 자유 구성 (홈 2×2)

struct MixWidget: Widget {
    let kind = "MixWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: MixWidgetIntent.self, provider: MixProvider()) { entry in
            MixWidgetView(entry: entry).widgetBackground(forceDark: entry.mixStyle != .plain)
        }
        .configurationDisplayName("자유 구성")
        .description("칸 3개에 코인·국내주식·미국주식·환율을 골라 담아요. 큰 위젯은 남는 줄을 앱 목록으로 채워요. 길게 눌러 \u{201C}위젯 편집\u{201D}에서 바꿀 수 있어요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// 자유 구성 한 칸: 심볼 · 등락률 / 가격.
struct MixItem: Hashable {
    var symbol: String
    var price: String
    var change: Double?
    var missing = false
    var icon: ItemIcon.Kind = .letter("")
    /// 가격 줄 후보 (넓은 것부터). 미국주식은 "$397.45 · 529,562원" → "$397.45 · 53만". 비면 [price].
    var priceVariants: [String] = []
    /// 큰 위젯 목록의 이름 줄과 가격 아래 보조 값(미국주식 원화).
    var name = ""
    var sub: String? = nil

    /// 홈 시안 목록 한 줄.
    var homeItem: HomeItem {
        HomeItem(icon: icon, symbol: symbol, name: name, price: price, listPrice: price, listSub: sub, change: change)
    }

    /// 화면 줄 수. 2×2 "줄마다 색"은 예전처럼 3칸, 그 밖에는 시안 목록 줄 수(이슈가 있으면 줄인다).
    static func rowCount(_ family: WidgetFamily, style: MixBackground, hasIssue: Bool) -> Int {
        if family == .systemSmall && style != .plain { return 3 }
        return WidgetPaging.pageSize(family, layout: .list, hasIssue: hasIssue)
    }

    /// 보여줄 항목 id. 고른 칸을 먼저, 줄이 남으면 앱 목록에서 코인·주식·환율을 섞어 채운다
    /// (5줄 2·2·1, 6줄 3·2·1, 8줄 3·3·2). 3줄이고 고른 칸이 있으면 고른 칸만.
    static func ids(picked: [String], in s: Snapshot, count: Int) -> [String] {
        if count <= 3 { return picked.isEmpty ? defaults(in: s) : picked }
        let fxs = (s.fx.map { [$0] } ?? []) + (s.fxList ?? []).filter { $0.code != s.fx?.code }
        let coins = s.coins.map { "coin:\($0.symbol)" }
        let stocks = s.stocks.map { "stock:\($0.ticker)" } + (s.krStocks ?? []).map { "kr:\($0.code)" }
        let fx = fxs.map { "fx:\($0.code)" }
        let (c, st, f) = count >= 8 ? (3, 3, 2) : (count >= 6 ? (3, 2, 1) : (2, 2, 1))
        var out = picked
        for id in Array(coins.prefix(c)) + Array(stocks.prefix(st)) + Array(fx.prefix(f)) + coins + stocks + fx
        where out.count < count && !out.contains(id) {
            out.append(id)
        }
        return out
    }

    static func resolve(_ id: String, in s: Snapshot) -> MixItem {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "", key = parts.count > 1 ? parts[1] : ""
        // 주식 가격이 없을 때: 증권사 미연결이면 연결 안내.
        let noPrice = s.settings.isStocksConnected ? "—" : "증권사 연결 필요"
        switch kind {
        case "coin":
            if let c = s.coins.first(where: { $0.symbol == key }) {
                return MixItem(symbol: c.symbol, price: c.priceShort ?? Fmt.dropWon(c.price) ?? "—", change: c.change,
                               icon: .coin(c.symbol), name: c.name)
            }
        case "kr":
            if let k = (s.krStocks ?? []).first(where: { $0.code == key }) {
                return MixItem(symbol: k.name, price: k.priceShort ?? Fmt.dropWon(k.price) ?? noPrice, change: k.change,
                               icon: .stock(id: "kr-\(k.code)", letter: k.name), name: k.code)
            }
        case "stock":
            if let st = s.stocks.first(where: { $0.ticker == key }) {
                // 원화는 달러 옆에. 앱 설정에서 원화 표시를 껐거나 원화 환율이 없으면 달러만.
                let krw = s.settings.showStockKrw && st.priceUsd != nil
                    ? [st.priceKrw, st.priceKrwShort].compactMap { $0 } : []
                return MixItem(symbol: st.ticker, price: st.priceUsd ?? noPrice, change: st.change,
                               icon: .stock(id: "us-\(st.ticker)", letter: st.ticker),
                               priceVariants: krw.map { "\(st.priceUsd!) · \($0)" },
                               name: st.name, sub: krw.first)
            }
        case "fx":
            let fxs = s.fxList ?? (s.fx.map { [$0] } ?? [])
            if let fx = fxs.first(where: { $0.code == key }) {
                return MixItem(symbol: fx.unit == 1 ? fx.code : "\(fx.unit)\(fx.code)",
                               price: Fmt.dropWon(fx.rate) ?? "—", change: fx.change,
                               icon: .flag(fx.code), name: fx.name)
            }
        default: break
        }
        return MixItem(symbol: key.isEmpty ? "—" : key, price: "앱에서 추가하세요", change: nil, missing: true,
                       icon: .letter(key))
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
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snap = entry.snapshot {
            let picked = entry.selected.compactMap { $0 }
            let count = MixItem.rowCount(family, style: entry.mixStyle, hasIssue: snap.issue != nil)
            let items = MixItem.ids(picked: picked, in: snap, count: count).map { MixItem.resolve($0, in: snap) }
            let scheme = snap.settings.colorScheme
            if items.isEmpty {
                EmptyHint(title: "자유 구성", message: "앱에서 코인·종목·환율을 추가하세요")
            } else if family != .systemSmall || entry.mixStyle == .plain {
                // 시안 목록 (2×2 기본, 4×2·4×4). 줄마다 색은 2×2에서만.
                HomeCard(title: "자유 구성", snapshot: snap, items: items.map(\.homeItem), layout: .list,
                         rowStyle: family == .systemSmall ? .plain : entry.mixStyle)
            } else if entry.mixStyle != .plain {
                // 줄마다 색: 줄 여백 때문에 제목 줄은 빼고, 갱신 시각은 맨 아래에 작게 둔다.
                VStack(alignment: .leading, spacing: 4) {
                    rows(items, scheme, entry.mixStyle)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if snap.settings.showUpdatedAt, let t = snap.updatedAt {
                            Text("최근 업데이트: \(Fmt.hm(t))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        RefreshButton()
                    }
                    .widgetAccentable()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                // 세로가 모자라면 제목 줄을 빼고 항목만 보여준다.
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetHeader(title: "자유 구성", snapshot: snap, now: entry.date)
                        rows(items, scheme, entry.mixStyle)
                    }
                    rows(items, scheme, entry.mixStyle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            EmptyHint(title: "자유 구성", message: "앱을 한 번 열면 표시돼요")
        }
    }

    private func rows(_ items: [MixItem], _ scheme: String, _ style: MixBackground) -> some View {
        let tinted = style != .plain
        return VStack(alignment: .leading, spacing: tinted ? 3 : 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                row(item, scheme)
                    // 줄마다 색: 로고·국기 색을 옅게 깔고, 글자 위치는 제목 줄과 맞춘다(바깥 -6 / 안쪽 +6).
                    .padding(.horizontal, tinted ? 6 : 0)
                    .padding(.vertical, tinted ? 3 : 0)
                    .background {
                        if tinted, let c = ItemTint.color(for: item.icon) {
                            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                            if style == .rowCard {
                                // 옅은 회색 상자 + 로고·국기 색 테두리.
                                shape.fill(Color.white.opacity(0.08))
                                    .overlay(shape.strokeBorder(c.opacity(0.9), lineWidth: 1.5))
                            } else if style == .rowFade {
                                // 로고 쪽(왼쪽)은 진하게, 오른쪽으로 갈수록 투명하게.
                                shape.fill(LinearGradient(colors: [c.opacity(0.8), c.opacity(0)],
                                                          startPoint: .leading, endPoint: .trailing))
                            } else {
                                shape.fill(c.opacity(0.55))
                            }
                        }
                    }
            }
        }
        .padding(.horizontal, tinted ? -6 : 0)
    }

    private func row(_ item: MixItem, _ scheme: String) -> some View {
                HStack(alignment: .center, spacing: 6) {
                    ItemIcon(kind: item.icon, size: 20)
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
                        let lines = item.priceVariants.isEmpty ? [item.price] : item.priceVariants
                        ViewThatFits(in: .horizontal) {
                            ForEach(lines, id: \.self) { priceLine($0) }
                            priceLine(lines.last ?? item.price).minimumScaleFactor(0.7)
                        }
                    }
                }
                .lineLimit(1)
    }

    private func priceLine(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

// MARK: - 라이브 액티비티 (잠금화면·다이내믹 아일랜드)
// 앱(Runner/AppDelegate.swift LiveActivityController)이 시작·갱신한다. 푸시를 쓰지 않으므로
// 앱이 켜져 있을 때만 값이 바뀌고, 15분 넘게 안 바뀌면 오래된 값 안내를 붙인다.

/// Runner/AppDelegate.swift의 같은 이름 struct와 이름·필드가 같아야 한다 (한쪽을 바꾸면 다른 쪽도).
struct MarketActivityAttributes: ActivityAttributes {
    struct Row: Codable, Hashable {
        /// "coin:BTC", "stock:TSLA", "fx:USD" (아이콘 고르기용)
        var id: String
        var symbol: String
        var price: String
        var change: Double?
    }

    struct ContentState: Codable, Hashable {
        var rows: [Row]
        /// "korean" | "global" (상승·하락 색)
        var scheme: String
        var updatedAt: Date
    }
}

struct MarketLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MarketActivityAttributes.self) { context in
            LiveLockView(state: context.state, stale: context.isStale)
                .padding(16)
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let first = s.rows.first
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    LiveRows(state: s)
                }
            } compactLeading: {
                Text(first?.symbol ?? "—").font(.caption2.weight(.bold))
            } compactTrailing: {
                ChangeText(pct: first?.change, scheme: s.scheme)
                    .font(.caption2.weight(.semibold)).monospacedDigit()
            } minimal: {
                Text(first.map { String($0.symbol.prefix(3)) } ?? "—").font(.caption2.weight(.bold))
            }
        }
    }
}

/// 잠금화면: 3종목 가로 + 맨 아래 갱신 시각.
struct LiveLockView: View {
    let state: MarketActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveRows(state: state)
            HStack {
                Spacer(minLength: 0)
                Text("최근 업데이트: \(Self.hms(state.updatedAt))" + (stale ? " · 앱을 열면 갱신돼요" : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func hms(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

/// 종목 칸 가로 배치: 아이콘·이름 / 가격 / 등락률.
struct LiveRows: View {
    let state: MarketActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(state.rows.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        ItemIcon(kind: Self.icon(r), size: 16)
                        Text(r.symbol).font(.caption.weight(.bold))
                            .minimumScaleFactor(0.7)
                    }
                    Text(r.price).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .minimumScaleFactor(0.6)
                    ChangeText(pct: r.change, scheme: state.scheme)
                        .font(.caption.weight(.semibold)).monospacedDigit()
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    static func icon(_ r: MarketActivityAttributes.Row) -> ItemIcon.Kind {
        let parts = r.id.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts.count > 1 ? parts[1] : r.symbol
        switch parts.first ?? "" {
        case "coin": return .coin(key)
        case "stock": return .stock(id: "us-\(key)", letter: r.symbol)
        case "kr": return .stock(id: "kr-\(key)", letter: r.symbol)
        case "fx": return .flag(key)
        default: return .letter(r.symbol)
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
// 로고 배경 4종 (미국주식 로고는 위젯이 받아 둔 파일이라 Canvas에서는 기본 배경으로 보인다).
#Preview("코인 · 홈 2×2 · 로고 배경", as: .systemSmall) { CoinWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder, background: .watermark)
    SnapshotEntry(date: .now, snapshot: .placeholder, background: .fill)
    SnapshotEntry(date: .now, snapshot: .placeholder, background: .color)
    SnapshotEntry(date: .now, snapshot: .placeholder, background: .blur)
}
#Preview("미국주식 · 홈 2×2", as: .systemSmall) { StockWidget() } timeline: { previewEntry; emptyEntry }
#Preview("환율 · 홈 2×2", as: .systemSmall) { FxWidget() } timeline: { previewEntry; emptyEntry }
#Preview("자유 구성 · 기본값", as: .systemSmall) { MixWidget() } timeline: { previewEntry; emptyEntry }
#Preview("자유 구성 · 고른 항목", as: .systemSmall) { MixWidget() } timeline: {
    SnapshotEntry(date: .now, snapshot: .placeholder, selected: ["coin:BTC", "stock:TSLA", "fx:JPY"])
    SnapshotEntry(date: .now, snapshot: .placeholder, selected: ["coin:ETH", nil, "coin:NONE"])
}
#Preview("AI 이슈 · 홈 2×2", as: .systemSmall) { IssueWidget() } timeline: { previewEntry; emptyEntry }

// 홈 시안: 한 종목 / 목록 × 이슈 있음(placeholder) / 없음. 라이트·다크는 Canvas의 설정에서 바꿔 본다.
private let noIssue: Snapshot = { var s = Snapshot.placeholder; s.issue = nil; return s }()
private let sampleChart = PriceChart(points: (0..<48).map { i in
    PriceChart.Point(date: Date().addingTimeInterval(Double(i - 47) * 1800),
                     price: 97_500_000 + 900_000 * sin(Double(i) / 5) + Double(i) * 30_000)
})
private let single = SnapshotEntry(date: .now, snapshot: .placeholder, layout: .single, pagingId: "preview",
                                   chart: sampleChart)
private let singleNoIssue = SnapshotEntry(date: .now, snapshot: noIssue, layout: .single, pagingId: "preview",
                                          chart: sampleChart)
private let list = SnapshotEntry(date: .now, snapshot: .placeholder, layout: .list, pagingId: "preview")
private let listNoIssue = SnapshotEntry(date: .now, snapshot: noIssue, layout: .list)
#Preview("코인 · 홈 2×2 시안", as: .systemSmall) { CoinWidget() } timeline: { single; singleNoIssue; list; listNoIssue }
#Preview("코인 · 홈 4×2", as: .systemMedium) { CoinWidget() } timeline: { single; singleNoIssue; list; listNoIssue; emptyEntry }
#Preview("코인 · 홈 4×4", as: .systemLarge) { CoinWidget() } timeline: { single; singleNoIssue; list; listNoIssue }
#Preview("미국주식 · 홈 4×2", as: .systemMedium) { StockWidget() } timeline: { single; list; emptyEntry }
#Preview("미국주식 · 홈 4×4", as: .systemLarge) { StockWidget() } timeline: { single; list }
#Preview("환율 · 홈 4×2", as: .systemMedium) { FxWidget() } timeline: { single; list; emptyEntry }
#Preview("환율 · 홈 4×4", as: .systemLarge) { FxWidget() } timeline: { single; listNoIssue }
#Preview("자유 구성 · 홈 4×2", as: .systemMedium) { MixWidget() } timeline: { previewEntry; listNoIssue }
#Preview("자유 구성 · 홈 4×4", as: .systemLarge) { MixWidget() } timeline: { previewEntry; listNoIssue }

#endif
