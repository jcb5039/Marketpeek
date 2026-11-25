// 전날 미국 시장 반응(FRED 지수, 미 재무부 10년물) 수집 테스트. 실제 외부 API는 부르지 않는다.
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  fetchMarketMoves, fetchTreasury10y, parseFredObservations, parseTreasury10y, splitByDate, toMove,
} from '../src/markets';

const jsonRes = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

/// 미 재무부 XML 피드와 같은 모양(필요한 부분만).
function treasuryXml(rows: [string, string][]): string {
  const entries = rows.map(([date, y10]) => `<entry><content type="application/xml"><m:properties>
<d:Id m:type="Edm.Int32">1</d:Id>
<d:NEW_DATE m:type="Edm.DateTime">${date}T00:00:00</d:NEW_DATE>
<d:BC_2YEAR m:type="Edm.Double">4.50</d:BC_2YEAR>
<d:BC_10YEAR m:type="Edm.Double">${y10}</d:BC_10YEAR>
</m:properties></content></entry>`);
  return `<?xml version="1.0"?><feed>${entries.join('\n')}</feed>`;
}

const fred = (pairs: [string, string][]) =>
  jsonRes({ observations: pairs.map(([date, value]) => ({ date, value })) });

afterEach(() => vi.restoreAllMocks());

describe('toMove: 마지막 두 값으로 등락', () => {
  it('지수는 등락과 등락률(%)', () => {
    expect(toMove('SP500', 'S&P500', [
      { date: '2026-11-18', value: 6000 },
      { date: '2026-11-19', value: 6090 },
    ])).toEqual({
      id: 'SP500', name: 'S&P500', date: '2026-11-19', close: 6090,
      prevDate: '2026-11-18', prevClose: 6000, change: 90, changePct: 1.5,
    });
  });

  it('금리는 %p 차이만, 등락률은 null', () => {
    const m = toMove('US10Y', '미국 10년물 금리', [
      { date: '2026-11-19', value: 5.04 },
      { date: '2026-11-18', value: 5.07 },
    ], true);
    expect(m).toMatchObject({ date: '2026-11-19', close: 5.04, change: -0.03, changePct: null });
  });

  it('값이 두 개보다 적으면 null', () => {
    expect(toMove('VIX', 'VIX', [{ date: '2026-11-19', value: 20 }])).toBeNull();
  });
});

describe('응답 해석', () => {
  it('FRED: 값이 없는 날(".")은 뺀다', () => {
    const body = { observations: [
      { date: '2026-11-19', value: '6090.5' },
      { date: '2026-11-18', value: '.' },
      { date: '2026-11-17', value: '6000' },
    ] };
    expect(parseFredObservations(body)).toEqual([
      { date: '2026-11-19', value: 6090.5 },
      { date: '2026-11-17', value: 6000 },
    ]);
    expect(parseFredObservations({})).toEqual([]);
  });

  it('미 재무부 XML: 날짜와 10년물만 꺼내 날짜 순으로', () => {
    const xml = treasuryXml([['2026-11-19', '5.04'], ['2026-11-17', '5.10'], ['2026-11-18', '5.07']]);
    expect(parseTreasury10y(xml)).toEqual([
      { date: '2026-11-17', value: 5.1 },
      { date: '2026-11-18', value: 5.07 },
      { date: '2026-11-19', value: 5.04 },
    ]);
  });
});

describe('fetchTreasury10y', () => {
  it('이번 달 값으로 마지막 두 날 비교', async () => {
    const f = vi.fn(async (_url: string) => new Response(treasuryXml([['2026-11-18', '5.07'], ['2026-11-19', '5.04']])));
    const m = await fetchTreasury10y(new Date('2026-11-19T22:00:00Z'), f as unknown as typeof fetch);
    expect(m).toMatchObject({ date: '2026-11-19', prevDate: '2026-11-18', change: -0.03 });
    expect(String(f.mock.calls[0][0])).toContain('field_tdr_date_value_month=202611');
    expect(f).toHaveBeenCalledTimes(1);
  });

  it('월초라 이번 달 값이 1개면 전 달도 받아 합친다', async () => {
    const f = vi.fn(async (url: string) => new Response(url.endsWith('202612')
      ? treasuryXml([['2026-12-01', '5.00']])
      : treasuryXml([['2026-11-27', '4.95'], ['2026-11-30', '4.98']])));
    // 한국 12/2 아침 7시 = 미국 12/1 저녁
    const m = await fetchTreasury10y(new Date('2026-12-01T22:00:00Z'), f as unknown as typeof fetch);
    expect(m).toMatchObject({ date: '2026-12-01', prevDate: '2026-11-30', change: 0.02 });
    expect(f.mock.calls.map(([u]) => String(u).slice(-6))).toEqual(['202612', '202611']);
  });

  it('1월 초에는 전 해 12월을 받는다', async () => {
    const f = vi.fn(async (url: string) => new Response(url.endsWith('202701')
      ? treasuryXml([])
      : treasuryXml([['2026-12-30', '5.00'], ['2026-12-31', '5.01']])));
    const m = await fetchTreasury10y(new Date('2027-01-01T22:00:00Z'), f as unknown as typeof fetch);
    expect(m).toMatchObject({ date: '2026-12-31' });
    expect(String(f.mock.calls[1][0])).toContain('202612');
  });
});

describe('fetchMarketMoves', () => {
  const now = new Date('2026-11-19T22:00:00Z');
  const route = vi.fn(async (url: string) => {
    if (url.includes('home.treasury.gov')) return new Response(treasuryXml([['2026-11-18', '5.07'], ['2026-11-19', '5.04']]));
    const series = new URL(url).searchParams.get('series_id');
    if (series === 'SP500') return fred([['2026-11-19', '6090'], ['2026-11-18', '6000']]);
    if (series === 'NASDAQCOM') return fred([['2026-11-19', '19800'], ['2026-11-18', '20000']]);
    if (series === 'VIXCLS') return jsonRes({ error_message: 'Bad Request' }, 400);
    return jsonRes({}, 404);
  });

  it('키가 있으면 FRED 지수 + 10년물, 실패한 것(VIX)은 빼고 키는 로그에 남기지 않는다', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const out = await fetchMarketMoves('secret-key', now, route as unknown as typeof fetch);
    expect(out.map((m) => [m.id, m.changePct])).toEqual([['SP500', 1.5], ['NASDAQ', -1], ['US10Y', null]]);
    expect(route.mock.calls.some(([u]) => String(u).includes('api_key=secret-key'))).toBe(true);
    expect(warn.mock.calls.flat().join(' ')).toContain('VIXCLS 400');
    expect(warn.mock.calls.flat().join(' ')).not.toContain('secret-key');
  });

  it('키가 없으면 FRED 는 부르지 않고 10년물만', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    route.mockClear();
    const out = await fetchMarketMoves(undefined, now, route as unknown as typeof fetch);
    expect(out.map((m) => m.id)).toEqual(['US10Y']);
    expect(route.mock.calls.every(([u]) => String(u).includes('home.treasury.gov'))).toBe(true);
  });
});

describe('splitByDate: 요약할 날짜와 다른 숫자 거르기', () => {
  it('FRED 가 아직 안 올린 날(지난 값)은 stale 로', () => {
    const sp = toMove('SP500', 'S&P500', [{ date: '2026-11-19', value: 7175.83 }, { date: '2026-11-20', value: 6910.39 }])!;
    const nq = toMove('NASDAQ', '나스닥', [{ date: '2026-11-18', value: 24429.88 }, { date: '2026-11-19', value: 23879.2 }])!;
    const y10 = toMove('US10Y', '미국 10년물 금리', [{ date: '2026-11-20', value: 4.1 }, { date: '2026-11-23', value: 4.05 }], true)!;
    const { fresh, stale } = splitByDate([sp, nq, y10], '2026-11-23');
    expect(fresh.map((m) => m.id)).toEqual(['US10Y']);
    expect(stale.map((m) => m.id)).toEqual(['SP500', 'NASDAQ']);
  });
});
