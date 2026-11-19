// 수출입은행 응답 변환과 /quotes 캐시 동작 테스트. 실제 외부 API는 부르지 않는다.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchFx, kstDate } from '../src/eximbank';
import worker, { collectYesterday, refresh, type Env } from '../src/index';
import { sampleIssue } from '../src/issue';
import { BACKFILL_PER_RUN, HISTORY_KEY, historyPoints, updateHistory } from '../src/fxHistory';
import { fetchCoinMoves } from '../src/yesterday';

const jsonRes = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

/// KVNamespace 대신 쓰는 메모리 저장소.
function memoryKv() {
  const store = new Map<string, string>();
  const kv = {
    store,
    get: async (key: string, type?: string) => {
      const v = store.get(key);
      if (v == null) return null;
      return type === 'json' ? JSON.parse(v) : v;
    },
    put: async (key: string, value: string) => void store.set(key, value),
  };
  return kv;
}

function env(kv = memoryKv()): Env & { QUOTES: ReturnType<typeof memoryKv> } {
  return {
    QUOTES: kv as unknown as KVNamespace & ReturnType<typeof memoryKv>,
    FX_CODES: 'USD,JPY',
    ISSUE_COINS: 'BTC,ETH,NOPE',
    EXIM_API_KEY: 'ek',
  } as Env & { QUOTES: ReturnType<typeof memoryKv> };
}

afterEach(() => vi.unstubAllGlobals());

describe('fetchFx', () => {
  // 2026-11-09(월) 10:00 KST → 오늘은 고시 전(빈 배열), 주말 건너뛰고 11-06(금)과 11-05(목)을 비교.
  const now = new Date('2026-11-09T01:00:00Z');
  const days: Record<string, unknown[]> = {
    '20261106': [
      { result: 1, cur_unit: 'USD', deal_bas_r: '1,430.5' },
      { result: 1, cur_unit: 'JPY(100)', deal_bas_r: '950' },
      { result: 1, cur_unit: 'IDR(100)', deal_bas_r: '8.69' },
    ],
    '20261105': [
      { result: 1, cur_unit: 'USD', deal_bas_r: '1,425' },
      { result: 1, cur_unit: 'JPY(100)', deal_bas_r: '952' },
      { result: 1, cur_unit: 'IDR(100)', deal_bas_r: '8.71' },
    ],
  };
  const fetchFn = vi.fn(async (url: string) => {
    const date = new URL(url).searchParams.get('searchdate')!;
    return jsonRes(days[date] ?? []);
  });

  it('최근 두 영업일을 찾아 등락률을 계산하고 JPY는 100엔 기준으로 매핑한다', async () => {
    const out = await fetchFx(['USD', 'JPY', 'EUR'], 'ek', now, fetchFn as unknown as typeof fetch);
    expect(out.USD.rateKrw).toBe(1430.5);
    expect(out.USD.changePct).toBeCloseTo(((1430.5 - 1425) / 1425) * 100, 9);
    expect(out.JPY.rateKrw).toBe(950);
    expect(out.EUR).toBeUndefined();
  });

  it('IDR은 100루피아 기준(IDR(100))으로 매핑한다', async () => {
    const out = await fetchFx(['IDR'], 'ek', now, fetchFn as unknown as typeof fetch);
    expect(out.IDR.rateKrw).toBe(8.69);
    expect(out.IDR.changePct).toBeCloseTo(((8.69 - 8.71) / 8.71) * 100, 9);
  });

  it('인증 오류(result 3)면 예외', async () => {
    const bad = async () => jsonRes([{ result: 3, cur_unit: '', deal_bas_r: '' }]);
    await expect(fetchFx(['USD'], 'ek', now, bad as unknown as typeof fetch)).rejects.toThrow('result 3');
  });

  it('kstDate는 한국 날짜 기준', () => {
    expect(kstDate(new Date('2026-11-05T16:00:00Z'))).toBe('20261106'); // KST 11-06 01:00
    expect(kstDate(new Date('2026-11-05T16:00:00Z'), 1)).toBe('20261105');
  });
});

describe('refresh / GET /quotes', () => {
  function stubApis() {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL) =>
      jsonRes([{ result: 1, cur_unit: 'USD', deal_bas_r: '1,430.5' }]),
    );
    vi.stubGlobal('fetch', fetchMock);
    return fetchMock;
  }

  it('환율은 1시간이 안 지났으면 다시 받지 않는다', async () => {
    const fetchMock = stubApis();
    const e = env();
    e.QUOTES.store.set(
      'fx',
      JSON.stringify({ updatedAt: '2026-11-06T05:30:00Z', data: { USD: { rateKrw: 1400, changePct: 0 } } }),
    );
    await refresh(e, new Date('2026-11-06T06:00:00Z'));
    expect(fetchMock.mock.calls.some(([u]) => String(u).includes('koreaexim'))).toBe(false);
  });

  it('/quotes는 요청한 통화만 돌려주고, 캐시가 비었으면 먼저 채운다', async () => {
    stubApis();
    const e = env();
    const res = await worker.fetch(new Request('https://x/quotes?stocks=TSLA&fx=usd,jpy'), e);
    const body = (await res.json()) as Record<string, unknown>;
    expect(res.status).toBe(200);
    expect(body.fx).toEqual({ USD: { rateKrw: 1430.5, changePct: 0 } });
    expect(body.stocks).toBeUndefined(); // 주식은 더 이상 서버에서 주지 않는다.
    expect(body.issue).toBeNull();
    expect(e.QUOTES.store.has('fx')).toBe(true);
  });

  it('cron은 Finnhub 등 주식 API를 부르지 않는다', async () => {
    const fetchMock = stubApis();
    await refresh(env(), new Date('2026-11-06T06:00:00Z'));
    expect(fetchMock.mock.calls.every(([u]) => String(u).includes('koreaexim'))).toBe(true);
  });

  it('/quotes의 issue는 예시 이슈가 있어도 아직 null이다', async () => {
    stubApis();
    const res = await worker.fetch(new Request('https://x/quotes?fx=USD'), env());
    const body = (await res.json()) as Record<string, unknown>;
    expect(body.issue).toBeNull();
  });

  it('없는 경로는 404', async () => {
    const res = await worker.fetch(new Request('https://x/nope'), env());
    expect(res.status).toBe(404);
  });
});

describe('GET /issue', () => {
  it('앱·위젯이 읽는 형식(text, shortText, generatedAt)으로 예시 이슈를 돌려준다', async () => {
    const res = await worker.fetch(new Request('https://x/issue'), env());
    const body = (await res.json()) as Record<string, unknown>;
    expect(res.status).toBe(200);
    expect(typeof body.text).toBe('string');
    expect(typeof body.shortText).toBe('string');
    expect(Number.isNaN(Date.parse(body.generatedAt as string))).toBe(false);
    expect(body.sample).toBe(true);
  });

  it('date는 한국 날짜 기준 어제다', () => {
    // UTC 11-15 14:59 = KST 11-15 23:59 → 어제는 11-14
    expect(sampleIssue(new Date('2026-11-15T14:59:00Z')).date).toBe('2026-11-14');
    // UTC 11-15 15:00 = KST 11-16 00:00 → 어제는 11-15
    expect(sampleIssue(new Date('2026-11-15T15:00:00Z')).date).toBe('2026-11-15');
  });

  it('GET이 아니면 405', async () => {
    const res = await worker.fetch(new Request('https://x/issue', { method: 'POST' }), env());
    expect(res.status).toBe(405);
  });
});

describe('어제 이슈 재료', () => {
  // KST 2026-11-16 10:00 → 어제는 11-15. 업비트 일봉은 최신순.
  const now = new Date('2026-11-16T01:00:00Z');
  const candle = (kstDay: string, price: number, rate: number) => ({
    candle_date_time_kst: `${kstDay}T09:00:00`,
    trade_price: price,
    change_rate: rate,
  });
  const upbit = vi.fn(async (url: string) => {
    const market = new URL(url).searchParams.get('market');
    if (market === 'KRW-BTC')
      return jsonRes([candle('2026-11-16', 88_000_000, -0.01), candle('2026-11-15', 89_949_000, 0.0122780166)]);
    if (market === 'KRW-ETH')
      return jsonRes([candle('2026-11-16', 4_000_000, 0.003), candle('2026-11-15', 3_990_000, -0.02)]);
    return jsonRes({ error: { name: 'Code not found' } }, 404);
  });

  it('코인은 어제 날짜의 일봉을 골라 등락률을 %(소수 둘째 자리)로 바꾸고, 실패한 코인은 뺀다', async () => {
    const out = await fetchCoinMoves(['BTC', 'ETH', 'NOPE'], now, upbit as unknown as typeof fetch);
    expect(out).toEqual([
      { symbol: 'BTC', closeKrw: 89_949_000, changePct: 1.23 },
      { symbol: 'ETH', closeKrw: 3_990_000, changePct: -2 },
    ]);
  });

  it('어제 봉이 응답에 없으면 그 코인은 뺀다', async () => {
    const onlyToday = async () => jsonRes([candle('2026-11-16', 1, 0)]);
    const out = await fetchCoinMoves(['BTC'], now, onlyToday as unknown as typeof fetch);
    expect(out).toEqual([]);
  });

  it('환율은 캐시 값을 그대로 쓰고 수출입은행은 다시 부르지 않는다', async () => {
    const e = env();
    e.QUOTES.store.set(
      'fx',
      JSON.stringify({ updatedAt: '2026-11-16T00:30:00Z', data: { USD: { rateKrw: 1430.5, changePct: 0.4 } } }),
    );
    const data = await collectYesterday(e, now, upbit as unknown as typeof fetch);
    expect(data.date).toBe('2026-11-15');
    expect(data.coins.map((c) => c.symbol)).toEqual(['BTC', 'ETH']);
    expect(data.fx).toEqual({ USD: { rateKrw: 1430.5, changePct: 0.4 } });
    expect(data.fxUpdatedAt).toBe('2026-11-16T00:30:00Z');
    expect(upbit.mock.calls.every(([u]) => String(u).includes('api.upbit.com'))).toBe(true);
  });

  it('/issue/data는 배포 주소에서는 404', async () => {
    const res = await worker.fetch(new Request('https://marketpeek-api.example.workers.dev/issue/data'), env());
    expect(res.status).toBe(404);
  });
});

describe('환율 기록 (차트용)', () => {
  // 2026-11-09(월) 10:00 KST. 오늘은 고시 전(빈 배열), 11-07(토)·11-08(일)은 주말.
  const now = new Date('2026-11-09T01:00:00Z');
  const weekend = new Set(['20261107', '20261108']);
  const fetchFn = vi.fn(async (url: string) => {
    const date = new URL(url).searchParams.get('searchdate')!;
    if (date === '20261109' || weekend.has(date)) return jsonRes([]);
    return jsonRes([
      { result: 1, cur_unit: 'USD', deal_bas_r: `1,4${date.slice(-2)}` },
      { result: 1, cur_unit: 'JPY(100)', deal_bas_r: '950' },
    ]);
  });

  it('오늘 + 지난 날짜를 최신부터 5개 채우고, 주말은 빈 날로 기록한다', async () => {
    const h = await updateHistory(null, ['USD', 'JPY'], 'ek', now, fetchFn as unknown as typeof fetch);
    expect(Object.keys(h.days).sort()).toEqual(['20261104', '20261105', '20261106']);
    expect(h.days['20261106']).toEqual({ USD: 1406, JPY: 950 });
    expect(h.empty.sort()).toEqual(['20261107', '20261108']);
    // 오늘(고시 전)은 빈 날로 표시하지 않아 다음에 다시 묻는다.
    expect(h.empty).not.toContain('20261109');
    expect(fetchFn.mock.calls.length).toBe(1 + BACKFILL_PER_RUN);
  });

  it('이미 있는 날짜와 빈 날은 다시 묻지 않고 더 지난 날짜를 채운다', async () => {
    fetchFn.mockClear();
    const first = await updateHistory(null, ['USD'], 'ek', now, fetchFn as unknown as typeof fetch);
    fetchFn.mockClear();
    const second = await updateHistory(first, ['USD'], 'ek', now, fetchFn as unknown as typeof fetch);
    const asked = fetchFn.mock.calls.map(([u]) => new URL(String(u)).searchParams.get('searchdate'));
    expect(asked[0]).toBe('20261109');
    expect(asked.slice(1)).toEqual(['20261103', '20261102', '20261101', '20261031', '20261030']);
    expect(Object.keys(second.days).length).toBeGreaterThan(Object.keys(first.days).length);
  });

  it('historyPoints는 그 통화의 최근 영업일을 오래된 것부터 준다', () => {
    const h = {
      days: { '20261106': { USD: 1406 }, '20261104': { USD: 1404 }, '20261105': { USD: 1405, JPY: 950 } },
      empty: [],
    };
    expect(historyPoints(h, 'USD', 2)).toEqual([
      { date: '2026-11-05', rate: 1405 },
      { date: '2026-11-06', rate: 1406 },
    ]);
    expect(historyPoints(h, 'JPY', 30)).toEqual([{ date: '2026-11-05', rate: 950 }]);
  });

  it('GET /fx/history는 저장된 기록에서 읽고, code가 없으면 400', async () => {
    const e = env();
    e.QUOTES.store.set(HISTORY_KEY, JSON.stringify({ days: { '20261106': { USD: 1406 } }, empty: [] }));
    const res = await worker.fetch(new Request('https://x/fx/history?code=usd&days=30'), e);
    expect(await res.json()).toEqual({ code: 'USD', points: [{ date: '2026-11-06', rate: 1406 }] });
    const bad = await worker.fetch(new Request('https://x/fx/history'), e);
    expect(bad.status).toBe(400);
  });

  it('cron이 환율을 받을 때 기록도 KV에 쓴다', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => jsonRes([{ result: 1, cur_unit: 'USD', deal_bas_r: '1,430.5' }])));
    const e = env();
    await refresh(e, now);
    expect(e.QUOTES.store.has(HISTORY_KEY)).toBe(true);
  });
});
