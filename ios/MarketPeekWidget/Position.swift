// 코인·미국주식 위젯의 "위젯 편집" 설정: 보여줄 종목을 이름으로 고른다(공통), 코인은 표시 정보도 고른다.
// 홈 화면 2×2에서는 배경(종목 로고)도 고른다.
import AppIntents
import WidgetKit

/// 단일 종목 홈 위젯(2×2)의 배경. 그리는 방법은 Shared.swift `LogoBackdrop`.
/// 잠금화면은 iOS가 단색으로 그려서 적용하지 않는다.
enum LogoBackground: String, AppEnum {
    case plain, watermark, fill, color, blur

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "배경"
    static let caseDisplayRepresentations: [LogoBackground: DisplayRepresentation] = [
        .plain: "기본",
        .watermark: "로고 크게",
        .fill: "로고 꽉 채움",
        .color: "로고 색",
        .blur: "로고 블러",
    ]
}

/// 홈 위젯 모양. 한 종목은 다음 버튼이 다음 종목으로, 목록은 다음 묶음으로 넘긴다(Shared.swift `WidgetPaging`).
/// "크기에 맞게"는 2×2는 한 종목, 4×2·4×4는 목록.
enum HomeLayout: String, AppEnum {
    case auto, single, list

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "모양"
    static let caseDisplayRepresentations: [HomeLayout: DisplayRepresentation] = [
        .auto: "크기에 맞게",
        .single: "한 종목",
        .list: "목록",
    ]

    func resolved(for family: WidgetFamily) -> HomeLayout {
        guard self == .auto else { return self }
        return family == .systemMedium || family == .systemLarge ? .list : .single
    }
}

// MARK: - 종목 고르기 (이름으로)
// 후보는 앱이 써둔 스냅샷의 홈 목록(앞 6개, Dart AppState.maxWidgetItems)이다.
// 고른 종목이 목록에서 몇 번째인지를 offset으로 바꿔 쓴다. 잠금화면 사각형은 그 종목부터 여러 줄을 보여준다.
// 고른 종목이 목록에서 빠졌거나 아직 안 골랐으면 첫 종목.

struct StockPick: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "종목"
    static let defaultQuery = StockPickQuery()

    /// 티커 ("TSLA")
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct StockPickQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [StockPick] {
        let all = Self.all()
        return identifiers.map { id in all.first { $0.id == id } ?? StockPick(id: id, name: id) }
    }

    func suggestedEntities() async throws -> [StockPick] { Self.all() }

    static func all() -> [StockPick] {
        (Snapshot.load()?.stocks ?? []).map { StockPick(id: $0.ticker, name: $0.name) }
    }
}

struct CoinPick: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "코인"
    static let defaultQuery = CoinPickQuery()

    /// 심볼 ("BTC")
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct CoinPickQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CoinPick] {
        let all = Self.all()
        return identifiers.map { id in all.first { $0.id == id } ?? CoinPick(id: id, name: id) }
    }

    func suggestedEntities() async throws -> [CoinPick] { Self.all() }

    static func all() -> [CoinPick] {
        (Snapshot.load()?.coins ?? []).map { CoinPick(id: $0.symbol, name: $0.name) }
    }
}

/// 고른 id가 목록에서 몇 번째인지 (없으면 0 = 첫 종목).
private func listOffset(of id: String?, in ids: [String]) -> Int {
    id.flatMap { ids.firstIndex(of: $0) } ?? 0
}

struct ListPositionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "미국주식 위젯"
    static let description = IntentDescription("보여줄 종목, 홈 화면 모양과 배경을 골라요. 배경은 홈 화면 한 종목 모양에만 적용돼요.")

    @Parameter(title: "종목 선택")
    var stock: StockPick?

    @Parameter(title: "모양", default: .auto)
    var layout: HomeLayout

    @Parameter(title: "배경 선택", default: .plain)
    var background: LogoBackground

    init() {}

    var offset: Int {
        listOffset(of: stock?.id, in: (Snapshot.load()?.stocks ?? []).map(\.ticker))
    }
}

struct PositionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func snapshot(for configuration: ListPositionIntent, in context: Context) async -> SnapshotEntry {
        let layout = configuration.layout.resolved(for: context.family)
        return .current(isPreview: context.isPreview, offset: configuration.offset,
                        background: homeBackground(configuration.background, layout: layout), layout: layout)
    }

    func timeline(for configuration: ListPositionIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let family = context.family
        let p = WidgetPaging.plan(kind: "StockWidget", family: family, layout: configuration.layout,
                                  baseId: configuration.stock?.id ?? "", base: configuration.offset,
                                  snapshot: Snapshot.load(), count: { $0.stocks.count })
        // 홈 화면만 로고를 보여주므로 그때만, 화면에 보일 수 있는 종목 것만 받는다.
        return await SnapshotEntry.timeline(parts: { _ in [.stocks] }, markets: { _ in [.us] },
                                            offset: p.offset,
                                            background: homeBackground(configuration.background, layout: p.layout),
                                            layout: p.layout, pagingId: p.pagingId,
                                            withIssue: WidgetPaging.isHome(family),
                                            logos: { snap in
            guard WidgetPaging.isHome(family) else { return [] }
            return WidgetPaging.window(snap.stocks, start: p.offset,
                                       size: WidgetPaging.pageSize(family, layout: p.layout, hasIssue: false))
                .map { "stock:\($0.ticker)" }
        })
    }
}

// MARK: - 환율 위젯 편집: 모양

struct FxWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "환율 위젯"
    static let description = IntentDescription("홈 화면 모양과 배경을 골라요. 통화는 앱에서 고르고, › 버튼으로 다음 통화를 봐요. 배경은 한 종목 모양에만 적용돼요.")

    @Parameter(title: "모양", default: .auto)
    var layout: HomeLayout

    @Parameter(title: "배경 선택", default: .plain)
    var background: LogoBackground

    init() {}
}

/// 환율: 앱에서 고른 통화(fxList) 중 대표 통화(fx)부터, 다음 버튼을 누른 만큼 넘긴다.
struct FxProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func snapshot(for configuration: FxWidgetIntent, in context: Context) async -> SnapshotEntry {
        let layout = configuration.layout.resolved(for: context.family)
        let entry = SnapshotEntry.current(isPreview: context.isPreview,
                                          background: homeBackground(configuration.background, layout: layout),
                                          layout: layout)
        var e = entry
        e.offset = Self.base(entry.snapshot)
        return e
    }

    func timeline(for configuration: FxWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let snap = Snapshot.load()
        let p = WidgetPaging.plan(kind: "FxWidget", family: context.family, layout: configuration.layout,
                                  baseId: snap?.fx?.code ?? "", base: Self.base(snap),
                                  snapshot: snap, count: { $0.fxList?.count ?? 0 })
        return await SnapshotEntry.timeline(parts: { _ in [.fx] }, offset: p.offset,
                                            background: homeBackground(configuration.background, layout: p.layout),
                                            layout: p.layout,
                                            pagingId: p.pagingId, withIssue: WidgetPaging.isHome(context.family),
                                            chart: WidgetPaging.isHome(context.family) && p.layout == .single
                                                ? { snap in
                                                    // 화면에 보이는 통화 하나의 30영업일 차트만 받는다.
                                                    let codes = (snap.fxList ?? []).map(\.code)
                                                    guard let code = codes.isEmpty ? snap.fx?.code
                                                            : codes[p.offset % codes.count] else { return nil }
                                                    return await LiveQuotes.fxChart(code, base: snap.settings.apiBaseUrl,
                                                                                    preferCache: WidgetCache.recentlyNavigated)
                                                } : nil)
    }

    static func base(_ snap: Snapshot?) -> Int {
        let codes = (snap?.fxList ?? []).map(\.code)
        return snap?.fx.flatMap { codes.firstIndex(of: $0.code) } ?? 0
    }
}

// MARK: - 코인 위젯 편집: 표시 순서 + 표시 정보

enum CoinDisplayStyle: String, AppEnum {
    case prices, changeOnly

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "표시 정보"
    static let caseDisplayRepresentations: [CoinDisplayStyle: DisplayRepresentation] = [
        .prices: "가격·등락률",
        .changeOnly: "이름·등락률 2개",
    ]
}

struct CoinWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "코인 위젯"
    static let description = IntentDescription("보여줄 코인과 정보, 홈 화면 모양과 배경을 골라요. 표시 정보는 잠금화면 사각형에만, 배경은 홈 화면 한 종목 모양에만 적용돼요.")

    @Parameter(title: "코인 선택")
    var coin: CoinPick?

    @Parameter(title: "모양", default: .auto)
    var layout: HomeLayout

    @Parameter(title: "표시 정보", default: .prices)
    var style: CoinDisplayStyle

    @Parameter(title: "배경 선택", default: .plain)
    var background: LogoBackground

    init() {}

    var offset: Int {
        listOffset(of: coin?.id, in: (Snapshot.load()?.coins ?? []).map(\.symbol))
    }
}

struct CoinProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func snapshot(for configuration: CoinWidgetIntent, in context: Context) async -> SnapshotEntry {
        let layout = configuration.layout.resolved(for: context.family)
        return .current(isPreview: context.isPreview, offset: configuration.offset,
                        changeOnly: configuration.style == .changeOnly,
                        background: homeBackground(configuration.background, layout: layout), layout: layout)
    }

    func timeline(for configuration: CoinWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let p = WidgetPaging.plan(kind: "CoinWidget", family: context.family, layout: configuration.layout,
                                  baseId: configuration.coin?.id ?? "", base: configuration.offset,
                                  snapshot: Snapshot.load(), count: { $0.coins.count })
        return await SnapshotEntry.timeline(parts: { _ in [.coins] }, offset: p.offset,
                                            changeOnly: configuration.style == .changeOnly,
                                            background: homeBackground(configuration.background, layout: p.layout),
                                            layout: p.layout, pagingId: p.pagingId,
                                            withIssue: WidgetPaging.isHome(context.family),
                                            chart: WidgetPaging.isHome(context.family) && p.layout == .single
                                                ? { snap in
                                                    // 화면에 보이는 코인 하나의 24시간 차트만 받는다.
                                                    guard snap.coins.indices.contains(p.offset) else { return nil }
                                                    return await LiveQuotes.coinChart(snap.coins[p.offset].symbol,
                                                                                  preferCache: WidgetCache.recentlyNavigated)
                                                } : nil)
    }
}

// MARK: - 자유 구성 위젯 편집: 칸 3개마다 코인·미국주식·환율 중 하나

/// 위젯 편집에서 고를 수 있는 항목. 후보는 앱이 써둔 스냅샷(앱에서 고른 코인·종목·통화)에서 온다.
struct QuoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "항목"
    static let defaultQuery = QuoteEntityQuery()

    /// "coin:BTC", "kr:005930", "stock:NVDA", "fx:USD"
    let id: String
    let title: String
    let kindLabel: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(kindLabel)")
    }
}

struct QuoteEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [QuoteEntity] {
        let all = Self.all()
        // 앱 목록에서 빠진 항목도 선택은 유지한다 (위젯에는 "앱에서 추가하세요"로 보임).
        return identifiers.map { id in
            all.first { $0.id == id }
                ?? QuoteEntity(id: id, title: String(id.split(separator: ":").last ?? ""), kindLabel: "목록에 없음")
        }
    }

    func suggestedEntities() async throws -> [QuoteEntity] { Self.all() }

    static func all() -> [QuoteEntity] {
        guard let s = Snapshot.load() else { return [] }
        let fxs = s.fxList ?? (s.fx.map { [$0] } ?? [])
        return s.coins.map { QuoteEntity(id: "coin:\($0.symbol)", title: "\($0.symbol) · \($0.name)", kindLabel: "코인") }
            + (s.krStocks ?? []).map { QuoteEntity(id: "kr:\($0.code)", title: "\($0.name) · \($0.code)", kindLabel: "국내주식") }
            + s.stocks.map { QuoteEntity(id: "stock:\($0.ticker)", title: "\($0.ticker) · \($0.name)", kindLabel: "미국주식") }
            + fxs.map { QuoteEntity(id: "fx:\($0.code)", title: "\($0.code) · \($0.name)", kindLabel: "환율") }
    }
}

/// 자유 구성 위젯 배경. 줄마다 그 항목의 로고 색(코인·주식) 또는 통화 대표 색(환율)을 깐다.
/// 색은 Shared.swift `ItemTint`, 그리기는 Widgets.swift `MixWidgetView`.
enum MixBackground: String, AppEnum {
    case plain, rowTint, rowFade, rowCard

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "배경"
    static let caseDisplayRepresentations: [MixBackground: DisplayRepresentation] = [
        .plain: "기본",
        .rowTint: "줄마다 색",
        .rowFade: "줄마다 색 (옅어지게)",
        .rowCard: "줄마다 카드",
    ]
}

struct MixWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "자유 구성"
    static let description = IntentDescription("칸마다 코인·국내주식·미국주식·환율 중 보여줄 항목을 골라요. 하나도 안 고르면 첫 코인·첫 종목·환율이 보여요.")

    @Parameter(title: "배경 선택", default: .plain)
    var background: MixBackground

    @Parameter(title: "첫 번째 칸")
    var slot1: QuoteEntity?

    @Parameter(title: "두 번째 칸")
    var slot2: QuoteEntity?

    @Parameter(title: "세 번째 칸")
    var slot3: QuoteEntity?

    init() {}

    var selected: [String?] { [slot1?.id, slot2?.id, slot3?.id] }
}

struct MixProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func snapshot(for configuration: MixWidgetIntent, in context: Context) async -> SnapshotEntry {
        .current(isPreview: context.isPreview, selected: configuration.selected,
                 mixStyle: configuration.background)
    }

    func timeline(for configuration: MixWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let picked = configuration.selected.compactMap { $0 }
        let family = context.family, style = configuration.background
        // 화면에 보일 수 있는 항목(이슈 없을 때 줄 수 기준)의 묶음과 로고만 받는다.
        let ids = { (snap: Snapshot) in
            MixItem.ids(picked: picked, in: snap, count: MixItem.rowCount(family, style: style, hasIssue: false))
        }
        return await SnapshotEntry.timeline(parts: { snap in
            // 칸에 실제로 보이는 항목의 묶음만 받는다 (안 고르면 기본 항목).
            Set(ids(snap).compactMap(QuotePart.of(itemId:)))
        }, markets: { snap in
            Set(ids(snap).compactMap { id -> StockMarket? in
                id.hasPrefix("kr:") ? .kr : (id.hasPrefix("stock:") ? .us : nil)
            })
        }, selected: configuration.selected, mixStyle: configuration.background,
        withIssue: true, logos: ids)
    }
}
