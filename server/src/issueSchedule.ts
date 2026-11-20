// AI 어제 이슈 3단계 ⓑ: 오늘(한국 7시 실행) 무엇을 요약할지 정한다.
// 기준(형, 2026-11-20):
// - 화~토: 전날(미국 월~금) 미국장을 요약한다.
// - 일: 미국 토요일(휴장). 큰 일·코인 큰 움직임이 있으면 그것, 없으면 직전 요약 유지 + "금 미국장 기준" 표시.
// - 월: 주말. 큰 일·코인 큰 움직임이 있으면 그것, 없으면 "이번 주 주요 일정".
// - 미국 휴장일은 일요일처럼 처리한다.
// - 미국 월요일 장(한국 화요일 아침)은 경제지표 '놀라움' 기준을 건너뛴다.
// 외부 호출 없이 날짜 계산만 한다.

/// 미국 주식시장(NYSE·나스닥) 전일 휴장일. 출처: NYSE Group 2026·2027·2028 휴장일 발표(2025-12-23).
/// 조기 폐장(오후 1시)은 장이 열리므로 넣지 않는다. 새 해 목록은 해마다 추가한다.
export const US_MARKET_HOLIDAYS: ReadonlySet<string> = new Set([
  // 2026
  '2026-01-01', '2026-01-19', '2026-02-16', '2026-04-03', '2026-05-25',
  '2026-06-19', '2026-07-03', '2026-09-07', '2026-11-26', '2026-12-25',
  // 2027
  '2027-01-01', '2027-01-18', '2027-02-15', '2027-03-26', '2027-05-31',
  '2027-06-18', '2027-07-05', '2027-09-06', '2027-11-25', '2027-12-24',
]);

/// 휴장일 목록이 들어 있는 연도. 이 밖의 연도는 휴장일을 모른다(holidaysKnown: false).
export const HOLIDAY_YEARS: ReadonlySet<number> = new Set([2026, 2027]);

const WEEKDAYS = ['일', '월', '화', '수', '목', '금', '토'];

export type IssueMode =
  /// 전날 미국장이 열렸다: 고르는 기준(시장 반응 → 놀라움 → 오래 가는 영향) 그대로.
  | 'session'
  /// 전날 미국장이 휴장(토요일 또는 휴장일): 큰 일·코인 큰 움직임이 없으면 직전 요약을 유지한다.
  | 'closed'
  /// 한국 월요일 아침(주말): 큰 일·코인 큰 움직임이 없으면 이번 주 주요 일정을 보여 준다.
  | 'weekend';

export interface IssuePlan {
  mode: IssueMode;
  /// 한국 날짜(실행일), YYYY-MM-DD.
  kstDate: string;
  /// 요약 대상인 미국 날짜(한국 날짜 하루 전), YYYY-MM-DD.
  usDate: string;
  /// usDate 와 같거나 그 전의 가장 최근 미국장 날짜, YYYY-MM-DD.
  lastSessionDate: string;
  /// 새 이슈를 보여 줄 때 제목 옆 기준 날짜. 예: "11/14 금 미국장", "주말", "11/26 목 미국 휴장".
  label: string;
  /// 직전 요약을 유지할 때 기준 날짜. 예: "11/14 금 미국장 기준".
  fallbackLabel: string;
  /// 경제지표 예상치 대비 '놀라움'을 볼지. 미국 월요일 장과 휴장일·주말은 false.
  checkSurprise: boolean;
  /// 코인 큰 움직임(예: 비트코인 ±5%)을 따로 볼지. 휴장일·주말만 true.
  watchCryptoMove: boolean;
  /// 큰 일이 없을 때 이번 주 주요 일정을 보여 줄지(weekend 만 true).
  showWeekSchedule: boolean;
  /// 이 연도의 휴장일 목록이 있는지. false 면 US_MARKET_HOLIDAYS 를 채워야 한다.
  holidaysKnown: boolean;
}

/// 'YYYY-MM-DD' 를 UTC 자정 Date 로. 날짜 계산만 하므로 시간대는 상관없다.
function parseDay(day: string): Date {
  return new Date(`${day}T00:00:00Z`);
}

function formatDay(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function addDays(day: string, n: number): string {
  return formatDay(new Date(parseDay(day).getTime() + n * 86_400_000));
}

function weekday(day: string): number {
  return parseDay(day).getUTCDay();
}

/// 미국 주식시장이 그날 열렸는지(주말·휴장일이 아니면 열림).
export function isUsTradingDay(day: string): boolean {
  const w = weekday(day);
  return w !== 0 && w !== 6 && !US_MARKET_HOLIDAYS.has(day);
}

/// day 와 같거나 그 전의 가장 최근 미국장 날짜.
export function lastUsTradingDay(day: string): string {
  let d = day;
  // 연휴가 아무리 길어도 열흘 안에는 장이 열린다.
  for (let i = 0; i < 10 && !isUsTradingDay(d); i++) d = addDays(d, -1);
  return d;
}

/// "11/14 금" 처럼 월/일 요일.
export function shortDayLabel(day: string): string {
  const [, m, d] = day.split('-');
  return `${Number(m)}/${Number(d)} ${WEEKDAYS[weekday(day)]}`;
}

/// now 의 한국 날짜(YYYY-MM-DD).
export function kstDay(now: Date): string {
  return formatDay(new Date(now.getTime() + 9 * 3_600_000));
}

/// 한국 시간 now 에 실행했을 때 무엇을 요약할지.
export function planIssue(now: Date): IssuePlan {
  const kstDate = kstDay(now);
  const usDate = addDays(kstDate, -1);
  const lastSessionDate = lastUsTradingDay(usDate);
  const kstWeekday = weekday(kstDate);
  const fallbackLabel = `${shortDayLabel(lastSessionDate)} 미국장 기준`;
  const holidaysKnown = HOLIDAY_YEARS.has(parseDay(usDate).getUTCFullYear());

  const base = { kstDate, usDate, lastSessionDate, fallbackLabel, holidaysKnown };

  if (kstWeekday === 1) {
    // 한국 월요일 아침 = 미국 일요일. 주말 전체를 본다.
    return {
      ...base, mode: 'weekend', label: '주말',
      checkSurprise: false, watchCryptoMove: true, showWeekSchedule: true,
    };
  }
  if (isUsTradingDay(usDate)) {
    return {
      ...base, mode: 'session', label: `${shortDayLabel(usDate)} 미국장`,
      // 미국 월요일 장은 경제지표 발표가 드물어 '놀라움'을 건너뛴다.
      checkSurprise: weekday(usDate) !== 1, watchCryptoMove: false, showWeekSchedule: false,
    };
  }
  // 한국 일요일(미국 토요일) 또는 평일 휴장일.
  const label = weekday(usDate) === 6 ? '주말' : `${shortDayLabel(usDate)} 미국 휴장`;
  return {
    ...base, mode: 'closed', label,
    checkSurprise: false, watchCryptoMove: true, showWeekSchedule: false,
  };
}
