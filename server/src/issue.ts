// AI 어제 이슈. 1단계에서는 고정된 예시 문장만 돌려준다(sample: true).
// 다음 단계에서 어제 코인·환율 등락을 모으고 AI 요약을 하루 1번 만들어 KV에 저장한다.
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
