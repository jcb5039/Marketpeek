import Foundation

/// 미국 정규장(09:30–16:00 ET, 평일) 여부. lib/util/market_hours.dart와 같은 규칙.
/// 공휴일은 반영하지 않는다 (서버가 장 상태를 내려주면 교체).
enum MarketHours {
    static func isOpen(at date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        guard let ny = TimeZone(identifier: "America/New_York") else { return false }
        cal.timeZone = ny
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = c.weekday, let h = c.hour, let m = c.minute else { return false }
        if wd == 1 || wd == 7 { return false }  // 일, 토
        let minutes = h * 60 + m
        return minutes >= 9 * 60 + 30 && minutes < 16 * 60
    }

    static func label(at date: Date) -> String {
        isOpen(at: date) ? "장중" : "장 마감"
    }
}
