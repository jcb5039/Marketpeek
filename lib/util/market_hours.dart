/// 미국 정규장(09:30–16:00 ET, 평일) 여부를 계산한다.
///
/// 서머타임(3월 둘째 일요일 ~ 11월 첫째 일요일)은 반영하지만 미국 공휴일은
/// 반영하지 않는다. 공휴일 처리는 서버가 장 상태를 내려주는 단계에서 보완한다.
/// 같은 규칙이 iOS 위젯(MarketHours.swift)에도 구현되어 있으니 함께 수정할 것.
enum UsMarketStatus { open, closed }

UsMarketStatus usMarketStatus(DateTime now) {
  final utc = now.toUtc();
  final offset = _isUsDst(utc) ? -4 : -5;
  final et = utc.add(Duration(hours: offset));
  if (et.weekday == DateTime.saturday || et.weekday == DateTime.sunday) {
    return UsMarketStatus.closed;
  }
  final minutes = et.hour * 60 + et.minute;
  return (minutes >= 9 * 60 + 30 && minutes < 16 * 60)
      ? UsMarketStatus.open
      : UsMarketStatus.closed;
}

String usMarketStatusLabel(UsMarketStatus s) =>
    s == UsMarketStatus.open ? '장중' : '장 마감, 종가 기준';

bool _isUsDst(DateTime utc) {
  final y = utc.year;
  // 3월 둘째 일요일 02:00 EST = 07:00 UTC
  final start = DateTime.utc(y, 3, _nthSunday(y, 3, 2), 7);
  // 11월 첫째 일요일 02:00 EDT = 06:00 UTC
  final end = DateTime.utc(y, 11, _nthSunday(y, 11, 1), 6);
  return !utc.isBefore(start) && utc.isBefore(end);
}

int _nthSunday(int year, int month, int n) {
  final first = DateTime.utc(year, month, 1);
  final firstSunday = 1 + (DateTime.sunday - first.weekday) % 7;
  return firstSunday + 7 * (n - 1);
}
