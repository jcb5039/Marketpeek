// Finnhub·수출입은행 응답 변환과 /quotes 캐시 동작 테스트. 실제 외부 API는 부르지 않는다.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchFx, kstDate } from '../src/eximbank';
import { fetchStocks } from '../src/finnhub';
import worker, { refresh, type Env } from '../src/index';

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
    STOCK_TICKERS: 'TSLA,NVDA',
    FX_CODES: 'USD,JPY',
    FINNHUB_API_KEY: 'fk',
    EXIM_API_KEY: 'ek',
  } as Env & { QUOTES: ReturnType<typeof memoryKv> };
}

afterEach(() => vi.unstubAllGlobals());

describe('fetchStocks', () => {
  it('c·dp를 priceUsd·changePct로 바꾸고 실패·빈 티커는 뺀다', async () => {
    const fetchFn = vi.fn(async (url: string) => {
      if (url.includes('symbol=TSLA')) return jsonRes({ c: 450, dp: 3.1, pc: 436.5 });
      if (url.includes('symbol=FAKE')) return jsonRes({ c: 0, dp: null });
      return jsonRes({ error: 'limit' }, 429);
    });
    const out = await fetchStocks(['TSLA', 'FAKE', 'NVDA'], 'fk', fetchFn as unknown as typeof fetch);
    expect(out).toEqual({ TSLA: { priceUsd: 450, changePct: 3.1 } });
    expect(fetchFn.mock.calls[0][0]).toContain('token=fk');
  });
});

describe('fetchFx', () => {
  // 2026-11-09(월) 10:00 KST → 오늘은 고시 전(빈 배열), 주말 건너뛰고 11-06(금)과 11-05(목)을 비교.
  const now = new Date('2026-11-09T01:00:00Z');
  const days: Record<string, unknown[]> = {
    '20261106': [
      { result: 1, cur_unit: 'USD', deal_bas_r: '1,430.5' },
      { result: 1, cur_unit: 'JPY(100)', deal_bas_r: '950' },
    ],
    '20261105': [
      { result: 1, cur_unit: 'USD', deal_bas_r: '1,425' },
      { result: 1, cur_unit: 'JPY(100)', deal_bas_r: '952' },
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
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('finnhub')) {
        if (url.includes('TSLA')) return jsonRes({ c: 450, dp: 3.1 });
        return jsonRes({}, 500);
      }
      return jsonRes([{ result: 1, cur_unit: 'USD', deal_bas_r: '1,430.5' }]);
    });
    vi.stubGlobal('fetch', fetchMock);
    return fetchMock;
  }

  it('실패한 종목은 이전 캐시 값을 유지한다', async () => {
    stubApis();
    const e = env();
    e.QUOTES.store.set(
      'stocks',
      JSON.stringify({ updatedAt: '2026-11-06T00:00:00Z', data: { NVDA: { priceUsd: 180, changePct: 1 } } }),
    );
    const { stocks } = await refresh(e, new Date('2026-11-06T06:00:00Z'));
    expect(stocks?.data).toEqual({
      NVDA: { priceUsd: 180, changePct: 1 },
      TSLA: { priceUsd: 450, changePct: 3.1 },
    });
  });

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

  it('/quotes는 요청한 종목·통화만 돌려주고, 캐시가 비었으면 먼저 채운다', async () => {
    stubApis();
    const e = env();
    const res = await worker.fetch(new Request('https://x/quotes?stocks=TSLA,AAPL&fx=usd'), e);
    const body = (await res.json()) as Record<string, unknown>;
    expect(res.status).toBe(200);
    expect(body.stocks).toEqual({ TSLA: { priceUsd: 450, changePct: 3.1 } });
    expect(body.fx).toEqual({ USD: { rateKrw: 1430.5, changePct: 0 } });
    expect(body.issue).toBeNull();
    expect(e.QUOTES.store.has('stocks')).toBe(true);
  });

  it('없는 경로는 404', async () => {
    const res = await worker.fetch(new Request('https://x/nope'), env());
    expect(res.status).toBe(404);
  });
});
