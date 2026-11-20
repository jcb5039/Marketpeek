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

/// 최근 days 일 큰 뉴스 제목. GDELT 는 "5초에 1번" 제한이 있어 429 면 6초 뒤 한 번만 다시 시도한다.
/// 끝내 실패하면 빈 배열(그때는 숫자만으로 요약한다).
export async function fetchHeadlines(
  days: number,
  fetchFn: typeof fetch = fetch,
  wait: (ms: number) => Promise<unknown> = sleep,
): Promise<Headline[]> {
  const url = 'https://api.gdeltproject.org/api/v2/doc/doc'
    + `?query=${encodeURIComponent(GDELT_QUERY)}&mode=artlist&format=json&maxrecords=60`
    + `&timespan=${days}d&sort=hybridrel`;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetchFn(url);
      if (res.status === 429 && attempt === 0) {
        await wait(6_000);
        continue;
      }
      if (!res.ok) throw new Error(`gdelt ${res.status}`);
      // GDELT 는 가끔 JSON 이 아닌 안내문을 돌려준다.
      const text = await res.text();
      return parseGdelt(JSON.parse(text));
    } catch (e) {
      console.warn(`headlines failed: ${String(e)}`);
      return [];
    }
  }
  console.warn('headlines failed: gdelt 429');
  return [];
}
