// AI 어제 이슈 3단계 ⓒ: 전날 큰 뉴스 제목을 GDELT 에서 받는다.
// 네이버 검색 API 는 약관(검색 API 특약 2.3)이 "데이터를 AI에 입력"하는 것을 금지해서 쓰지 않는다(2026-11-20 확인).
// GDELT 는 학술·상업 포함 무료·무제한, 조건은 "GDELT Project" 출처 표시와 https://www.gdeltproject.org/ 링크.
// 본문은 받지 않고 기사 제목·링크·매체만 쓴다. 영어 기사 제목을 AI 가 한국어로 요약한다.

export interface Headline {
  title: string;
  url: string;
  domain: string;
  /// GDELT 가 기사를 본 시각(UTC, YYYYMMDDTHHMMSSZ).
  seenDate: string;
}

export const GDELT_CREDIT = { name: 'GDELT Project', url: 'https://www.gdeltproject.org/' } as const;

/// 시장 전체 흐름(거시 이슈)만 찾는다. 종목별 뉴스는 쓰지 않는다(형 기준).
/// GDELT 는 괄호 안 OR 를 한 단계만 지원한다(중첩 불가).
export const GDELT_QUERY =
  '(stocks OR "wall street" OR nasdaq OR "s&p 500" OR "dow jones" OR "federal reserve" OR'
  + ' treasury OR inflation OR bitcoin OR tariffs) sourcelang:english';

/// 경제지표 발표 기사만 따로 찾는다(형 기준 ② 놀라움: "CPI 예상 부합" 같은 표현).
/// 위 검색어에 단어만 더하면 그날 큰 뉴스(지수 급락 기사 수십 개)에 밀려 60개 안에 하나도 안 들어왔다(2026-11-21 실제 검색).
/// "than expected" 는 넣지 않는다: 기업 실적 기사(종목 뉴스)까지 끌려온다. 예상 숫자는 쓰지 않고 제목의 말만 쓴다.
export const INDICATOR_QUERY =
  '(cpi OR "consumer prices" OR "jobs report" OR payrolls) sourcelang:english';

/// 지표 기사는 주요 기사 뒤에 이만큼까지만 붙인다.
export const INDICATOR_LIMIT = 8;

/// GDELT 는 "5초에 1번" 제한이 있다. 두 번째 검색 전에 이만큼 쉰다.
export const GDELT_GAP_MS = 6_000;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

interface GdeltArticle {
  url?: string;
  title?: string;
  domain?: string;
  seendate?: string;
}

/// GDELT 제목은 문장부호 앞에 띄어쓰기가 들어가 있다("Dow Falls 1 , 100 Points", "S & P 500").
/// 라디오 방송국들이 같은 기사를 "제목 | 방송국 이름" 으로 다시 싣기도 해서 뒤의 " | ..." 를 뗀다.
export function cleanTitle(raw: string): string {
  return raw
    .replace(/\s+/g, ' ')
    .replace(/\s+\|.*$/, '')
    .replace(/\s+([,.:;!?%])/g, '$1')
    .replace(/(\d), (\d{3})\b/g, '$1,$2')
    .replace(/(\d)\. (\d)/g, '$1.$2')
    .replace(/\bS & P\b/g, 'S&P')
    .trim();
}

/// GDELT 응답에서 제목이 있는 기사만, 같은 제목(다듬은 뒤)은 하나만 남긴다.
export function parseGdelt(body: unknown, limit = 25): Headline[] {
  const arts = (body as { articles?: GdeltArticle[] })?.articles ?? [];
  const seen = new Set<string>();
  const out: Headline[] = [];
  for (const a of arts) {
    const title = cleanTitle(a.title ?? '');
    const key = title.toLowerCase();
    if (!title || !a.url || seen.has(key)) continue;
    seen.add(key);
    out.push({ title, url: a.url, domain: a.domain ?? '', seenDate: a.seendate ?? '' });
    if (out.length >= limit) break;
  }
  return out;
}

type Wait = (ms: number) => Promise<unknown>;

/// GDELT 검색 한 번. 429 면 6초 뒤 한 번만 다시 시도하고, 끝내 실패하면 null.
async function searchGdelt(
  query: string, days: number, maxrecords: number, limit: number, fetchFn: typeof fetch, wait: Wait, what: string,
): Promise<Headline[] | null> {
  const url = 'https://api.gdeltproject.org/api/v2/doc/doc'
    + `?query=${encodeURIComponent(query)}&mode=artlist&format=json&maxrecords=${maxrecords}`
    + `&timespan=${days}d&sort=hybridrel`;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetchFn(url);
      if (res.status === 429 && attempt === 0) {
        await wait(GDELT_GAP_MS);
        continue;
      }
      if (!res.ok) throw new Error(`gdelt ${res.status}`);
      // GDELT 는 가끔 JSON 이 아닌 안내문을 돌려준다.
      const text = await res.text();
      return parseGdelt(JSON.parse(text), limit);
    } catch (e) {
      console.warn(`${what} failed: ${String(e)}`);
      return null;
    }
  }
  console.warn(`${what} failed: gdelt 429`);
  return null;
}

/// 최근 days 일 큰 뉴스 제목. 끝내 실패하면 빈 배열(그때는 숫자만으로 요약한다).
/// indicators 가 true 면(경제지표를 보는 날) 6초 쉬고 지표 기사를 따로 받아 뒤에 붙인다(같은 제목은 뺌).
/// 첫 검색이 실패하면 GDELT 가 막고 있는 것이라 지표 검색은 하지 않는다. 지표 검색만 실패하면 주요 기사만 쓴다.
export async function fetchHeadlines(
  days: number,
  fetchFn: typeof fetch = fetch,
  wait: Wait = sleep,
  { indicators = false }: { indicators?: boolean } = {},
): Promise<Headline[]> {
  const main = await searchGdelt(GDELT_QUERY, days, 60, 25, fetchFn, wait, 'headlines');
  if (!main) return [];
  if (!indicators) return main;

  await wait(GDELT_GAP_MS);
  const extra = await searchGdelt(INDICATOR_QUERY, days, 30, INDICATOR_LIMIT, fetchFn, wait, 'indicator headlines');
  const seen = new Set(main.map((h) => h.title.toLowerCase()));
  return [...main, ...(extra ?? []).filter((h) => !seen.has(h.title.toLowerCase()))];
}
