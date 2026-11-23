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
  /// 최근 24시간 변동폭: (최고가 − 최저가) ÷ 24시간 전 가격 (%, 소수 둘째 자리).
  /// 예: −3% 까지 내렸다가 +2% 까지 오르면 5. 지금 가격과는 상관없다. 비트코인만 받고, 못 받으면 없다.
  rangePct?: number;
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

interface UpbitMinuteCandle {
  opening_price?: number;
  high_price?: number;
  low_price?: number;
}

/// 변동폭을 보는 시간(1시간봉 개수). 일봉은 09:00 에 끊겨 7시에는 진행 중이라 최근 24시간으로 본다.
export const RANGE_HOURS = 24;
/// 변동폭을 계산하는 코인. 주말·휴장일 "코인 큰 움직임" 판단에 비트코인만 쓴다.
export const RANGE_SYMBOLS = ['BTC'];

/// 업비트 1시간봉(최신순)에서 변동폭(%)을 계산한다. 쓸 수 있는 봉이 없으면 null.
export function rangePct(candles: UpbitMinuteCandle[]): number | null {
  const ok = candles.filter((c) =>
    [c.opening_price, c.high_price, c.low_price].every((v) => typeof v === 'number' && v > 0));
  if (ok.length === 0) return null;
  const base = ok[ok.length - 1].opening_price!; // 최신순이라 마지막이 가장 오래된 봉
  const hi = Math.max(...ok.map((c) => c.high_price!));
  const lo = Math.min(...ok.map((c) => c.low_price!));
  return Math.round(((hi - lo) / base) * 10_000) / 100;
}

/// 최근 24시간 변동폭. 실패하면 null(그때는 등락률로 판단한다).
async function fetchRange(symbol: string, fetchFn: typeof fetch): Promise<number | null> {
  try {
    const url = `https://api.upbit.com/v1/candles/minutes/60?market=KRW-${symbol}&count=${RANGE_HOURS}`;
    const res = await fetchFn(url);
    if (!res.ok) throw new Error(`upbit ${symbol} 1h ${res.status}`);
    const body = await res.json();
    return Array.isArray(body) ? rangePct(body as UpbitMinuteCandle[]) : null;
  } catch (e) {
    console.warn(`coin range failed: ${String(e)}`);
    return null;
  }
}

/// 업비트 일봉은 한국 시간 09:00~다음 날 09:00이 하루다.
/// 어제 날짜로 시작한 봉을 고른다. 오늘 09:00 전에 부르면 그 봉은 아직 진행 중이다.
export async function fetchCoinMoves(
  symbols: string[],
  now: Date,
  fetchFn: typeof fetch = fetch,
  rangeSymbols: string[] = RANGE_SYMBOLS,
): Promise<CoinMove[]> {
  const day = dashed(kstDate(now, 1));
  const results = await Promise.allSettled(
    symbols.map(async (symbol): Promise<CoinMove | null> => {
      const url = `https://api.upbit.com/v1/candles/days?market=KRW-${symbol}&count=3`;
      const [res, range] = await Promise.all([
        fetchFn(url),
        rangeSymbols.includes(symbol) ? fetchRange(symbol, fetchFn) : Promise.resolve(null),
      ]);
      if (!res.ok) throw new Error(`upbit ${symbol} ${res.status}`);
      const candles = (await res.json()) as UpbitDayCandle[];
      const c = candles.find((x) => x.candle_date_time_kst.startsWith(day));
      if (!c) return null;
      const move: CoinMove = { symbol, closeKrw: c.trade_price, changePct: Math.round(c.change_rate * 10_000) / 100 };
      if (range != null) move.rangePct = range;
      return move;
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
