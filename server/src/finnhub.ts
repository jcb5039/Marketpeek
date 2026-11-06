// Finnhub에서 미국주식 현재가·전일 대비 등락률을 받아온다.

export interface StockQuote {
  priceUsd: number;
  changePct: number;
}

/// 티커마다 한 번씩 호출한다(Finnhub quote는 단건 API).
/// 실패하거나 값이 없는 티커(잘못된 티커는 c=0으로 옴)는 결과에서 빠진다.
export async function fetchStocks(
  tickers: string[],
  apiKey: string,
  fetchFn: typeof fetch = fetch,
): Promise<Record<string, StockQuote>> {
  const entries = await Promise.all(
    tickers.map(async (ticker): Promise<[string, StockQuote] | null> => {
      try {
        const url = `https://finnhub.io/api/v1/quote?symbol=${encodeURIComponent(ticker)}&token=${apiKey}`;
        const res = await fetchFn(url);
        if (!res.ok) {
          console.warn(`finnhub ${ticker}: HTTP ${res.status}`);
          return null;
        }
        const q = (await res.json()) as { c?: number; dp?: number | null };
        if (!q.c || q.dp == null) return null;
        return [ticker, { priceUsd: q.c, changePct: q.dp }];
      } catch (e) {
        console.warn(`finnhub ${ticker}: ${e}`);
        return null;
      }
    }),
  );
  return Object.fromEntries(entries.filter((e): e is [string, StockQuote] => e !== null));
}
