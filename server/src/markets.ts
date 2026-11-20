// AI 어제 이슈 3단계 ⓐ: 전날 미국 시장 반응(지수·금리)을 모은다.
// 형 기준(11-20) 1순위 "시장 반응"의 재료: S&P500·나스닥·VIX·미국 10년물 금리(+ 비트코인은 yesterday.ts, 원/달러는 환율 캐시).
// - 미국 10년물: 미 재무부 Daily Par Yield Curve XML 피드(키 없음).
// - S&P500·나스닥·VIX: FRED(미국 세인트루이스 연준) API, 무료 키 필요(FRED_API_KEY). 키가 없으면 건너뛴다.
//   지수 시리즈는 제공사 저작권이 있어 비상업·교육용으로만 쓴다(출시 계획 없음, 형 11-20).
// 각 출처에서 값이 있는 가장 최근 두 날을 비교한다. 날짜가 어제 미국장과 맞는지는 요약 단계에서 확인한다.

export interface MarketMove {
  /// 'SP500' | 'NASDAQ' | 'VIX' | 'US10Y'
  id: string;
  /// 화면·AI 입력용 이름.
  name: string;
  /// 값의 날짜(미국 기준), YYYY-MM-DD.
  date: string;
  close: number;
  /// 직전 값이 있는 날짜, YYYY-MM-DD.
  prevDate: string;
  prevClose: number;
  /// close - prevClose (소수 둘째 자리). 금리는 %p(0.03 = 3bp).
  change: number;
  /// 전일 대비 등락률(%, 소수 둘째 자리). 금리는 null(금리는 %p 로 본다).
  changePct: number | null;
}

interface Point {
  date: string;
  value: number;
}

/// FRED 에서 받을 지수. id 는 우리 이름, series 는 FRED 시리즈 번호.
export const FRED_SERIES = [
  { id: 'SP500', series: 'SP500', name: 'S&P500' },
  { id: 'NASDAQ', series: 'NASDAQCOM', name: '나스닥' },
  { id: 'VIX', series: 'VIXCLS', name: 'VIX(공포지수)' },
] as const;

const round2 = (n: number) => Math.round(n * 100) / 100;

/// 날짜 오름차순 값 목록에서 마지막 두 개로 등락을 만든다. 두 개가 안 되면 null.
export function toMove(id: string, name: string, points: Point[], isRate = false): MarketMove | null {
  const sorted = [...points].sort((a, b) => a.date.localeCompare(b.date));
  if (sorted.length < 2) return null;
  const prev = sorted[sorted.length - 2];
  const last = sorted[sorted.length - 1];
  return {
    id, name,
    date: last.date, close: last.value,
    prevDate: prev.date, prevClose: prev.value,
    change: round2(last.value - prev.value),
    changePct: isRate || prev.value === 0 ? null : round2(((last.value - prev.value) / prev.value) * 100),
  };
}

/// FRED 관측값 응답에서 값이 있는 날만 꺼낸다(휴장일 등 값이 없으면 ".").
export function parseFredObservations(body: unknown): Point[] {
  const obs = (body as { observations?: { date?: string; value?: string }[] })?.observations ?? [];
  const out: Point[] = [];
  for (const o of obs) {
    const v = Number(o.value);
    if (o.date && o.value !== '.' && Number.isFinite(v)) out.push({ date: o.date, value: v });
  }
  return out;
}

/// 미 재무부 금리 XML 에서 날짜별 10년물 금리(%)를 꺼낸다. 날짜 오름차순.
export function parseTreasury10y(xml: string): Point[] {
  const out: Point[] = [];
  for (const block of xml.split('<m:properties>').slice(1)) {
    const date = /<d:NEW_DATE[^>]*>(\d{4}-\d{2}-\d{2})/.exec(block)?.[1];
    const raw = /<d:BC_10YEAR[^>]*>([^<]+)</.exec(block)?.[1];
    const v = Number(raw);
    if (date && raw && Number.isFinite(v)) out.push({ date, value: v });
  }
  return out.sort((a, b) => a.date.localeCompare(b.date));
}

/// YYYYMM. 요약할 미국 날짜(한국 날짜 하루 전)의 달과 그 전 달.
/// UTC 로 계산하면 한국 아침 7시(UTC 전날 22시)에 하루가 어긋나므로 한국 시간(+9시간)으로 센다.
function months(now: Date): [string, string] {
  const us = new Date(now.getTime() + 9 * 3_600_000 - 86_400_000);
  const cur = `${us.getUTCFullYear()}${String(us.getUTCMonth() + 1).padStart(2, '0')}`;
  const p = new Date(Date.UTC(us.getUTCFullYear(), us.getUTCMonth() - 1, 1));
  const prev = `${p.getUTCFullYear()}${String(p.getUTCMonth() + 1).padStart(2, '0')}`;
  return [cur, prev];
}

const treasuryUrl = (yyyymm: string) =>
  'https://home.treasury.gov/resource-center/data-chart-center/interest-rates/pages/xml'
  + `?data=daily_treasury_yield_curve&field_tdr_date_value_month=${yyyymm}`;

/// 미국 10년물 금리 등락. 이번 달 값이 2개보다 적으면(월초) 전 달도 받는다.
export async function fetchTreasury10y(now: Date, fetchFn: typeof fetch = fetch): Promise<MarketMove | null> {
  const [cur, prev] = months(now);
  const get = async (m: string) => {
    const res = await fetchFn(treasuryUrl(m));
    if (!res.ok) throw new Error(`treasury ${m} ${res.status}`);
    return parseTreasury10y(await res.text());
  };
  let points = await get(cur);
  if (points.length < 2) points = [...(await get(prev)), ...points];
  return toMove('US10Y', '미국 10년물 금리', points, true);
}

/// FRED 시리즈 하나의 등락. 최근 10개(값 없는 날 포함)만 받는다.
export async function fetchFredMove(
  id: string, series: string, name: string, apiKey: string, fetchFn: typeof fetch = fetch,
): Promise<MarketMove | null> {
  const url = 'https://api.stlouisfed.org/fred/series/observations'
    + `?series_id=${series}&api_key=${encodeURIComponent(apiKey)}&file_type=json&sort_order=desc&limit=10`;
  const res = await fetchFn(url);
  if (!res.ok) throw new Error(`fred ${series} ${res.status}`);
  return toMove(id, name, parseFredObservations(await res.json()));
}

/// 전날 시장 반응 전체. 실패한 것은 빠지고 이유는 로그에만 남긴다(키 값은 로그에 쓰지 않음).
export async function fetchMarketMoves(
  fredApiKey: string | undefined, now: Date, fetchFn: typeof fetch = fetch,
): Promise<MarketMove[]> {
  const jobs: Promise<MarketMove | null>[] = [];
  if (fredApiKey) {
    for (const s of FRED_SERIES) jobs.push(fetchFredMove(s.id, s.series, s.name, fredApiKey, fetchFn));
  } else {
    console.warn('FRED_API_KEY 없음: S&P500·나스닥·VIX 건너뜀');
  }
  jobs.push(fetchTreasury10y(now, fetchFn));
  const out: MarketMove[] = [];
  for (const r of await Promise.allSettled(jobs)) {
    if (r.status === 'fulfilled' && r.value) out.push(r.value);
    else if (r.status === 'rejected') console.warn(`market move failed: ${String(r.reason)}`);
  }
  return out;
}
