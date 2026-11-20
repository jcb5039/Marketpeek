// AI 어제 이슈. 매일 한국 7시에 issueJob.ts 가 만들어 KV('issue')에 저장한다.
// 아직 한 번도 만들지 않았으면 고정된 예시 문장(sample: true)을 돌려준다.
// 문구는 "무엇이 왜 움직였는지"만 쓴다. 종목 추천·투자 권유로 읽힐 표현 금지.
import { kstDate } from './eximbank';

export interface Issue {
  /// 한 줄 요약 (위젯 사각형·홈).
  text: string;
  /// 더 짧은 요약 (위젯 한 줄).
  shortText: string;
  /// 요약을 만든 시각 (ISO 8601).
  generatedAt: string;
  /// 요약 대상 날짜, 한국 기준 어제 (YYYY-MM-DD).
  date: string;
  /// 예시 데이터면 true. 실제 요약이 생기면 false.
  sample: boolean;
  /// 제목 옆 기준 날짜. 예: "11/14 금 미국장", "주말", "11/20 금 미국장 기준"(직전 요약 유지).
  label?: string;
  /// 순위대로 최대 3개(앱 화면용). text·shortText 는 위젯용 1위 줄.
  items?: { text: string; shortText: string }[];
  /// news: 뉴스+숫자로 AI 요약, numbers: 숫자만, kept: 직전 요약 유지.
  basis?: 'news' | 'numbers' | 'kept';
  /// 뉴스를 썼으면 출처 표시(GDELT 약관상 필수)와 근거 기사 몇 개.
  credit?: { name: string; url: string };
  sources?: { title: string; url: string; domain: string }[];
}

export function sampleIssue(now: Date): Issue {
  const d = kstDate(now, 1);
  return {
    text: '(예시) 어제 비트코인은 미국 금리 동결 소식에 올랐어요.',
    shortText: '(예시) 비트코인, 금리 동결에 상승',
    generatedAt: now.toISOString(),
    date: `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`,
    sample: true,
  };
}
