// 코인·미국주식 위젯의 "위젯 편집" 설정: 몇 번째 종목부터 보여줄지(공통), 코인은 표시 정보도 고른다.
import AppIntents
import WidgetKit

/// 표시 순서. 스냅샷에는 홈 목록 앞 6개까지 담긴다(Dart AppState.maxWidgetItems).
enum ListPosition: Int, AppEnum {
    case p1 = 1, p2, p3, p4, p5, p6

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "표시 순서"
    static let caseDisplayRepresentations: [ListPosition: DisplayRepresentation] = [
        .p1: "1번째부터", .p2: "2번째부터", .p3: "3번째부터",
        .p4: "4번째부터", .p5: "5번째부터", .p6: "6번째부터",
    ]
}

struct ListPositionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "표시 순서"
    static let description = IntentDescription("홈 목록에서 몇 번째 종목부터 이 위젯에 보여줄지 골라요.")

    @Parameter(title: "표시 순서", default: .p1)
    var start: ListPosition

    init() {}
    init(start: ListPosition) { self.start = start }
}

struct PositionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func snapshot(for configuration: ListPositionIntent, in context: Context) async -> SnapshotEntry {
        .current(isPreview: context.isPreview, offset: configuration.start.rawValue - 1)
    }

    func timeline(for configuration: ListPositionIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        SnapshotEntry.timeline(offset: configuration.start.rawValue - 1)
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
    static let description = IntentDescription("몇 번째 코인부터, 어떤 정보를 보여줄지 골라요. 표시 정보는 사각형 위젯에만 적용돼요.")

    @Parameter(title: "표시 순서", default: .p1)
    var start: ListPosition

    @Parameter(title: "표시 정보", default: .prices)
    var style: CoinDisplayStyle

    init() {}
}

struct CoinProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func snapshot(for configuration: CoinWidgetIntent, in context: Context) async -> SnapshotEntry {
        .current(isPreview: context.isPreview, offset: configuration.start.rawValue - 1,
                 changeOnly: configuration.style == .changeOnly)
    }

    func timeline(for configuration: CoinWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        SnapshotEntry.timeline(offset: configuration.start.rawValue - 1,
                               changeOnly: configuration.style == .changeOnly)
    }
}

// MARK: - 자유 구성 위젯 편집: 칸 3개마다 코인·미국주식·환율 중 하나

/// 위젯 편집에서 고를 수 있는 항목. 후보는 앱이 써둔 스냅샷(앱에서 고른 코인·종목·통화)에서 온다.
struct QuoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "항목"
    static let defaultQuery = QuoteEntityQuery()

    /// "coin:BTC", "stock:NVDA", "fx:USD"
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
            + s.stocks.map { QuoteEntity(id: "stock:\($0.ticker)", title: "\($0.ticker) · \($0.name)", kindLabel: "미국주식") }
            + fxs.map { QuoteEntity(id: "fx:\($0.code)", title: "\($0.code) · \($0.name)", kindLabel: "환율") }
    }
}

struct MixWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "자유 구성"
    static let description = IntentDescription("칸마다 코인·미국주식·환율 중 보여줄 항목을 골라요. 하나도 안 고르면 첫 코인·첫 종목·환율이 보여요.")

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
        .current(isPreview: context.isPreview, selected: configuration.selected)
    }

    func timeline(for configuration: MixWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        SnapshotEntry.timeline(selected: configuration.selected)
    }
}
