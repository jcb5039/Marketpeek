// 한국수출입은행 환율 API에서 원화 환율과 전 영업일 대비 등락률을 받아온다.

export interface FxQuote {
  /// 앱 Currency.unit 단위 기준 원화 값 (JPY는 100엔 기준).
  rateKrw: number;
  changePct: number;
}

/// 앱 통화 코드 → 수출입은행 cur_unit. 위안화는 역외 위안(CNH)으로 고시된다.
const EXIM_CODE: Record<string, string> = {
  JPY: 'JPY(100)',
  CNY: 'CNH',
};

interface EximRow {
  result: number;
  cur_unit: string;
  deal_bas_r: string;
}

/// 수출입은행은 영업일 오전 11시쯤 하루 한 번 고시한다. 주말·공휴일·고시 전에는 빈 배열이 온다.
/// 오늘부터 거꾸로 고시가 있는 날 두 개를 찾아 최신 값과 전 영업일 값을 비교한다.
export async function fetchFx(
  codes: string[],
  apiKey: string,
  now: Date = new Date(),
  fetchFn: typeof fetch = fetch,
): Promise<Record<string, FxQuote>> {
  const days: Map<string, number>[] = [];
  for (let back = 0; back < 10 && days.length < 2; back++) {
    const rates = await fetchDay(kstDate(now, back), apiKey, fetchFn);
    if (rates.size > 0) days.push(rates);
  }
  const [latest, prev] = days;
  if (!latest) return {};

  const out: Record<string, FxQuote> = {};
  for (const code of codes) {
    const key = EXIM_CODE[code] ?? code;
    const rate = latest.get(key);
    if (rate == null) continue;
    const before = prev?.get(key);
    out[code] = {
      rateKrw: rate,
      changePct: before ? ((rate - before) / before) * 100 : 0,
    };
  }
  return out;
}

async function fetchDay(
  yyyymmdd: string,
  apiKey: string,
  fetchFn: typeof fetch,
): Promise<Map<string, number>> {
  const url =
    'https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON' +
    `?authkey=${apiKey}&searchdate=${yyyymmdd}&data=AP01`;
  const res = await fetchFn(url);
  if (!res.ok) throw new Error(`eximbank ${yyyymmdd}: HTTP ${res.status}`);
  const rows = (await res.json()) as EximRow[];
  const map = new Map<string, number>();
  for (const row of rows) {
    // result: 1 성공, 2 DATA코드 오류, 3 인증코드 오류, 4 일일 제한 횟수 마감
    if (row.result !== 1) throw new Error(`eximbank ${yyyymmdd}: result ${row.result}`);
    map.set(row.cur_unit, Number(row.deal_bas_r.replaceAll(',', '')));
  }
  return map;
}

/// [now]의 한국 날짜에서 [daysBack]일 전을 YYYYMMDD로.
export function kstDate(now: Date, daysBack = 0): string {
  const kst = new Date(now.getTime() + 9 * 3600_000 - daysBack * 86400_000);
  return kst.toISOString().slice(0, 10).replaceAll('-', '');
}
