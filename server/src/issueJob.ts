// AI 어제 이슈 3단계 ⓒ: 매일 한국 7시(cron "0 22 * * *", UTC)에 한 번 이슈를 만들어 KV('issue')에 저장한다.
// 순서: 오늘 계획(issueSchedule) → 재료(시장 숫자·코인·환율) + 뉴스 제목(GDELT) → AI 요약 → 검사 → 저장.
// AI 가 실패하거나 검사에서 떨어지면 숫자만 저장한다. 휴장·주말에 큰 일이 없으면 직전 요약을 유지한다.
import type { Env } from './index';
import { collectYesterday } from './index';
import type { Issue } from './issue';
import { ISSUE_MODELS, aiText, buildMessages, isBigCryptoMove, numbersOnly, parseAiAnswer, type AiIssue } from './issueAi';
import { planIssue } from './issueSchedule';
import { GDELT_CREDIT, fetchHeadlines, type Headline } from './news';

export const ISSUE_KEY = 'issue';
export const ISSUE_CRON = '0 22 * * *';

/// Workers AI 바인딩 중 쓰는 부분만(테스트에서 바꿔 끼우기 쉽게).
export interface AiRunner {
  run(model: string, inputs: {
    messages: { role: string; content: string }[];
    max_tokens?: number;
    chat_template_kwargs?: { enable_thinking?: boolean };
  }): Promise<unknown>;
}

export interface IssueJobDeps {
  fetchFn?: typeof fetch;
  ai?: AiRunner;
  /// 테스트용: GDELT 429 재시도·두 번째 검색 전 대기.
  wait?: (ms: number) => Promise<unknown>;
}

export async function runIssueJob(env: Env, now: Date, deps: IssueJobDeps = {}): Promise<Issue | null> {
  const fetchFn = deps.fetchFn ?? fetch;
  const ai = deps.ai ?? (env.AI as unknown as AiRunner | undefined);
  const plan = planIssue(now);
  if (!plan.holidaysKnown) console.warn(`미국 휴장일 목록에 ${plan.usDate.slice(0, 4)}년이 없음(issueSchedule.ts)`);

  const [data, headlines, prev] = await Promise.all([
    collectYesterday(env, now, fetchFn),
    // 경제지표를 보는 날(화~금 미국장)에만 지표 기사를 따로 더 받는다.
    fetchHeadlines(plan.mode === 'weekend' ? 2 : 1, fetchFn, deps.wait, { indicators: plan.checkSurprise }),
    env.QUOTES.get<Issue>(ISSUE_KEY, 'json'),
  ]);
  // 장이 열린 날과 코인이 크게 오르내린 날은 직전 요약을 유지하지 않는다.
  const allowKeep = plan.mode !== 'session' && !isBigCryptoMove(data);

  let result: AiIssue | null = null;
  let basis: Issue['basis'] = 'numbers';
  if (ai) {
    try {
      const out = await runFirstWorking(ai, modelsFor(env), buildMessages(plan, data, headlines));
      const { answer, reason } = parseAiAnswer(aiText(out), allowKeep);
      if (answer?.keep) {
        if (prev && !prev.sample) {
          // 유지해도 확인 시각은 남겨서 오늘 작업이 돌았는지 알 수 있게 한다.
          const kept: Issue = { ...prev, label: plan.fallbackLabel, basis: 'kept', checkedAt: now.toISOString() };
          await env.QUOTES.put(ISSUE_KEY, JSON.stringify(kept));
          return kept;
        }
        // 유지할 직전 요약이 없으면 숫자로 넘어간다.
      } else if (answer) {
        result = answer;
        basis = headlines.length ? 'news' : 'numbers';
      } else {
        // 원인을 보려고 앞부분만 남긴다(입력·키는 남기지 않음).
        console.warn(`AI 답 버림: ${reason} | ${JSON.stringify(out).slice(0, 400)}`);
      }
    } catch (e) {
      console.warn(`AI 실패: ${String(e)}`);
    }
  } else {
    console.warn('AI 바인딩 없음: 숫자만 저장');
  }

  result ??= numbersOnly(data);
  if (!result) return null;

  const issue: Issue = {
    text: result.items[0].text,
    shortText: result.headline,
    generatedAt: now.toISOString(),
    checkedAt: now.toISOString(),
    date: plan.lastSessionDate,
    sample: false,
    label: plan.mode === 'session' || basis !== 'numbers' ? plan.label : plan.fallbackLabel,
    items: result.items,
    basis,
    ...(basis === 'news' ? { credit: GDELT_CREDIT, sources: topSources(headlines) } : {}),
  };
  await env.QUOTES.put(ISSUE_KEY, JSON.stringify(issue));
  return issue;
}

/// 맨 앞에 env.ISSUE_MODEL 을 두고 기본 목록을 잇는다(중복 제거).
export function modelsFor(env: Env): string[] {
  return [...new Set([env.ISSUE_MODEL, ...ISSUE_MODELS].filter((m): m is string => !!m))];
}

/// 모델을 차례로 시도해 처음 성공한 응답을 돌려준다. 모두 실패하면 마지막 오류를 던진다.
async function runFirstWorking(ai: AiRunner, models: string[], messages: { role: string; content: string }[]) {
  let last: unknown;
  for (const m of models) {
    try {
      // Gemma 4 등은 '생각'이 기본으로 켜져 있어 토큰을 다 쓰고 답(content)이 비기도 한다 → 끈다.
      // 그래도 생각하는 모델이 답을 끝낼 수 있게 넉넉히(하루 1번이라 뉴런 부담 작음).
      return await ai.run(m, { messages, max_tokens: 2500, chat_template_kwargs: { enable_thinking: false } });
    } catch (e) {
      console.warn(`AI 모델 ${m} 실패: ${String(e)}`);
      last = e;
    }
  }
  throw last;
}

function topSources(h: Headline[]): Issue['sources'] {
  return h.slice(0, 5).map(({ title, url, domain }) => ({ title, url, domain }));
}
