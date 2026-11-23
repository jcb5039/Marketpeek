// AI 어제 이슈 ⓒ 테스트: GDELT 뉴스, AI 지시문·답 검사, 숫자 대비, 하루 작업. 실제 외부 API·AI 는 부르지 않는다.
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Env } from '../src/index';
import worker from '../src/index';
import {
  aiText, buildMessages, findBanned, isBigCryptoMove, marketLines, numbersOnly, parseAiAnswer,
} from '../src/issueAi';
import { ISSUE_CRON, ISSUE_KEY, runIssueJob, type AiRunner } from '../src/issueJob';
import { planIssue } from '../src/issueSchedule';
import {
  cleanTitle, fetchHeadlines, GDELT_GAP_MS, INDICATOR_LIMIT, INDICATOR_RETRY_WAITS_MS, MAIN_RETRY_WAITS_MS, parseGdelt,
} from '../src/news';
import type { YesterdayData } from '../src/yesterday';

const jsonRes = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

afterEach(() => vi.restoreAllMocks());
const quiet = () => vi.spyOn(console, 'warn').mockImplementation(() => {});
/// GDELT 두 번째 검색 전 6초를 실제로 기다리지 않게 한다.
const noWait = async () => {};

const data: YesterdayData = {
  date: '2026-11-19',
  coins: [{ symbol: 'BTC', closeKrw: 130_000_000, changePct: -1.2 }],
  fx: { USD: { rateKrw: 1430.5, changePct: 0.4 } },
  fxUpdatedAt: '2026-11-19T22:00:00Z',
  markets: [
    { id: 'SP500', name: 'S&P500', date: '2026-11-19', close: 6000, prevDate: '2026-11-18', prevClose: 6061, change: -61, changePct: -1.01 },
    { id: 'NASDAQ', name: '나스닥', date: '2026-11-19', close: 19800, prevDate: '2026-11-18', prevClose: 20200, change: -400, changePct: -1.98 },
    { id: 'US10Y', name: '미국 10년물 금리', date: '2026-11-19', close: 5.04, prevDate: '2026-11-18', prevClose: 5.07, change: -0.03, changePct: null },
  ],
};

const good = JSON.stringify({
  keep: false,
  headline: '금리 인하 기대 약화에 나스닥 하락',
  items: [
    { text: '연준 위원 발언으로 금리 인하 기대가 줄어 나스닥이 2% 내린 것으로 보임', shortText: '금리 인하 기대 약화' },
    { text: '미국 10년물 금리는 소폭 하락', shortText: '10년물 금리 소폭 하락' },
  ],
});

describe('GDELT 뉴스', () => {
  it('제목 있는 기사만, 같은 제목은 하나만', () => {
    const body = { articles: [
      { url: 'https://a.com/1', title: 'Stocks fall as  Fed  signals', domain: 'a.com', seendate: '20261119T210000Z' },
      { url: 'https://b.com/2', title: 'stocks fall as fed signals', domain: 'b.com' },
      { url: 'https://c.com/3', title: '', domain: 'c.com' },
      { title: 'no url' },
    ] };
    expect(parseGdelt(body)).toEqual([
      { title: 'Stocks fall as Fed signals', url: 'https://a.com/1', domain: 'a.com', seenDate: '20261119T210000Z' },
    ]);
  });

  it('제목 다듬기: 문장부호 띄어쓰기, 숫자, S&P, 방송국 꼬리표', () => {
    expect(cleanTitle('Stock Market Today , Nov . 19 : Dow Plunges 1 , 100 Points as the S & P 500 Falls'))
      .toBe('Stock Market Today, Nov. 19: Dow Plunges 1,100 Points as the S&P 500 Falls');
    expect(cleanTitle('Wall Street Slump Continues | Talk Radio 105 . 9')).toBe('Wall Street Slump Continues');
    expect(cleanTitle('Yields rise 0 . 05 % on jobs data')).toBe('Yields rise 0.05% on jobs data');
  });

  it('같은 기사를 다른 방송국이 다시 실은 것은 하나만', () => {
    const t = 'Wall Street Slump Continues as Dow Falls Over 1 , 100 Points';
    const body = { articles: [
      { url: 'https://a.iheart.com/1', title: t, domain: 'a.iheart.com' },
      { url: 'https://b.iheart.com/1', title: `${t} | Talk Radio 105 . 9`, domain: 'b.iheart.com' },
    ] };
    expect(parseGdelt(body).map((h) => h.domain)).toEqual(['a.iheart.com']);
  });

  it('429 면 간격을 늘려 가며 다시 시도(Cloudflare 는 IP 를 같이 써서 처음부터 막혀 있곤 함)', async () => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    const busy = () => new Response('Please limit requests', { status: 429 });
    const f = vi.fn()
      .mockResolvedValueOnce(busy())
      .mockResolvedValueOnce(busy())
      .mockResolvedValueOnce(busy())
      .mockResolvedValueOnce(jsonRes({ articles: [{ url: 'https://a.com', title: 'Wall Street rallies', domain: 'a.com' }] }));
    const wait = vi.fn(async (_ms: number) => {});
    const out = await fetchHeadlines(1, f as unknown as typeof fetch, wait);
    expect(out.map((h) => h.title)).toEqual(['Wall Street rallies']);
    expect(f).toHaveBeenCalledTimes(4);
    expect(wait.mock.calls.map((c) => c[0])).toEqual([6000, 15000, 30000]);
    expect(String(f.mock.calls[0][0])).toContain('timespan=1d');
  });

  it('계속 429 면 최대 6번 시도하고 포기(빈 배열)', async () => {
    quiet();
    const busy = vi.fn(async () => new Response('busy', { status: 429 }));
    const wait = vi.fn(async (_ms: number) => {});
    expect(await fetchHeadlines(1, busy as unknown as typeof fetch, wait)).toEqual([]);
    expect(busy).toHaveBeenCalledTimes(1 + MAIN_RETRY_WAITS_MS.length);
    expect(MAIN_RETRY_WAITS_MS.length + 1).toBe(6);
    expect(wait.mock.calls.map((c) => c[0])).toEqual(MAIN_RETRY_WAITS_MS);
  });

  it('429 가 아닌 실패는 다시 시도하지 않음', async () => {
    quiet();
    const down = vi.fn(async () => new Response('down', { status: 503 }));
    expect(await fetchHeadlines(1, down as unknown as typeof fetch, noWait)).toEqual([]);
    expect(down).toHaveBeenCalledTimes(1);
  });

  it('JSON 이 아닌 안내문이나 계속 429 면 빈 배열', async () => {
    quiet();
    const text = async () => new Response('not json', { status: 200 });
    expect(await fetchHeadlines(1, text as unknown as typeof fetch, async () => {})).toEqual([]);
    const busy = async () => new Response('busy', { status: 429 });
    expect(await fetchHeadlines(1, busy as unknown as typeof fetch, async () => {})).toEqual([]);
  });

  describe('경제지표 기사 따로 검색', () => {
    const art = (title: string) => ({ url: `https://x.com/${encodeURIComponent(title)}`, title, domain: 'x.com' });
    /// 주요 검색과 지표 검색을 검색어로 구분해 다른 기사를 준다.
    const gdelt = (main: unknown, indicator: unknown) => vi.fn(async (url: string) => {
      const q = new URL(url).searchParams.get('query') ?? '';
      const body = q.includes('payrolls') ? indicator : main;
      return body instanceof Response ? body : jsonRes(body);
    });

    it('지표를 보는 날: 6초 쉬고 지표 기사를 뒤에 붙임(같은 제목은 뺌)', async () => {
      const f = gdelt(
        { articles: [art('Wall Street slumps'), art('Dow falls 500 points')] },
        { articles: [art('CPI rises in line with expectations'), art('Wall Street slumps')] },
      );
      const wait = vi.fn(async () => {});
      const out = await fetchHeadlines(1, f as unknown as typeof fetch, wait, { indicators: true });
      expect(out.map((h) => h.title)).toEqual(['Wall Street slumps', 'Dow falls 500 points', 'CPI rises in line with expectations']);
      expect(f).toHaveBeenCalledTimes(2);
      expect(wait).toHaveBeenCalledWith(GDELT_GAP_MS);
    });

    it('지표 기사는 최대 INDICATOR_LIMIT 개', async () => {
      const many = Array.from({ length: 20 }, (_, i) => art(`Payrolls report ${i}`));
      const f = gdelt({ articles: [art('Stocks rise')] }, { articles: many });
      const out = await fetchHeadlines(1, f as unknown as typeof fetch, noWait, { indicators: true });
      expect(out).toHaveLength(1 + INDICATOR_LIMIT);
    });

    it('지표를 안 보는 날(기본값)은 한 번만 검색', async () => {
      const f = gdelt({ articles: [art('Stocks rise')] }, { articles: [art('CPI hotter')] });
      const out = await fetchHeadlines(1, f as unknown as typeof fetch, noWait);
      expect(out.map((h) => h.title)).toEqual(['Stocks rise']);
      expect(f).toHaveBeenCalledTimes(1);
    });

    it('지표 검색만 실패하면 주요 기사는 그대로', async () => {
      quiet();
      const f = gdelt({ articles: [art('Stocks rise')] }, new Response('busy', { status: 500 }));
      const out = await fetchHeadlines(1, f as unknown as typeof fetch, noWait, { indicators: true });
      expect(out.map((h) => h.title)).toEqual(['Stocks rise']);
    });

    it('첫 검색이 막히면 지표 검색은 하지 않음', async () => {
      quiet();
      const busy = vi.fn(async () => new Response('busy', { status: 429 }));
      expect(await fetchHeadlines(1, busy as unknown as typeof fetch, noWait, { indicators: true })).toEqual([]);
      expect(busy).toHaveBeenCalledTimes(1 + MAIN_RETRY_WAITS_MS.length); // 첫 검색만 여러 번, 지표 검색은 안 함
    });

    it('지표 검색은 계속 막히면 최대 4번만 시도하고 주요 기사로 진행', async () => {
      quiet();
      const f = gdelt({ articles: [art('Stocks rise')] }, null);
      f.mockImplementation(async (url: string) => {
        const q = new URL(url).searchParams.get('query') ?? '';
        return q.includes('payrolls') ? new Response('busy', { status: 429 }) : jsonRes({ articles: [art('Stocks rise')] });
      });
      const out = await fetchHeadlines(1, f as unknown as typeof fetch, noWait, { indicators: true });
      expect(out.map((h) => h.title)).toEqual(['Stocks rise']);
      expect(f).toHaveBeenCalledTimes(1 + 1 + INDICATOR_RETRY_WAITS_MS.length);
    });
  });
});

describe('시장 숫자 줄', () => {
  it('크게 움직인 순서, 금리는 bp', () => {
    const lines = marketLines(data).map((x) => x.line);
    expect(lines[0]).toBe('나스닥 19800 -1.98% (2026-11-19)');
    expect(lines).toContain('미국 10년물 금리 5.04% -3bp (2026-11-19)');
    expect(lines).toContain('원/달러 환율 1430.5원 +0.40%');
  });

  it('비트코인 24시간 변동폭 4% 이상이면 큰 움직임(지금 등락률과 상관없이)', () => {
    const btc = (changePct: number, rangePct?: number) => ({ ...data, coins: [{ symbol: 'BTC', closeKrw: 1, changePct, rangePct }] });
    expect(isBigCryptoMove(data)).toBe(false);
    // −3% → +2%: 변동폭 5%, 지금은 +2%
    expect(isBigCryptoMove(btc(2, 5))).toBe(true);
    expect(isBigCryptoMove(btc(1.81, 4))).toBe(true);
    expect(isBigCryptoMove(btc(-3.9, 3.99))).toBe(false);
    // 변동폭을 못 받았으면 등락률 크기로
    expect(isBigCryptoMove(btc(-4.2))).toBe(true);
    expect(isBigCryptoMove(btc(-3.5))).toBe(false);
  });

  it('변동폭이 있으면 비트코인 줄에 함께 쓰고, 숫자 대비 문장에서는 뺀다', () => {
    const d = { ...data, markets: [], coins: [{ symbol: 'BTC', closeKrw: 1, changePct: 1.81, rangePct: 9.58 }] };
    expect(marketLines(d)[0].line).toBe('비트코인 +1.81% (업비트, 한국 시간 기준 하루 · 최근 24시간 변동폭 9.58%)');
    expect(numbersOnly(d)?.items[0].text).toBe('비트코인 +1.81%');
  });
});

describe('AI 지시문', () => {
  it('장이 열린 날: 대상 날짜, 숫자, 뉴스 제목이 들어감', () => {
    const plan = planIssue(new Date('2026-11-20T07:00:00+09:00'));
    const msgs = buildMessages(plan, data, [{ title: 'Nasdaq drops on Fed comments', url: 'u', domain: 'reuters.com', seenDate: '' }]);
    expect(msgs[0].content).toContain('가격이 먼저');
    expect(msgs[1].content).toContain('11/19 목 미국장');
    expect(msgs[1].content).toContain('나스닥 19800 -1.98%');
    expect(msgs[1].content).toContain('Nasdaq drops on Fed comments (reuters.com)');
    expect(msgs[1].content).not.toContain('keep');
  });

  it('미국 월요일 장은 놀라움을 보지 않는다고 알려 줌', () => {
    const plan = planIssue(new Date('2026-11-17T07:00:00+09:00'));
    expect(buildMessages(plan, data, [])[1].content).toContain('놀라움(경제지표)은 보지 않는다');
  });

  it('주말·휴장: 큰 일이 없으면 keep, 뉴스가 없으면 숫자만', () => {
    const plan = planIssue(new Date('2026-11-23T07:00:00+09:00'));
    const user = buildMessages(plan, data, [])[1].content;
    expect(user).toContain('{"keep":true}');
    expect(user).toContain('받은 뉴스 없음');
  });
});

describe('AI 답 검사', () => {
  it('올바른 답(생각 블록·앞뒤 글 무시)', () => {
    const { answer } = parseAiAnswer(`<think>음...</think>답입니다 ${good} 끝`, false);
    expect(answer).toMatchObject({ keep: false, headline: '금리 인하 기대 약화에 나스닥 하락' });
    expect(answer && !answer.keep && answer.items).toHaveLength(2);
  });

  it('keep 은 휴장·주말에만', () => {
    expect(parseAiAnswer('{"keep":true}', true).answer).toEqual({ keep: true });
    expect(parseAiAnswer('{"keep":true}', false)).toMatchObject({ answer: null, reason: '장이 열린 날인데 keep' });
  });

  it('투자 권유·단정 표현은 버림, 사실 표현은 통과', () => {
    const bad = good.replace('나스닥 하락"', '저가 매수 기회"');
    expect(parseAiAnswer(bad, false)).toMatchObject({ answer: null, reason: '금지 표현: 매수' });
    const sure = good.replace('내린 것으로 보임', '내렸기 때문이다');
    expect(parseAiAnswer(sure, false).reason).toBe('금지 표현: 때문이다');
    expect(findBanned('불확실성 확대에 S&P500 사상 최고가 경신 후 하락')).toBeNull();
  });

  it('형식이 틀리거나 너무 길면 버림', () => {
    expect(parseAiAnswer('요약할 수 없습니다', false).reason).toBe('JSON 없음');
    expect(parseAiAnswer('{"headline": ', false).reason).toBe('JSON 없음');
    expect(parseAiAnswer('{"keep":false,"headline":"x","items":[]}', false).reason).toBe('headline 또는 items 없음');
    const long = JSON.stringify({ keep: false, headline: '가'.repeat(41), items: [{ text: 'a', shortText: 'b' }] });
    expect(parseAiAnswer(long, false).reason).toBe('headline 너무 김');
  });

  it('Workers AI 응답 모양 여러 가지에서 글자 꺼내기', () => {
    expect(aiText('x')).toBe('x');
    expect(aiText({ response: 'y' })).toBe('y');
    expect(aiText({ choices: [{ message: { content: 'z' } }] })).toBe('z');
    expect(aiText({ response: { keep: true } })).toBe('{"keep":true}');
    expect(aiText(null)).toBe('');
  });

  it('숫자만: 크게 움직인 두 개', () => {
    // 비트코인(-1.20%)이 S&P500(-1.01%)보다 크게 움직였다. 괄호 속 날짜·출처는 뺀다.
    expect(numbersOnly(data)?.headline).toBe('나스닥 19800 -1.98% · 비트코인 -1.20%');
    expect(numbersOnly({ ...data, markets: [], coins: [], fx: {} })).toBeNull();
  });
});

/// KVNamespace 대신 쓰는 메모리 저장소.
function memoryKv() {
  const store = new Map<string, string>();
  return {
    store,
    get: async (key: string, type?: string) => {
      const v = store.get(key);
      return v == null ? null : type === 'json' ? JSON.parse(v) : v;
    },
    put: async (key: string, value: string) => void store.set(key, value),
  };
}

function env(kv = memoryKv()) {
  return {
    QUOTES: kv as unknown as KVNamespace,
    kv,
    FX_CODES: 'USD',
    ISSUE_COINS: 'BTC',
    EXIM_API_KEY: 'ek',
  } as unknown as Env & { kv: ReturnType<typeof memoryKv> };
}

/// 업비트·재무부·GDELT 를 흉내 낸다. FRED 키는 없음.
function routes(headlines: { title: string; url: string; domain: string }[]) {
  return vi.fn(async (url: string) => {
    if (url.includes('api.upbit.com')) {
      return jsonRes([{ candle_date_time_kst: '2026-11-19T09:00:00', trade_price: 130_000_000, change_rate: -0.012 }]);
    }
    if (url.includes('home.treasury.gov')) {
      return new Response(['2026-11-18', '2026-11-19'].map((d, i) =>
        `<m:properties><d:NEW_DATE>${d}T00:00:00</d:NEW_DATE><d:BC_10YEAR>${i ? '5.04' : '5.07'}</d:BC_10YEAR></m:properties>`).join(''));
    }
    if (url.includes('api.gdeltproject.org')) return jsonRes({ articles: headlines });
    return jsonRes({}, 404);
  });
}

const aiReturning = (content: string): AiRunner & { run: ReturnType<typeof vi.fn> } =>
  ({ run: vi.fn(async () => ({ choices: [{ message: { content } }] })) });

describe('하루 작업(runIssueJob)', () => {
  const thu7 = new Date('2026-11-20T07:00:00+09:00'); // 11/19 목 미국장
  const news = [{ title: 'Nasdaq slides as Fed dims rate-cut hopes', url: 'https://r.com/1', domain: 'r.com' }];

  it('AI 답이 좋으면 뉴스 기반 이슈 저장(출처 GDELT, 위젯 줄 = headline)', async () => {
    quiet();
    const e = env();
    const ai = aiReturning(good);
    const issue = await runIssueJob(e, thu7, { fetchFn: routes(news) as unknown as typeof fetch, wait: noWait, ai });
    expect(issue).toMatchObject({
      shortText: '금리 인하 기대 약화에 나스닥 하락', sample: false, basis: 'news',
      label: '11/19 목 미국장', date: '2026-11-19', credit: { name: 'GDELT Project' },
    });
    expect(issue?.sources?.[0].url).toBe('https://r.com/1');
    expect(JSON.parse(e.kv.store.get(ISSUE_KEY)!)).toEqual(issue);
    expect(ai.run.mock.calls[0][0]).toBe('@cf/google/gemma-4-26b-a4b-it');
  });

  it('AI 답이 금지 표현이면 숫자만 저장', async () => {
    quiet();
    const e = env();
    const issue = await runIssueJob(e, thu7, {
      fetchFn: routes(news) as unknown as typeof fetch, wait: noWait,
      ai: aiReturning(good.replace('나스닥 하락"', '매수 기회"')),
    });
    expect(issue).toMatchObject({ basis: 'numbers', label: '11/19 목 미국장' });
    expect(issue?.credit).toBeUndefined();
    expect(issue?.shortText).toContain('비트코인');
  });

  it('첫 모델이 폐기돼 오류면 다음 모델로', async () => {
    quiet();
    const run = vi.fn()
      .mockRejectedValueOnce(new Error('5028: deprecated'))
      .mockResolvedValueOnce({ response: good });
    const issue = await runIssueJob(env(), thu7, { fetchFn: routes(news) as unknown as typeof fetch, wait: noWait, ai: { run } });
    expect(issue?.basis).toBe('news');
    expect(run.mock.calls.map((c) => c[0])).toEqual(['@cf/google/gemma-4-26b-a4b-it', '@cf/zai-org/glm-4.7-flash']);
  });

  it('숫자만일 때 금리 등락(bp)도 남김', async () => {
    quiet();
    const issue = await runIssueJob(env(), thu7, { fetchFn: routes(news) as unknown as typeof fetch, wait: noWait });
    expect(issue?.items?.map((i) => i.text)).toContain('미국 10년물 금리 5.04% -3bp');
  });

  it('AI 가 없거나 오류여도 숫자만 저장', async () => {
    quiet();
    const broken: AiRunner = { run: async () => { throw new Error('quota'); } };
    for (const ai of [undefined, broken]) {
      const issue = await runIssueJob(env(), thu7, { fetchFn: routes(news) as unknown as typeof fetch, wait: noWait, ai });
      expect(issue?.basis).toBe('numbers');
    }
  });

  it('주말에 큰 일이 없으면(keep) 직전 요약 유지 + "기준" 표시', async () => {
    quiet();
    const e = env();
    e.kv.store.set(ISSUE_KEY, JSON.stringify({
      text: 't', shortText: '금요일 이슈', generatedAt: '2026-11-21T22:00:00Z', date: '2026-11-20', sample: false,
      label: '11/20 금 미국장', basis: 'news',
    }));
    const issue = await runIssueJob(e, new Date('2026-11-22T07:00:00+09:00'), {
      fetchFn: routes([]) as unknown as typeof fetch, ai: aiReturning('{"keep":true}'),
    });
    expect(issue).toMatchObject({
      shortText: '금요일 이슈', label: '11/20 금 미국장 기준', basis: 'kept',
      generatedAt: '2026-11-21T22:00:00Z', checkedAt: new Date('2026-11-22T07:00:00+09:00').toISOString(),
    });
  });

  it('주말에 비트코인 변동폭이 4% 이상이면 keep 을 받지 않고 새로 만든다(확인 시각 저장)', async () => {
    quiet();
    const e = env();
    e.kv.store.set(ISSUE_KEY, JSON.stringify({
      text: 't', shortText: '금요일 이슈', generatedAt: '2026-11-20T22:00:00Z', date: '2026-11-20', sample: false,
      label: '11/20 금 미국장', basis: 'news',
    }));
    const base = routes([]);
    // 24시간 동안 100 → 최저 97 → 최고 102 (변동폭 5%)
    const fetchFn = vi.fn(async (url: string) => url.includes('candles/minutes/60')
      ? jsonRes([
        { opening_price: 101, high_price: 102, low_price: 100 },
        { opening_price: 98, high_price: 101, low_price: 97 },
        { opening_price: 100, high_price: 100, low_price: 98 },
      ])
      : url.includes('candles/days')
        ? jsonRes([{ candle_date_time_kst: '2026-11-21T09:00:00', trade_price: 82_600_000, change_rate: 0.0181 }])
        : base(url));
    const sun7 = new Date('2026-11-22T07:00:00+09:00');
    const ai = aiReturning('{"keep":true}');
    const issue = await runIssueJob(e, sun7, { fetchFn: fetchFn as unknown as typeof fetch, ai });
    expect(issue?.basis).toBe('numbers');
    expect(issue?.checkedAt).toBe(sun7.toISOString());
    const prompt = ai.run.mock.calls[0][1].messages[1].content as string;
    expect(prompt).toContain('5.00% 범위로 크게 오르내렸다');
    expect(prompt).not.toContain('keep');
  });

  it('장이 열린 날 keep 이면 받아들이지 않고 숫자만', async () => {
    quiet();
    const issue = await runIssueJob(env(), thu7, {
      fetchFn: routes(news) as unknown as typeof fetch, wait: noWait, ai: aiReturning('{"keep":true}'),
    });
    expect(issue?.basis).toBe('numbers');
  });
});

describe('서버 연결', () => {
  it('7시 cron 은 이슈 작업, 매시 cron 은 환율', async () => {
    quiet();
    const e = env();
    const waits: Promise<unknown>[] = [];
    const ctx = { waitUntil: (p: Promise<unknown>) => waits.push(p) } as unknown as ExecutionContext;
    vi.stubGlobal('fetch', routes([]));
    // 평일 장이면 지표 검색 전 6초를 실제로 기다리므로 날짜를 일요일로 고정한다(Date 만 가짜).
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-11-22T07:00:00+09:00'));
    await worker.scheduled({ cron: ISSUE_CRON } as ScheduledController, e, ctx);
    await Promise.all(waits);
    expect(e.kv.store.has(ISSUE_KEY)).toBe(true);
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it('/issue/run 은 배포 주소에서는 404', async () => {
    const res = await worker.fetch(new Request('https://marketpeek-api.example.workers.dev/issue/run'), env());
    expect(res.status).toBe(404);
  });

  it('/quotes 와 /issue 는 실제 이슈만 내려줌(예시는 /quotes 에서 null)', async () => {
    const e = env();
    e.kv.store.set('fx', JSON.stringify({ updatedAt: new Date().toISOString(), data: {} }));
    let body = await (await worker.fetch(new Request('https://x.dev/quotes'), e)).json() as { issue: unknown };
    expect(body.issue).toBeNull();
    const sample = await (await worker.fetch(new Request('https://x.dev/issue'), e)).json() as { sample: boolean };
    expect(sample.sample).toBe(true);

    e.kv.store.set(ISSUE_KEY, JSON.stringify({ text: 't', shortText: 's', generatedAt: 'g', date: 'd', sample: false }));
    body = await (await worker.fetch(new Request('https://x.dev/quotes'), e)).json() as { issue: unknown };
    expect(body.issue).toMatchObject({ shortText: 's', sample: false });
  });
});
