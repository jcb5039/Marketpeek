// MarketPeek 시세 서버 진입점: 예약 실행(cron)으로 환율 캐시를 채우고 GET /quotes로 내려준다.
// GET /issue는 AI 어제 이슈(지금은 예시 문장). GET /fx/history는 환율 차트용 날짜별 기록.
// 주식 시세는 앱이 한국투자증권 Open API에서 사용자 키로 직접 받는다 (Finnhub는 재배포 금지라 제거).
import { fetchFx, kstDate, type FxQuote } from './eximbank';
import { HISTORY_KEY, historyPoints, updateHistory, type FxHistory } from './fxHistory';
import { sampleIssue } from './issue';
import { fetchMarketMoves } from './markets';
import { dashed, fetchCoinMoves, type YesterdayData } from './yesterday';

export interface Env {
  QUOTES: KVNamespace;
  FX_CODES: string;
  /// AI 어제 이슈 재료로 쓸 코인 (업비트 원화 마켓 심볼).
  ISSUE_COINS: string;
  EXIM_API_KEY: string;
  /// FRED 무료 API 키(S&P500·나스닥·VIX). 없으면 그 지수들은 건너뛴다.
  FRED_API_KEY?: string;
}

interface Cached<T> {
  updatedAt: string;
  data: Record<string, T>;
}

/// 수출입은행은 하루 한 번 고시하므로 1시간에 한 번만 다시 받는다.
const FX_REFRESH_MS = 60 * 60 * 1000;

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    if (req.method !== 'GET') return json({ error: 'method not allowed' }, 405);
    if (url.pathname === '/health') return json({ ok: true });
    if (url.pathname === '/issue') return json(sampleIssue(new Date()));
    if (url.pathname === '/fx/history') {
      const code = list(url.searchParams.get('code'))[0];
      if (!code) return json({ error: 'code required' }, 400);
      const days = Math.min(Math.max(Number(url.searchParams.get('days')) || 30, 2), 40);
      const h = await env.QUOTES.get<FxHistory>(HISTORY_KEY, 'json');
      return json({ code, points: historyPoints(h, code, days) });
    }
    // 이슈 재료 확인용. 요청마다 업비트를 부르므로 로컬(npm run dev)에서만 연다.
    if (url.pathname === '/issue/data') {
      if (!isLocal(url)) return json({ error: 'not found' }, 404);
      return json(await collectYesterday(env, new Date()));
    }
    if (url.pathname !== '/quotes') return json({ error: 'not found' }, 404);

    let fx = await env.QUOTES.get<Cached<FxQuote>>('fx', 'json');
    // 배포 직후 cron이 아직 안 돌았으면 한 번 직접 채운다.
    if (!fx) ({ fx } = await refresh(env, new Date()));

    return json({
      fx: pick(fx?.data, list(url.searchParams.get('fx'))),
      // AI 어제 이슈는 아직 예시뿐이라(GET /issue) 앱·위젯에 진짜처럼 뜨지 않게 null로 둔다.
      // 실제 요약이 생기면 { text, shortText, generatedAt }.
      issue: null,
      fxUpdatedAt: fx?.updatedAt ?? null,
    });
  },

  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(refresh(env, new Date()).then(() => undefined));
  },
};

/// 환율은 1시간이 지났을 때만 새로 받아 KV에 쓴다.
/// 일부 통화가 실패해도 이전 캐시 값은 남긴다(새 값으로 덮어쓰기만 함).
export async function refresh(env: Env, now: Date): Promise<{ fx: Cached<FxQuote> | null }> {
  const oldFx = await env.QUOTES.get<Cached<FxQuote>>('fx', 'json');

  let fx = oldFx;
  const fxAge = oldFx ? now.getTime() - Date.parse(oldFx.updatedAt) : Infinity;
  if (fxAge >= FX_REFRESH_MS) {
    try {
      const data = await fetchFx(list(env.FX_CODES), env.EXIM_API_KEY, now);
      if (Object.keys(data).length > 0) {
        fx = { updatedAt: now.toISOString(), data: { ...oldFx?.data, ...data } };
        await env.QUOTES.put('fx', JSON.stringify(fx));
      }
    } catch (e) {
      console.warn(`fx refresh failed: ${e}`);
    }
    // 차트용 날짜별 기록도 같은 주기(1시간)로 갱신한다. KV 쓰기는 하루 24회 더해 48회.
    try {
      const old = await env.QUOTES.get<FxHistory>(HISTORY_KEY, 'json');
      const h = await updateHistory(old, list(env.FX_CODES), env.EXIM_API_KEY, now);
      await env.QUOTES.put(HISTORY_KEY, JSON.stringify(h));
    } catch (e) {
      console.warn(`fx history failed: ${e}`);
    }
  }

  return { fx };
}

/// AI 어제 이슈 재료: 어제 주요 코인 등락(업비트) + 캐시된 환율 등락(새로 받지 않음)
/// + 전날 미국 시장 반응(FRED 지수, 미 재무부 10년물).
export async function collectYesterday(
  env: Env,
  now: Date,
  fetchFn: typeof fetch = fetch,
): Promise<YesterdayData> {
  const [coins, fx, markets] = await Promise.all([
    fetchCoinMoves(list(env.ISSUE_COINS), now, fetchFn),
    env.QUOTES.get<Cached<FxQuote>>('fx', 'json'),
    fetchMarketMoves(env.FRED_API_KEY, now, fetchFn),
  ]);
  return {
    date: dashed(kstDate(now, 1)),
    coins,
    fx: fx?.data ?? {},
    fxUpdatedAt: fx?.updatedAt ?? null,
    markets,
  };
}

function isLocal(url: URL): boolean {
  return url.hostname === 'localhost' || url.hostname === '127.0.0.1';
}

function list(csv: string | null | undefined): string[] {
  return (csv ?? '')
    .split(',')
    .map((s) => s.trim().toUpperCase())
    .filter(Boolean);
}

function pick<T>(data: Record<string, T> | undefined, keys: string[]): Record<string, T> {
  if (!data) return {};
  return Object.fromEntries(keys.filter((k) => k in data).map((k) => [k, data[k]]));
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}
