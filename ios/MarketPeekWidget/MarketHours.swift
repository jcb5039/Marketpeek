import Foundation

/// 위젯이 보여주는 주식 시장. 다시 받을 시점을 정할 때 쓴다([ReloadPlan]).
enum StockMarket: Hashable {
    case us, kr
}

/// 미국 정규장(09:30–16:00 ET, 평일) 여부. lib/util/market_hours.dart와 같은 규칙.
/// 국내 정규장(09:00–15:30 KST, 평일)은 위젯의 갱신 요청 시점에만 쓴다(앱에는 아직 없음).
/// 공휴일은 반영하지 않는다 (서버가 장 상태를 내려주면 교체).
enum MarketHours {
    static func isOpen(at date: Date) -> Bool {
        isOpen(.us, at: date)
    }

    static func isOpen(_ market: StockMarket, at date: Date) -> Bool {
        let (zone, open, close) = switch market {
        case .us: ("America/New_York", 9 * 60 + 30, 16 * 60)
        case .kr: ("Asia/Seoul", 9 * 60, 15 * 60 + 30)
        }
        var cal = Calendar(identifier: .gregorian)
        guard let tz = TimeZone(identifier: zone) else { return false }
        cal.timeZone = tz
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, let h = c.hour, let m = c.minute else { return false }
        if wd == 1 || wd == 7 { return false }  // 일, 토
        let minutes = h * 60 + m
        return minutes >= open && minutes < close
    }

    static func label(at date: Date) -> String {
        isOpen(at: date) ? "장중" : "장 마감"
    }
}
