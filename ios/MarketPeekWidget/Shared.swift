import AppIntents
import SwiftUI
import WidgetKit
import CoreImage.CIFilterBuiltins

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    /// 이 위젯이 보여줄 첫 종목의 위치(0부터). "위젯 편집"에서 고른 종목의 목록 위치.
    var offset: Int = 0
    /// 코인 사각형(2칸)을 가격 없이 "이름·등락률 2개"로 보여줄지. 코인 위젯 편집에서 고른다.
    var changeOnly: Bool = false
    /// 자유 구성 위젯의 칸별 항목 id ("coin:BTC", "stock:NVDA", "fx:USD"). 위젯 편집에서 고른다.
    var selected: [String?] = []
    /// 단일 종목 홈 위젯(2×2)의 배경. 코인·미국주식 위젯 편집에서 고른다.
    var background: LogoBackground = .plain
    /// 자유 구성 위젯 배경. 자유 구성 위젯 편집에서 고른다.
    var mixStyle: MixBackground = .plain
}

extension SnapshotEntry {
    /// 앱이 써둔 스냅샷(종목 목록·설정)을 읽고, [parts] 시세를 직접 받아 덮어쓴 뒤 엔트리를 만든다.
    /// 엔트리는 시세를 다시 받지 않고 같은 값을 시각만 바꿔 그린다. 처음 1시간은 1분 간격이라
    /// "N분 전"·미국장 상태가 저절로 바뀌고, 그 뒤 6시간까지는 10분 간격이다.
    /// 다시 받아 달라는 시점은 [ReloadPlan]이 정하지만, 실제로 언제 부를지는 iOS가 정한다(보장 아님).
    /// [markets]: 이 위젯이 보여주는 주식 시장. 장중인지에 따라 다시 받을 시점이 달라진다.
    static func timeline(parts: (Snapshot) -> Set<QuotePart>,
                         markets: (Snapshot) -> Set<StockMarket> = { _ in [.us, .kr] },
                         offset: Int = 0, changeOnly: Bool = false,
                         selected: [String?] = [], background: LogoBackground = .plain,
                         mixStyle: MixBackground = .plain,
                         logos: (Snapshot) -> [String] = { _ in [] }) async -> Timeline<SnapshotEntry> {
        var snap = Snapshot.load()
        var wanted: Set<QuotePart> = []
        var stockMarkets: Set<StockMarket> = []
        if let s = snap {
            wanted = parts(s)
            stockMarkets = markets(s)
            // 주식 로고(자유 구성)는 시세와 동시에 받는다. 둘 다 끝난 뒤 엔트리를 만든다.
            let logoIds = logos(s)
            async let logoDone: Void = StockLogos.prefetch(itemIds: logoIds)
            snap = await LiveQuotes.refresh(s, parts: wanted)
            await logoDone
        }
        let now = Date()
        let minutes = Array(0..<60) + Array(stride(from: 60, to: 360, by: 10))
        let entries = minutes.map { m in
            SnapshotEntry(date: now.addingTimeInterval(Double(m) * 60), snapshot: snap,
                          offset: offset, changeOnly: changeOnly, selected: selected, background: background,
                          mixStyle: mixStyle)
        }
        let after = ReloadPlan.interval(parts: wanted, markets: stockMarkets, now: now)
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(after)))
    }

    static func current(isPreview: Bool, offset: Int = 0, changeOnly: Bool = false,
                        selected: [String?] = [], background: LogoBackground = .plain,
                        mixStyle: MixBackground = .plain) -> SnapshotEntry {
        let snap = isPreview ? (Snapshot.load() ?? .placeholder) : Snapshot.load()
        return SnapshotEntry(date: .now, snapshot: snap, offset: offset, changeOnly: changeOnly,
                             selected: selected, background: background, mixStyle: mixStyle)
    }
}

/// 위젯 편집이 없는 위젯(환율·AI 이슈)의 타임라인 공급자. [part] 시세를 직접 받아온다.
/// iOS가 실제 갱신 시점을 결정하므로 "15분마다" 같은 보장 표현은 쓰지 않는다.
struct SnapshotProvider: TimelineProvider {
    let part: QuotePart

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(.current(isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let part = part
        Task { completion(await SnapshotEntry.timeline(parts: { _ in [part] })) }
    }
}

/// 다음 타임라인을 언제 다시 받아 달라고 요청할지. iOS는 위젯마다 하루 갱신 횟수를 제한하므로
/// 값이 거의 안 바뀌는 때(장 마감, 환율 고시 사이, 하루 1번인 AI 이슈)에는 덜 요청해 장중에 횟수를 남긴다.
/// 실제로 언제 부를지는 iOS가 정한다.
enum ReloadPlan {
    static let often: TimeInterval = 15 * 60
    static let rarely: TimeInterval = 60 * 60
    static let issue: TimeInterval = 2 * 60 * 60

    static func interval(parts: Set<QuotePart>, markets: Set<StockMarket>, now: Date) -> TimeInterval {
        // 앱 스냅샷이 아직 없으면(parts 비어 있음) 앱을 연 뒤 빨리 보이도록 자주.
        if parts.isEmpty || parts.contains(.coins) { return often }  // 코인은 24시간 거래
        var best = parts.contains(.fx) ? rarely : issue  // 환율: 서버가 1시간마다 갱신
        if parts.contains(.stocks) { best = min(best, stockInterval(markets, now: now)) }
        return best
    }

    /// 장중이면 15분. 닫혀 있으면 1시간이되, 그 안에 장이 열리면 열린 직후로 당긴다(15분 단위).
    static func stockInterval(_ markets: Set<StockMarket>, now: Date) -> TimeInterval {
        for step in 0...3 {
            let t = Double(step) * often
            if markets.contains(where: { MarketHours.isOpen($0, at: now.addingTimeInterval(t)) }) {
                return max(t, often)
            }
        }
        return rarely
    }
}

/// 홈 화면 위젯의 새로고침 버튼(↻). 버튼을 누르면 iOS가 그 위젯의 타임라인을 다시 만들어
/// 앱을 열지 않고 시세를 새로 받는다. 할 일은 없고, 다시 만드는 건 WidgetKit이 한다.
/// 60초 안에 다시 누르면 같은 요청을 재사용(LiveQuotes Reuse)해 값이 그대로일 수 있다.
struct RefreshQuotesIntent: AppIntent {
    static let title: LocalizedStringResource = "시세 새로고침"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult { .result() }
}

/// 홈 화면 위젯의 새로고침 버튼 ↻ (제목 줄, 자유 구성 아래 줄).
struct RefreshButton: View {
    var body: some View {
        Button(intent: RefreshQuotesIntent()) {
            Image(systemName: "arrow.clockwise").font(.caption2.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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

    /// 마지막 갱신이 [now] 기준 얼마 전인지: "방금", "12분 전", "3시간 전", "2일 전".
    /// 엔트리 시각을 [now]로 넘기므로 위젯이 시세를 다시 받지 않아도 엔트리마다 늘어난다.
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분 전" }
        if minutes < 24 * 60 { return "\(minutes / 60)시간 전" }
        return "\(minutes / (24 * 60))일 전"
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

/// 위젯 공통 헤더.
/// - 홈 화면: 제목 없이 오른쪽에 "최근 업데이트: 15:30 ↻" (↻ 새로고침 버튼)
/// - 잠금화면: "코인 ········ 3분 전"
struct WidgetHeader: View {
    let title: String
    let snapshot: Snapshot
    /// 엔트리 시각. 잠금화면의 "N분 전"을 이 시각 기준으로 계산한다.
    let now: Date
    @Environment(\.widgetFamily) private var family

    private var isHome: Bool { family == .systemSmall || family == .systemMedium || family == .systemLarge }

    var body: some View {
        HStack(spacing: 4) {
            if !isHome {
                Text(title).font(.caption2.weight(.semibold))
            }
            Spacer(minLength: 0)
            if snapshot.settings.showUpdatedAt, let t = snapshot.updatedAt {
                Text(isHome ? "최근 업데이트: \(Fmt.hm(t))" : Fmt.ago(t, now: now))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            // 잠금화면 위젯은 누르면 앱이 열리므로 홈 화면에만 단다.
            if isHome {
                RefreshButton()
            }
        }
        .lineLimit(1)
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

/// 작은 칸(원형 자리) 1칸에 코인 1개를 사각형으로: 위에 심볼, 아래에 등락률.
/// 칸 크기가 작아 가격과 한글 이름은 빼고, 원 대신 둥근 사각형 배경을 그린다.
struct SmallSquareQuote: View {
    struct Item: Hashable {
        var symbol: String
        var change: Double?
    }

    let item: Item
    let scheme: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.18))
            // 등락률은 소수 첫째 자리까지, 자리가 모자라면 글자를 줄인다.
            VStack(spacing: 1) {
                Text(item.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .minimumScaleFactor(0.5)
                Text(Fmt.changeShort(item.change))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(ChangeText.style(item.change, scheme: scheme, renderingMode: renderingMode))
                    .trend(item.change)
                    .minimumScaleFactor(0.6)
            }
            .lineLimit(1)
            .padding(.horizontal, 5)
        }
    }

    @Environment(\.widgetRenderingMode) private var renderingMode
}

/// 코인 사각형(가로 2칸)의 "이름·등락률" 모드: 코인 2개를 한 줄씩, 가격 없이 크게.
struct ChangeOnlyRows: View {
    let items: [SmallSquareQuote.Item]
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

/// 홈 화면 2×2: 제목·갱신 시각 / 심볼 크게 + 이름 / 가격 크게 (+보조 가격) / 등락률.
/// 가격은 [prices]를 넓은 표기부터 시도해 한 줄에 들어가는 첫 번째를 쓴다.
struct SmallHomeCard: View {
    let title: String
    let snapshot: Snapshot
    let now: Date
    let symbol: String
    let name: String?
    let prices: [String]
    var secondary: String? = nil
    /// 가격 옆에 작게 붙이는 보조 값 (미국주식 원화). 넓은 것부터, 한 줄에 들어가는 첫 번째를 쓴다.
    var inlineSecondary: [String] = []
    let change: Double?
    let scheme: String
    /// 기호 왼쪽 아이콘 (코인 로고·주식 로고·국기). nil이면 아이콘 없이.
    var icon: ItemIcon.Kind? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: title, snapshot: snapshot, now: now)
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 6) {
                if let icon {
                    ItemIcon(kind: icon, size: 28)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(symbol)
                        .font(.system(size: 22, weight: .bold))
                        .minimumScaleFactor(0.6)
                    if let name {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            if let side = inlineSecondary.last {
                let price = prices.first ?? "—"
                ViewThatFits(in: .horizontal) {
                    ForEach(inlineSecondary, id: \.self) { priceLine(price, $0) }
                    priceLine(price, side).minimumScaleFactor(0.6)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    ForEach(prices, id: \.self) { priceText($0) }
                    priceText(prices.last ?? "—").minimumScaleFactor(0.6)
                }
            }
            if let secondary {
                Text(secondary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            ChangeText(pct: change, scheme: scheme)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .padding(.top, 1)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func priceText(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 19, weight: .semibold))
            .monospacedDigit()
            .trend(change)
    }

    /// 큰 가격 + 옆에 작은 보조 값 ("$397.45 529,562원").
    private func priceLine(_ price: String, _ side: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            priceText(price)
            Text(side).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
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
    /// [backdrop]이 있으면 홈 화면 2×2에서 종목 로고를 배경에 깐다 (단일 종목 위젯).
    func widgetBackground(squareSmall: Bool = false, backdrop: Backdrop? = nil) -> some View {
        modifier(WidgetBackground(squareSmall: squareSmall, backdrop: backdrop))
    }
}

/// 홈 위젯 기본 배경색 (앱 다크 테마와 같은 짙은 회색).
let widgetBaseColor = Color(red: 0.11, green: 0.11, blue: 0.12)

private struct WidgetBackground: ViewModifier {
    let squareSmall: Bool
    var backdrop: Backdrop? = nil
    @Environment(\.widgetFamily) private var family

    func body(content: Content) -> some View {
        if family == .systemSmall {
            // 홈 화면은 컬러로 그려진다: 앱 다크 테마와 같은 짙은 배경 + 흰 글자.
            // 홈 화면 "색조·투명" 모드에서는 iOS가 이 배경을 지우고 단색으로 그린다.
            if let backdrop, backdrop.style != .plain {
                content
                    .environment(\.colorScheme, .dark)
                    // 색이 있는 배경 위에서도 글자가 읽히게 옅은 그림자를 준다.
                    .shadow(color: .black.opacity(backdrop.style == .watermark ? 0 : 0.55), radius: 2, y: 1)
                    .containerBackground(for: .widget) { LogoBackdrop(backdrop: backdrop) }
            } else {
                content
                    .environment(\.colorScheme, .dark)
                    .containerBackground(for: .widget) { widgetBaseColor }
            }
        } else {
            lockScreen(content)
        }
    }

    private func lockScreen(_ content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if squareSmall && family == .accessoryCircular {
                Color.clear
            } else {
                AccessoryWidgetBackground()
            }
        }
    }
}

/// 자유 구성 위젯 칸 왼쪽 아이콘.
/// - 코인: 위젯 Assets의 `coin-<기호>` 이미지 (spothq/cryptocurrency-icons, CC0). 없으면 글자 동그라미.
/// - 주식: 위젯이 받아 둔 로고(StockLogos). 없으면 글자 동그라미. 환율: 국기.
struct ItemIcon: View {
    enum Kind: Hashable {
        case coin(String)
        /// 주식: [id]는 StockLogos 키("us-TSLA", "kr-005930"). 로고가 아직 없으면 [letter] 첫 글자.
        case stock(id: String, letter: String)
        case letter(String)
        case flag(String)
    }

    let kind: Kind
    var size: CGFloat = 20

    var body: some View {
        switch kind {
        case .coin(let symbol):
            if UIImage(named: "coin-\(symbol)") != nil {
                image("coin-\(symbol)")
            } else {
                letter(symbol)
            }
        case .stock(let id, let text):
            if let u = StockLogos.fileURL(key: id), let img = UIImage(contentsOfFile: u.path) {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                letter(text)
            }
        case .letter(let text):
            letter(text)
        case .flag(let code):
            if let f = Self.flags[code] {
                Text(f).font(.system(size: size * 0.85)).frame(width: size, height: size)
            } else {
                letter(code)
            }
        }
    }

    /// 앱 Catalog.currencies(수출입은행 고시 22개)와 같은 목록.
    private static let flags = [
        "USD": "🇺🇸", "JPY": "🇯🇵", "EUR": "🇪🇺", "CNY": "🇨🇳", "THB": "🇹🇭",
        "GBP": "🇬🇧", "CHF": "🇨🇭", "CAD": "🇨🇦", "AUD": "🇦🇺", "NZD": "🇳🇿",
        "HKD": "🇭🇰", "SGD": "🇸🇬", "IDR": "🇮🇩", "MYR": "🇲🇾", "BND": "🇧🇳",
        "AED": "🇦🇪", "SAR": "🇸🇦", "KWD": "🇰🇼", "BHD": "🇧🇭", "SEK": "🇸🇪",
        "NOK": "🇳🇴", "DKK": "🇩🇰",
    ]

    @ViewBuilder
    private func image(_ name: String) -> some View {
        if #available(iOS 18.0, *) {
            Image(name).resizable().widgetAccentedRenderingMode(.fullColor)
                .scaledToFit().frame(width: size, height: size)
        } else {
            Image(name).resizable().scaledToFit().frame(width: size, height: size)
        }
    }

    private func letter(_ text: String) -> some View {
        Text(String(text.prefix(1)).uppercased())
            .font(.system(size: size * 0.5, weight: .bold))
            .frame(width: size, height: size)
            .background(Circle().fill(.secondary.opacity(0.35)))
    }
}

// MARK: - 단일 종목 위젯 로고 배경

/// 홈 위젯 배경에 깔 로고와 방식. 로고가 없으면(아직 못 받은 주식 등) nil → 기본 배경.
struct Backdrop {
    let image: UIImage
    let style: LogoBackground

    /// 코인 위젯: 위젯 편집 순서가 가리키는 코인의 로고 (위젯 Assets `coin-<기호>`).
    static func coin(_ e: SnapshotEntry) -> Backdrop? {
        guard e.background != .plain,
              let c = e.snapshot?.coins.dropFirst(e.offset).first,
              let img = UIImage(named: "coin-\(c.symbol)") else { return nil }
        return Backdrop(image: img, style: e.background)
    }

    /// 미국주식 위젯: 위젯이 받아 둔 로고 (StockLogos "us-<티커>").
    static func stock(_ e: SnapshotEntry) -> Backdrop? {
        guard e.background != .plain,
              let st = e.snapshot?.stocks.dropFirst(e.offset).first,
              let u = StockLogos.fileURL(key: "us-\(st.ticker)"),
              let img = UIImage(contentsOfFile: u.path) else { return nil }
        return Backdrop(image: img, style: e.background)
    }
}

/// 로고 배경 4종. 로고 원본이 100~250px로 작아서 크게 키우는 방식(꽉 채움)은 흐릿할 수 있다.
struct LogoBackdrop: View {
    let backdrop: Backdrop

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = max(w, h)
            ZStack {
                widgetBaseColor
                switch backdrop.style {
                case .plain:
                    EmptyView()
                case .watermark:
                    // 정중앙에 크게, 흐리게.
                    logo.scaledToFit()
                        .frame(width: side * 0.75, height: side * 0.75)
                        .opacity(0.3)
                        .position(x: w / 2, y: h / 2)
                case .fill:
                    logo.scaledToFill().frame(width: w, height: h).clipped()
                    LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom)
                case .color:
                    let c = Self.averageColor(backdrop.image) ?? (0.3, 0.3, 0.32)
                    LinearGradient(colors: [rgb(c, 0.85), rgb(c, 0.4)], startPoint: .top, endPoint: .bottom)
                case .blur:
                    logo.scaledToFill()
                        .frame(width: side * 1.3, height: side * 1.3)
                        .blur(radius: 24)
                        .position(x: w / 2, y: h / 2)
                    Color.black.opacity(0.3)
                }
            }
            .frame(width: w, height: h)
        }
    }

    private var logo: some View {
        Image(uiImage: backdrop.image).resizable()
    }

    private func rgb(_ c: (Double, Double, Double), _ k: Double) -> Color {
        Color(red: c.0 * k, green: c.1 * k, blue: c.2 * k)
    }

    /// 투명한 부분을 뺀 평균 색 (0~1). CIAreaAverage 결과는 알파가 곱해져 있으므로 알파로 나눈다.
    static func averageColor(_ image: UIImage) -> (Double, Double, Double)? {
        guard let ci = CIImage(image: image) else { return nil }
        let f = CIFilter.areaAverage()
        f.inputImage = ci
        f.extent = ci.extent
        guard let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                    format: .RGBA8, colorSpace: nil)
        let a = Double(px[3]) / 255
        guard a > 0.01 else { return nil }
        func ch(_ v: UInt8) -> Double { min(1, Double(v) / 255 / a) }
        // 흰 바탕 로고(애플 등)는 평균이 밝은 회색이라 흰 글자가 안 읽힌다. 가장 밝은 채널을 0.6 이하로 낮춘다.
        let (r, g, b) = (ch(px[0]), ch(px[1]), ch(px[2]))
        let k = min(1, 0.6 / max(r, g, b, 0.001))
        return (r * k, g * k, b * k)
    }
}

// MARK: - 자유 구성 줄 색

/// 자유 구성 위젯 한 줄의 배경색. 코인·주식은 로고 평균 색(LogoBackdrop.averageColor, 밝기 상한 있음),
/// 환율은 국기 이모지에서 색을 뽑기 어려워 통화마다 대표 색을 정해 둔다. 로고가 아직 없으면 nil(기본 배경).
enum ItemTint {
    static func color(for kind: ItemIcon.Kind) -> Color? {
        switch kind {
        case .coin(let symbol):
            return UIImage(named: "coin-\(symbol)").flatMap(LogoBackdrop.averageColor).map(rgb)
        case .stock(let id, _):
            guard let u = StockLogos.fileURL(key: id), let img = UIImage(contentsOfFile: u.path) else { return nil }
            return LogoBackdrop.averageColor(img).map(rgb)
        case .flag(let code):
            return fx[code].map(rgb)
        case .letter:
            return nil
        }
    }

    private static func rgb(_ c: (Double, Double, Double)) -> Color {
        Color(red: c.0, green: c.1, blue: c.2)
    }

    private static let navy = (0.16, 0.24, 0.52), red = (0.58, 0.12, 0.16), green = (0.05, 0.40, 0.22)
    /// 앱 Catalog.currencies(22개)와 같은 목록. 국기의 주된 색.
    private static let fx: [String: (Double, Double, Double)] = [
        "USD": navy, "JPY": red, "EUR": (0.10, 0.22, 0.58), "CNY": red, "THB": navy,
        "GBP": navy, "CHF": red, "CAD": red, "AUD": navy, "NZD": navy,
        "HKD": red, "SGD": red, "IDR": red, "MYR": navy, "BND": (0.55, 0.48, 0.08),
        "AED": green, "SAR": green, "KWD": green, "BHD": red, "SEK": (0.02, 0.32, 0.55),
        "NOK": red, "DKK": red,
    ]
}
