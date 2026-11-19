// 환율 차트용 날짜별 기록. 수출입은행은 하루 한 번 고시하므로 "날짜 → 통화별 환율"을 KV에 모아 둔다.
// 위젯은 GET /fx/history?code=USD&days=30 으로 최근 영업일 환율을 받아 차트를 그린다.
import { fetchDayRates, kstDate } from './eximbank';

export interface FxHistory {
  /// YYYYMMDD → { USD: 1430.5, JPY: 950, ... }
  days: Record<string, Record<string, number>>;
  /// 고시가 없던 지난 날짜(주말·공휴일). 다시 묻지 않는다.
  empty: string[];
}

export const HISTORY_KEY = 'fx:history';
/// 보관 기간(달력 기준 일). 차트는 이 안의 최근 영업일 30일을 쓴다.
export const KEEP_DAYS = 45;
/// 한 번 실행에 거꾸로 채우는 지난 날짜 수. 수출입은행 하루 호출 한도(1,000회) 안에서 여유 있게.
export const BACKFILL_PER_RUN = 5;

/// 오늘 환율을 다시 받고, 기록에 없는 지난 날짜를 최신부터 [BACKFILL_PER_RUN]개까지 채운다.
/// 오늘은 고시 전(오전 11시쯤 전)이면 비어 있으므로 빈 날로 표시하지 않고 다음에 다시 묻는다.
export async function updateHistory(
  old: FxHistory | null,
  codes: string[],
  apiKey: string,
  now: Date,
  fetchFn: typeof fetch = fetch,
): Promise<FxHistory> {
  const keep = new Set(Array.from({ length: KEEP_DAYS }, (_, i) => kstDate(now, i)));
  const h: FxHistory = {
    days: Object.fromEntries(Object.entries(old?.days ?? {}).filter(([d]) => keep.has(d))),
    empty: (old?.empty ?? []).filter((d) => keep.has(d)),
  };
  const today = kstDate(now);
  const missing = [...keep]
    .filter((d) => d !== today && !(d in h.days) && !h.empty.includes(d))
    .slice(0, BACKFILL_PER_RUN);

  for (const date of [today, ...missing]) {
    try {
      const rates = await fetchDayRates(codes, date, apiKey, fetchFn);
      if (Object.keys(rates).length > 0) h.days[date] = rates;
      else if (date !== today) h.empty.push(date);
    } catch (e) {
      // 한도 초과·인증 오류 등은 다음 실행에서 다시 시도한다.
      console.warn(`fx history ${date} failed: ${e}`);
      break;
    }
  }
  return h;
}

export interface FxHistoryPoint {
  /// "2026-11-18" (한국 날짜, 고시일)
  date: string;
  rate: number;
}

/// [code]의 최근 영업일 [days]개를 오래된 것부터.
export function historyPoints(h: FxHistory | null, code: string, days: number): FxHistoryPoint[] {
  return Object.keys(h?.days ?? {})
    .sort()
    .filter((d) => h!.days[d][code] != null)
    .slice(-days)
    .map((d) => ({ date: `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6)}`, rate: h!.days[d][code] }));
}
