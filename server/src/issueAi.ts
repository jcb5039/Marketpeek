// AI 어제 이슈 3단계 ⓒ: AI 에게 줄 지시문, AI 답 검사, 숫자만 쓰는 대비 문장.
// 형 기준(11-20): 시장 반응 → 놀라움 → 오래 가는 영향 순, 상위 3개, 1·2위가 비슷하면 한 줄에 함께,
// 투자 권유 표현 금지, 원인 단정 금지("~ 영향으로 보임"). 형 피드백(11-19): 가격이 먼저, 원인이 불분명하면 숫자만.
import type { PriorIssue } from './issue';
import type { IssuePlan } from './issueSchedule';
import type { MarketMove } from './markets';
import type { Headline } from './news';
import type { YesterdayData } from './yesterday';

/// Workers AI 무료 플랜 다국어 모델. 앞에서부터 시도하고, 오류(모델 폐기 등)면 다음 모델로 넘어간다.
/// qwen3-30b-a3b-fp8 은 2026-11-20 폐기됨(오류 5028). glm-4.7-flash 는 생각(reasoning)에 토큰을 다 써서
/// 600 토큰으로는 답(content)이 비어 뒤로 뺐다. wrangler.toml 의 ISSUE_MODEL 로 맨 앞 모델을 바꿀 수 있다.
export const ISSUE_MODELS = ['@cf/google/gemma-4-26b-a4b-it', '@cf/zai-org/glm-4.7-flash'];

/// 비트코인 최근 24시간 변동폭(최고가 − 최저가)이 이만큼(%) 이상이면 휴장일·주말에도 이슈로 본다.
/// 등락률이 아니라 변동폭이다(−3% → +2% 면 5%). 최근 200일 업비트 기준 주말 변동폭 중간값 1.5%,
/// 4% 이상은 주말의 약 10%(한 달에 한 번꼴)라 4로 정했다(2026-11-23).
export const BIG_CRYPTO_MOVE_PCT = 4;

export interface IssueItem {
  /// 앱 화면용 한 문장.
  text: string;
  /// 위젯 한 줄용 짧은 문장.
  shortText: string;
}

export interface AiIssue {
  /// 위젯·라이브 액티비티 한 줄(1위, 비슷하면 1·2위를 " · " 로).
  headline: string;
  /// 순위대로 최대 3개.
  items: IssueItem[];
}

export type AiAnswer = { keep: true } | ({ keep: false } & AiIssue);

const LIMITS = { headline: 40, text: 90, shortText: 30 };

/// 투자 권유·단정으로 읽히는 표현. 하나라도 있으면 AI 답을 버린다.
export const BANNED = [
  // "사상 최고가", "불확실성" 같은 사실 표현은 막지 않도록 단어를 좁게 잡는다.
  '매수', '매도', '사세요', '파세요', '팔아', '추천', '기회', '주목할', '유망', '담아',
  '목표가', '진입', '반드시', '확실히', '확실하다', '틀림없', '때문이다', '때문입니다',
];

export function findBanned(s: string): string | null {
  return BANNED.find((w) => s.includes(w)) ?? null;
}

function fmtPct(n: number): string {
  return `${n > 0 ? '+' : ''}${n.toFixed(2)}%`;
}

/// AI 입력과 숫자 대비 문장에 쓰는 시장 숫자 줄. 크게 움직인 것부터.
export function marketLines(data: YesterdayData): { line: string; size: number }[] {
  const out: { line: string; size: number }[] = [];
  for (const m of data.markets) out.push({ line: moveLine(m), size: moveSize(m) });
  const btc = data.coins.find((c) => c.symbol === 'BTC');
  if (btc) {
    const range = btc.rangePct != null ? ` · 최근 24시간 변동폭 ${btc.rangePct.toFixed(2)}%` : '';
    out.push({ line: `비트코인 ${fmtPct(btc.changePct)} (업비트, 한국 시간 기준 하루${range})`, size: Math.abs(btc.changePct) });
  }
  const usd = data.fx.USD;
  if (usd) out.push({ line: `원/달러 환율 ${usd.rateKrw}원 ${fmtPct(usd.changePct)}`, size: Math.abs(usd.changePct) });
  return out.sort((a, b) => b.size - a.size);
}

function moveLine(m: MarketMove): string {
  if (m.changePct == null) {
    const bp = Math.round(m.change * 100);
    return `${m.name} ${m.close}% ${bp >= 0 ? '+' : ''}${bp}bp (${m.date})`;
  }
  return `${m.name} ${m.close} ${fmtPct(m.changePct)} (${m.date})`;
}

/// 움직임 크기를 대략 같은 눈금으로: 지수는 %, 금리는 0.1%p(10bp) 를 1% 로, VIX 는 너무 커서 1/5.
function moveSize(m: MarketMove): number {
  if (m.changePct == null) return Math.abs(m.change) * 10;
  return m.id === 'VIX' ? Math.abs(m.changePct) / 5 : Math.abs(m.changePct);
}

/// 비트코인 24시간 변동폭. 변동폭을 못 받았으면 등락률 크기로 대신한다. 비트코인이 없으면 null.
export function cryptoSwing(data: YesterdayData): number | null {
  const btc = data.coins.find((c) => c.symbol === 'BTC');
  if (!btc) return null;
  return btc.rangePct ?? Math.abs(btc.changePct);
}

export function isBigCryptoMove(data: YesterdayData): boolean {
  const swing = cryptoSwing(data);
  return swing != null && swing >= BIG_CRYPTO_MOVE_PCT;
}

const SYSTEM = `너는 장기 투자자를 위한 시장 요약 도우미다. 어제 시장이 "왜 움직였는지"를 한국어로 짧게 쓴다.
규칙:
1. 가격이 먼저다. 아래 '시장 숫자'에서 실제로 크게 움직인 시장을 찾고, 그 움직임을 설명하는 뉴스만 원인으로 쓴다.
2. 고르는 순서: ① 시장 반응(크게 움직인 시장과 그 이유) ② 놀라움(경제지표가 예상과 달랐다는 기사. 예상에 부합한 지표는 1위로 하지 않는다) ③ 오래 가는 영향(금리 경로·정책·전쟁 같은 일을 하루짜리 일보다 앞에).
3. 원인은 반드시 아래 '뉴스 제목'에 근거한다. 근거가 없으면 원인을 지어내지 말고 숫자만 쓴다(예: "나스닥 1.2% 하락, 뚜렷한 원인 보도 없음").
4. 원인을 단정하지 않는다. "~ 영향으로 보임", "~ 영향으로 풀이" 처럼 쓴다.
5. 금지: 투자 권유로 읽히는 말(매수, 매도, 기회, 추천, 주목할 종목, 저가, 바닥 등), 종목별 이야기, 확실·반드시 같은 단정.
6. 상위 최대 3개를 순위대로. headline 은 위젯 한 줄(${LIMITS.headline}자 이내): 1위, 1·2위가 비슷한 무게면 " · " 로 함께(예: "미중 회담 기대에 반등 · CPI 예상 부합"). text 는 ${LIMITS.text}자 이내 한 문장, shortText 는 ${LIMITS.shortText}자 이내.
7. JSON 만 출력한다: {"keep":false,"headline":"...","items":[{"text":"...","shortText":"..."}]}`;

/// AI 에게 보낼 메시지. keep 을 허용하는 날(휴장·주말)에는 큰 일이 없으면 {"keep":true} 로 답하게 한다.
export function buildMessages(plan: IssuePlan, data: YesterdayData, headlines: Headline[], prior?: PriorIssue) {
  const lines = marketLines(data).map((x) => `- ${x.line}`).join('\n') || '- (숫자 없음)';
  const news = headlines.length
    ? headlines.map((h) => `- ${h.title} (${h.domain})`).join('\n')
    : '- (받은 뉴스 없음: 원인을 쓰지 말고 숫자만 쓴다)';
  const day: string[] = [];
  if (plan.mode === 'session') {
    day.push(`대상: ${plan.label}.`);
    if (!plan.checkSurprise) day.push('미국 월요일 장이라 ② 놀라움(경제지표)은 보지 않는다.');
    // 지수 종가가 아직 안 올라온 날(issueJob 이 날짜 다른 숫자를 뺌): 뉴스의 장 마감 결과로 판단하게 한다.
    if (!data.markets.some((m) => m.id === 'SP500' || m.id === 'NASDAQ')) {
      day.push('미국 지수 종가(S&P500·나스닥)는 아직 받지 못했다. 뉴스 제목에 나온 장 마감 결과로 시장 반응을 판단하고, 장 시작 전 전망 기사는 결과로 쓰지 않는다.');
    }
  } else {
    const why = plan.mode === 'weekend' ? '주말' : `${plan.label}(미국장 휴장)`;
    day.push(`대상: ${why}. 미국 주식시장은 쉬었다.`);
    if (isBigCryptoMove(data)) {
      // 큰 움직임이면 유지를 허용하지 않는다(issueJob 도 keep 을 받지 않음).
      day.push(`비트코인이 최근 24시간 동안 ${cryptoSwing(data)!.toFixed(2)}% 범위로 크게 오르내렸다(최고가와 최저가 차이).`);
      day.push('이 움직임과 그 이유를 1위로 요약한다. 다른 큰 일이 있으면 함께 쓴다.');
    } else {
      day.push(`깜짝 발표·전쟁·정책 같은 큰 일이나 비트코인 24시간 변동폭(최고가와 최저가 차이) ${BIG_CRYPTO_MOVE_PCT}% 이상일 때만 요약한다.`);
      day.push('비트코인은 크게 움직이지 않았다.');
      day.push('그런 일이 없으면 {"keep":true} 만 출력한다.');
    }
  }
  if (prior) {
    // 뉴스는 24시간을 넓게 받으므로(장 전 코인·큰 뉴스도 잡으려고) 전날 이야기를 다룬 기사가 많이 섞인다.
    day.push(`직전 요약(${prior.label ?? prior.date}, 이미 알림): "${prior.text}".`
      + ' 이 일을 다룬 기사가 많아도 지난 일이니 다시 1위로 쓰지 않고, 그 뒤 새로 생긴 움직임과 뉴스를 쓴다.'
      + ' 단 같은 일이라도 새 전개(추가 급등락, 후속 발표, 반대 방향 움직임)가 있으면 그 새 전개를 쓴다.');
  }
  const user = `${day.join(' ')}\n\n시장 숫자(크게 움직인 순):\n${lines}\n\n뉴스 제목(영어, 출처 GDELT):\n${news}`;
  return [
    { role: 'system', content: SYSTEM },
    { role: 'user', content: user },
  ];
}

/// Workers AI 응답에서 글자만 꺼낸다(모델에 따라 문자열·response·choices 모양이 다르다).
export function aiText(out: unknown): string {
  if (typeof out === 'string') return out;
  const o = out as { response?: unknown; choices?: { message?: { content?: string } }[] };
  if (typeof o?.response === 'string') return o.response;
  if (o?.response && typeof o.response === 'object') return JSON.stringify(o.response);
  return o?.choices?.[0]?.message?.content ?? '';
}

/// AI 답을 검사한다. 형식이 틀리거나 길이를 넘거나 금지 표현이 있으면 이유와 함께 null.
export function parseAiAnswer(raw: string, allowKeep: boolean): { answer: AiAnswer | null; reason?: string } {
  const text = raw.replace(/<think>[\s\S]*?<\/think>/g, '');
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return { answer: null, reason: 'JSON 없음' };
  let o: Record<string, unknown>;
  try {
    o = JSON.parse(text.slice(start, end + 1));
  } catch {
    return { answer: null, reason: 'JSON 깨짐' };
  }
  if (o.keep === true) {
    return allowKeep ? { answer: { keep: true } } : { answer: null, reason: '장이 열린 날인데 keep' };
  }
  const headline = typeof o.headline === 'string' ? o.headline.trim() : '';
  const rawItems = Array.isArray(o.items) ? o.items : [];
  const items: IssueItem[] = [];
  for (const it of rawItems.slice(0, 3)) {
    const t = typeof it?.text === 'string' ? it.text.trim() : '';
    const s = typeof it?.shortText === 'string' ? it.shortText.trim() : '';
    if (!t || !s) return { answer: null, reason: '빈 항목' };
    items.push({ text: t, shortText: s });
  }
  if (!headline || items.length === 0) return { answer: null, reason: 'headline 또는 items 없음' };
  if (headline.length > LIMITS.headline) return { answer: null, reason: 'headline 너무 김' };
  for (const it of items) {
    if (it.text.length > LIMITS.text || it.shortText.length > LIMITS.shortText) return { answer: null, reason: '항목 너무 김' };
  }
  for (const s of [headline, ...items.flatMap((i) => [i.text, i.shortText])]) {
    const bad = findBanned(s);
    if (bad) return { answer: null, reason: `금지 표현: ${bad}` };
  }
  return { answer: { keep: false, headline, items } };
}

/// AI 를 못 쓰거나 답이 검사에서 떨어졌을 때: 원인 없이 숫자만(형 11-19 "원인이 불분명하면 숫자만").
/// 크게 움직인 두 개를 " · " 로. 숫자가 하나도 없으면 null.
export function numbersOnly(data: YesterdayData): AiIssue | null {
  const top = marketLines(data).slice(0, 2).map((x) => x.line.replace(/ \([^)]*\)$/, ''));
  if (top.length === 0) return null;
  const headline = top.join(' · ');
  return {
    headline: headline.length > LIMITS.headline ? top[0] : headline,
    items: top.map((t) => ({ text: t, shortText: t.length > LIMITS.shortText ? t.slice(0, LIMITS.shortText) : t })),
  };
}
