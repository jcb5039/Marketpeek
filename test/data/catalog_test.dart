// Catalog: 국내·미국 종목 검색(이름·코드·티커), 순위, 결과 수 제한, 없는 종목 이름 처리.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketpeek/data/catalog.dart';
import 'package:marketpeek/models/models.dart';

void main() {
  setUp(() {
    Catalog.setKrStocks(const [
      KrStock(code: '005930', name: '삼성전자'),
      KrStock(code: '005935', name: '삼성전자우'),
      KrStock(code: '028260', name: '삼성물산'),
      KrStock(code: '247540', name: '에코프로비엠', market: 'KOSDAQ'),
    ]);
    Catalog.setStocks(const [
      UsStock(ticker: 'TSLA', name: '테슬라', engName: 'TESLA INC'),
      UsStock(ticker: 'TSM', name: 'TSMC(ADR)', engName: 'TAIWAN SEMICONDUCTOR', excd: 'NYS'),
      UsStock(ticker: 'AAPL', name: '애플', engName: 'APPLE INC'),
      UsStock(ticker: 'SPY', name: 'SS SPDR S&P 500 TRUST', engName: 'SPDR S&P 500 ETF', excd: 'AMS'),
    ]);
  });
  tearDown(Catalog.resetStocks);

  test('국내주식: 이름이 정확히 같은 종목이 먼저, 그다음 앞부분 일치', () {
    final names = Catalog.searchKrStocks('삼성전자').map((s) => s.name).toList();
    expect(names, ['삼성전자', '삼성전자우']);
    expect(Catalog.searchKrStocks('삼성').length, 3);
  });

  test('국내주식: 종목코드로도 찾는다', () {
    expect(Catalog.searchKrStocks('2475').single.name, '에코프로비엠');
  });

  test('미국주식: 티커·한글명·영문명으로 찾고 티커 일치가 먼저', () {
    expect(Catalog.searchStocks('TS').map((s) => s.ticker), ['TSLA', 'TSM']);
    expect(Catalog.searchStocks('테슬라').single.ticker, 'TSLA');
    expect(Catalog.searchStocks('apple').single.ticker, 'AAPL');
  });

  test('거래소 코드와 없는 종목 처리', () {
    expect(Catalog.stock('SPY').excd, 'AMS');
    expect(Catalog.stock('ZZZZ').name, 'ZZZZ');
    expect(Catalog.krStock('000000').name, '000000');
  });

  test('검색 결과는 최대 searchLimit개', () {
    Catalog.setKrStocks([
      for (var i = 0; i < 200; i++) KrStock(code: i.toString().padLeft(6, '0'), name: '테스트$i'),
    ]);
    expect(Catalog.searchKrStocks('테스트').length, Catalog.searchLimit);
  });
}
