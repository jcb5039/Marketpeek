// AI 어제 이슈의 재료: 한국 기준 어제 주요 코인(업비트)과 환율이 얼마나 움직였는지 모은다.
// 코인 목록은 사용자별 관심 목록이 아니라 wrangler.toml ISSUE_COINS의 고정 목록이다.
import { kstDate, type FxQuote } from './eximbank';
import type { MarketMove } from './markets';

export interface CoinMove {
  symbol: string;
  /// 어제 종가 (원).
  closeKrw: number;
  /// 전일 종가 대비 등락률 (%, 소수 둘째 자리).
  changePct: number;
}

export interface YesterdayData {
  /// 한국 기준 어제 (YYYY-MM-DD).
  date: string;
  /// 받는 데 실패한 코인은 빠진다.
  coins: CoinMove[];
  /// 서버 캐시의 최근 영업일 환율 등락 (수출입은행 고시 기준이라 주말·공휴일엔 어제와 다를 수 있다).
  fx: Record<string, FxQuote>;
  /// 환율 캐시 시각. 캐시가 없으면 null.
  fxUpdatedAt: string | null;
  /// 전날 미국 시장 반응(S&P500·나스닥·VIX·10년물). 받는 데 실패한 것은 빠진다.
  markets: MarketMove[];
}

interface UpbitDayCandle {
  candle_date_time_kst: string;
  trade_price: number;
  change_rate: number;
}

/// 업비트 일봉은 한국 시간 09:00~다음 날 09:00이 하루다.
/// 어제 날짜로 시작한 봉을 고른다. 오늘 09:00 전에 부르면 그 봉은 아직 진행 중이다.
export async function fetchCoinMoves(
  symbols: string[],
  now: Date,
  fetchFn: typeof fetch = fetch,
): Promise<CoinMove[]> {
  const day = dashed(kstDate(now, 1));
  const results = await Promise.allSettled(
    symbols.map(async (symbol): Promise<CoinMove | null> => {
      const url = `https://api.upbit.com/v1/candles/days?market=KRW-${symbol}&count=3`;
      const res = await fetchFn(url);
      if (!res.ok) throw new Error(`upbit ${symbol} ${res.status}`);
      const candles = (await res.json()) as UpbitDayCandle[];
      const c = candles.find((x) => x.candle_date_time_kst.startsWith(day));
      if (!c) return null;
      return { symbol, closeKrw: c.trade_price, changePct: Math.round(c.change_rate * 10_000) / 100 };
    }),
  );
  const out: CoinMove[] = [];
  for (const r of results) {
    if (r.status === 'fulfilled' && r.value) out.push(r.value);
    else if (r.status === 'rejected') console.warn(`coin move failed: ${r.reason}`);
  }
  return out;
}

export function dashed(yyyymmdd: string): string {
  return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`;
}
