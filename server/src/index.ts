// MarketPeek 시세 서버 진입점: 예약 실행(cron)으로 캐시를 채우고 GET /quotes로 캐시를 내려준다.
import { fetchFx, type FxQuote } from './eximbank';
import { fetchStocks, type StockQuote } from './finnhub';

export interface Env {
  QUOTES: KVNamespace;
  STOCK_TICKERS: string;
  FX_CODES: string;
  FINNHUB_API_KEY: string;
  EXIM_API_KEY: string;
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
    if (url.pathname !== '/quotes') return json({ error: 'not found' }, 404);

    let [stocks, fx] = await Promise.all([
      env.QUOTES.get<Cached<StockQuote>>('stocks', 'json'),
      env.QUOTES.get<Cached<FxQuote>>('fx', 'json'),
    ]);
    // 배포 직후 cron이 아직 안 돌았으면 한 번 직접 채운다.
    if (!stocks || !fx) ({ stocks, fx } = await refresh(env, new Date()));

    return json({
      stocks: pick(stocks?.data, list(url.searchParams.get('stocks'))),
      fx: pick(fx?.data, list(url.searchParams.get('fx'))),
      // AI 어제 이슈는 아직 없음. 생기면 { text, shortText, generatedAt }.
      issue: null,
      stocksUpdatedAt: stocks?.updatedAt ?? null,
      fxUpdatedAt: fx?.updatedAt ?? null,
    });
  },

  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(refresh(env, new Date()).then(() => undefined));
  },
};

/// 주식은 매번, 환율은 1시간이 지났을 때만 새로 받아 KV에 쓴다.
/// 일부 종목이 실패해도 이전 캐시 값은 남긴다(새 값으로 덮어쓰기만 함).
export async function refresh(
  env: Env,
  now: Date,
): Promise<{ stocks: Cached<StockQuote> | null; fx: Cached<FxQuote> | null }> {
  const [oldStocks, oldFx] = await Promise.all([
    env.QUOTES.get<Cached<StockQuote>>('stocks', 'json'),
    env.QUOTES.get<Cached<FxQuote>>('fx', 'json'),
  ]);

  let stocks = oldStocks;
  const fresh = await fetchStocks(list(env.STOCK_TICKERS), env.FINNHUB_API_KEY);
  if (Object.keys(fresh).length > 0) {
    stocks = { updatedAt: now.toISOString(), data: { ...oldStocks?.data, ...fresh } };
    await env.QUOTES.put('stocks', JSON.stringify(stocks));
  }

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
  }

  return { stocks, fx };
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
