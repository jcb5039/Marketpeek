/// 앱 전반에서 쓰는 도메인 모델.
///
/// 코인·국내주식·미국주식은 서로 다른 타입·목록으로 관리한다.
library;

class Coin {
  const Coin({required this.symbol, required this.name});
  final String symbol; // 예: BTC
  final String name; // 예: 비트코인
}

class UsStock {
  const UsStock({required this.ticker, required this.name, this.engName = '', this.excd = 'NAS'});
  final String ticker; // 예: TSLA
  final String name; // 예: 테슬라 (한글명이 없으면 영문)
  final String engName; // 예: TESLA INC (검색용)

  /// 한국투자증권 해외주식 API의 거래소 코드: NAS(나스닥), NYS(뉴욕), AMS(아멕스·NYSE Arca).
  final String excd;
}

/// 국내주식 (코스피·코스닥). [code]는 6자리 종목코드.
class KrStock {
  const KrStock({required this.code, required this.name, this.market = 'KOSPI'});
  final String code; // 예: 005930
  final String name; // 예: 삼성전자
  final String market; // KOSPI | KOSDAQ
}

/// 환율 위젯에서 고를 수 있는 통화. [unit]은 표기 단위(JPY는 100).
class Currency {
  const Currency({
    required this.code,
    required this.name,
    this.unit = 1,
  });
  final String code; // 예: USD
  final String name; // 예: 미국 달러
  final int unit;
}

class CoinQuote {
  const CoinQuote({required this.priceKrw, required this.changePct});
  final double priceKrw;
  final double changePct;
}

class StockQuote {
  const StockQuote({required this.priceUsd, required this.changePct});
  final double priceUsd;
  final double changePct;
}

class KrStockQuote {
  const KrStockQuote({required this.priceKrw, required this.changePct});
  final double priceKrw;
  final double changePct;
}

/// [rateKrw]는 통화 1단위가 아니라 [Currency.unit] 단위 기준 원화 값이다.
class FxQuote {
  const FxQuote({required this.rateKrw, required this.changePct});
  final double rateKrw;
  final double changePct;
}

class MarketIssue {
  const MarketIssue({
    required this.text,
    required this.shortText,
    required this.generatedAt,
  });
  final String text;

  /// 잠금화면 시계 위 한 줄 칸용 짧은 요약 (12자 안팎).
  /// AI 요약 단계에서 [text]와 함께 생성한다.
  final String shortText;
  final DateTime generatedAt;
}

/// 상승·하락 색상 체계.
enum ChangeColorScheme {
  /// 상승 빨강 · 하락 파랑
  korean,

  /// 상승 초록 · 하락 빨강
  global,
}
