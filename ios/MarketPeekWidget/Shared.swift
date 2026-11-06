import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    /// 이 위젯이 보여줄 첫 종목의 위치(0부터). "위젯 편집"의 표시 순서에서 온다.
    var offset: Int = 0
    /// 코인 사각형(2칸)을 가격 없이 "이름·등락률 2개"로 보여줄지. 코인 위젯 편집에서 고른다.
    var changeOnly: Bool = false
}

extension SnapshotEntry {
    /// 미국장 상태는 시각에 따라 바뀌므로 엔트리마다 다시 계산되게 15분 간격 엔트리를 만든다.
    static func timeline(offset: Int = 0, changeOnly: Bool = false) -> Timeline<SnapshotEntry> {
        let snap = Snapshot.load()
        let now = Date()
        let entries = (0..<4).map { i in
            SnapshotEntry(date: now.addingTimeInterval(Double(i) * 15 * 60), snapshot: snap,
                          offset: offset, changeOnly: changeOnly)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(60 * 60)))
    }

    static func current(isPreview: Bool, offset: Int = 0, changeOnly: Bool = false) -> SnapshotEntry {
        let snap = isPreview ? (Snapshot.load() ?? .placeholder) : Snapshot.load()
        return SnapshotEntry(date: .now, snapshot: snap, offset: offset, changeOnly: changeOnly)
    }
}

/// 4종 위젯이 공유하는 타임라인 공급자.
///
/// 지금은 앱이 App Group에 써둔 스냅샷을 읽기만 한다. 서버(4주차)가 붙으면
/// 여기서 직접 받아와 앱을 열지 않아도 값이 바뀌게 한다.
/// iOS가 실제 갱신 시점을 결정하므로 "15분마다" 같은 보장 표현은 쓰지 않는다.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(.current(isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(SnapshotEntry.timeline())
    }
}

// MARK: - Formatting

enum Fmt {
    /// 잠금화면 위젯은 보통 단색(vibrant)으로 그려져 색이 사라지므로 +/- 부호를 항상 붙인다.
    /// (▲▼는 폭이 넓어 가격이 잘려서 부호로 바꿨다.)
    static func change(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        let sign = pct > 0 ? "+" : (pct < 0 ? "-" : "")
        return "\(sign)\(String(format: "%.2f", abs(pct)))%"
    }

    /// 작은 칸용: 소수 첫째 자리. "+2.5%"
    static func changeShort(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        let sign = pct > 0 ? "+" : (pct < 0 ? "-" : "")
        return "\(sign)\(String(format: "%.1f", abs(pct)))%"
    }

    static func dropWon(_ s: String?) -> String? {
        s.map { $0.hasSuffix("원") ? String($0.dropLast()) : $0 }
    }

    static func hm(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func color(_ pct: Double?, scheme: String) -> Color {
        guard let pct, pct != 0 else { return .secondary }
        let up = pct > 0
        if scheme == "global" {
            return up ? Color(red: 0.24, green: 0.75, blue: 0.48) : Color(red: 0.94, green: 0.38, blue: 0.43)
        }
        return up ? Color(red: 0.94, green: 0.38, blue: 0.43) : Color(red: 0.36, green: 0.55, blue: 0.94)
    }
}

// MARK: - Views

/// 여러 종목을 한 줄씩 보여주는 표. 모든 행이 같은 열 폭·글자 크기를 쓴다.
struct PriceRow: Hashable {
    var symbol: String
    var price: String
    var extra: String?  // 미국주식 원화 등 보조 값
    var change: Double?
}

/// 가격을 절대 "…"로 자르지 않는다. 주어진 변형(variants)을 넓은 것부터 시도해
/// 한 줄에 들어가는 첫 번째를 쓰고, 그래도 안 되면 마지막 변형을 통째로 축소한다.
struct PriceGrid: View {
    let variants: [[PriceRow]]
    let scheme: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(variants.indices, id: \.self) { i in
                grid(variants[i])
            }
            grid(variants.last ?? []).minimumScaleFactor(0.6)
        }
    }

    private func grid(_ rows: [PriceRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 5, verticalSpacing: 0) {
            ForEach(rows, id: \.self) { r in
                GridRow {
                    Text(r.symbol).font(.caption.weight(.bold))
                    Text(r.price).font(.caption).monospacedDigit()
                        .trend(r.change)
                        .gridColumnAlignment(.trailing)
                    if let extra = r.extra {
                        Text(extra).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            .gridColumnAlignment(.trailing)
                    }
                    ChangeText(pct: r.change, scheme: scheme).font(.caption2).monospacedDigit()
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        .lineLimit(1)
    }
}

/// 등락률 텍스트. 풀컬러로 그려지는 곳(StandBy 등)에서만 색이 보인다.
/// 잠금화면(단색)에서는 [TrendEmphasis]의 굵기·밝기로 오르내림을 구분한다.
struct ChangeText: View {
    let pct: Double?
    let scheme: String
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(Fmt.change(pct))
            .foregroundStyle(Self.style(pct, scheme: scheme, renderingMode: renderingMode))
            .trend(pct)
    }

    static func style(_ pct: Double?, scheme: String, renderingMode: WidgetRenderingMode) -> Color {
        renderingMode == .fullColor ? Fmt.color(pct, scheme: scheme) : .primary
    }
}

/// 잠금화면 위젯은 단색이라 빨강·파랑을 못 쓴다. 대신 숫자(가격·등락률)를
/// 상승은 굵고 진하게, 하락은 가늘고 흐리게, 보합·값 없음은 그 중간으로 그린다.
/// 굵기는 어디서나, 밝기는 단색 렌더링일 때만 바꾼다(풀컬러에서는 색이 그 역할을 한다).
struct TrendEmphasis: ViewModifier {
    let pct: Double?
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content
            .fontWeight(weight)
            .opacity(renderingMode == .fullColor ? 1 : opacity)
    }

    private var weight: Font.Weight {
        guard let pct, pct != 0 else { return .medium }
        return pct > 0 ? .heavy : .regular
    }

    private var opacity: Double {
        guard let pct, pct != 0 else { return 0.75 }
        return pct > 0 ? 1 : 0.5
    }
}

extension View {
    func trend(_ pct: Double?) -> some View { modifier(TrendEmphasis(pct: pct)) }
}

/// 위젯 공통 헤더: "코인 ········ 15:30"
struct WidgetHeader: View {
    let title: String
    let snapshot: Snapshot

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption2.weight(.semibold))
            Spacer(minLength: 0)
            if snapshot.settings.showUpdatedAt, let t = snapshot.updatedAt {
                Text(Fmt.hm(t)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .widgetAccentable()
    }
}

/// 제목 줄 + 종목 표. 3종목처럼 세로가 모자라면 제목 줄을 빼고 종목만 보여준다.
/// (ViewThatFits가 위에서부터 들어가는 첫 번째 레이아웃을 고른다.)
struct HeaderedRows<Header: View, Rows: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 0) {
                header()
                rows()
            }
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 원형 위젯: 심볼 + 등락률 두 줄.
struct CircularQuote: View {
    let symbol: String
    let change: Double?
    let scheme: String

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(symbol).font(.system(size: 12, weight: .bold))
                ChangeText(pct: change, scheme: scheme).font(.system(size: 10))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 3)
        }
    }
}

/// 작은 칸(원형 자리) 1칸에 코인 2개를 사각형으로: 한 줄에 심볼 + 등락률.
/// 칸 크기가 작아 가격과 한글 이름은 빼고, 원 대신 둥근 사각형 배경을 그린다.
struct SmallSquareQuotes: View {
    struct Item: Hashable {
        var symbol: String
        var change: Double?
    }

    let items: [Item]
    let scheme: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.18))
            // 작은 칸은 원 모양으로 잘리므로 두 줄을 가운데(가장 넓은 곳)로 모은다.
            // 등락률은 소수 첫째 자리까지, 자리가 모자라면 심볼부터 줄인다.
            VStack(spacing: 1) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 2) {
                        Text(item.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .minimumScaleFactor(0.5)
                        Spacer(minLength: 0)
                        Text(Fmt.changeShort(item.change))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(ChangeText.style(item.change, scheme: scheme, renderingMode: renderingMode))
                            .trend(item.change)
                            .minimumScaleFactor(0.6)
                            .layoutPriority(1)
                    }
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 7)
        }
    }

    @Environment(\.widgetRenderingMode) private var renderingMode
}

/// 코인 사각형(가로 2칸)의 "이름·등락률" 모드: 코인 2개를 한 줄씩, 가격 없이 크게.
struct ChangeOnlyRows: View {
    let items: [SmallSquareQuotes.Item]
    let scheme: String

    var body: some View {
        VStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Text(item.symbol).font(.system(size: 17, weight: .bold))
                    Spacer(minLength: 0)
                    ChangeText(pct: item.change, scheme: scheme)
                        .font(.system(size: 16))
                        .monospacedDigit()
                        .layoutPriority(1)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 앱에서 아직 설정하지 않았을 때.
struct EmptyHint: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold))
            Text(message).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// iOS 17+는 containerBackground가 필수. 잠금화면은 시스템 배경을 쓴다.
    /// [squareSmall]이면 작은 칸(accessoryCircular)에서 원형 배경을 깔지 않는다
    /// (코인 작은 사각형 위젯이 직접 사각형 배경을 그린다).
    func widgetBackground(squareSmall: Bool = false) -> some View {
        modifier(WidgetBackground(squareSmall: squareSmall))
    }
}

private struct WidgetBackground: ViewModifier {
    let squareSmall: Bool
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if squareSmall && family == .accessoryCircular {
                Color.clear
            } else {
                AccessoryWidgetBackground()
            }
        }
    }
}
