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
