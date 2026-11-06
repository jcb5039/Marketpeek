import 'package:intl/intl.dart';

import '../models/models.dart';

final _krw = NumberFormat('#,##0', 'ko_KR');
final _krw2 = NumberFormat('#,##0.00', 'ko_KR');
final _usd = NumberFormat('#,##0.00', 'en_US');

/// 원화 가격. 100원 미만 소액(코인·환율)은 소수점 둘째 자리까지,
/// 1원 미만 코인(예: PEPE 0.00694원)은 유효숫자 4자리까지.
String formatKrw(double v) => '${_krwNumber(v)}원';

String _krwNumber(double v) {
  final a = v.abs();
  if (a > 0 && a < 1) {
    return v.toStringAsPrecision(4).replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return a < 100 ? _krw2.format(v) : _krw.format(v);
}

String formatUsd(double v) => '\$${_usd.format(v)}';

String formatPct(double v) {
  final sign = v > 0 ? '+' : (v < 0 ? '-' : '');
  return '$sign${v.abs().toStringAsFixed(2)}%';
}

/// 환율 값. USD처럼 소수점이 의미 있는 통화는 둘째 자리까지 보여준다.
String formatFxRate(double v) {
  final rounded = v == v.roundToDouble();
  return '${rounded ? _krw.format(v) : _krw2.format(v)}원';
}

/// 예: "1 USD = 1,430.50원", "100 JPY = 950원"
String formatFxLine(Currency c, double rateKrw) =>
    '${c.unit} ${c.code} = ${formatFxRate(rateKrw)}';

/// 미국주식 원화 환산가. 위젯에서 선택한 통화와 관계없이 항상 USD/KRW로 계산한다.
double stockKrw(double priceUsd, double usdKrw) =>
    (priceUsd * usdKrw).roundToDouble();

String formatHm(DateTime t) => DateFormat('HH:mm').format(t);

/// 위젯 공간이 모자랄 때 쓰는 짧은 원화 표기 ("원" 생략).
/// 100,000,000 → "1억", 123,456,789 → "1.23억", 5,200,000 → "520만", 643,725 → "64.4만", 3,500 → "3,500"
String formatKrwShort(double v) {
  String trim(String s) => s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  final a = v.abs();
  if (a >= 1e8) return '${trim((v / 1e8).toStringAsFixed(2))}억';
  if (a >= 1e5) return '${trim((v / 1e4).toStringAsFixed(a >= 1e6 ? 0 : 1))}만';
  return _krwNumber(v);
}
