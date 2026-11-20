// AI 어제 이슈 요일·휴장일 판단 테스트. 날짜 계산만 하므로 외부 호출이 없다.
import { describe, expect, it } from 'vitest';
import {
  HOLIDAY_YEARS, US_MARKET_HOLIDAYS, isUsTradingDay, kstDay, lastUsTradingDay, planIssue, shortDayLabel,
} from '../src/issueSchedule';

/// 한국 시간 그날 아침 7시(cron 실행 시각).
const at7 = (kst: string) => new Date(`${kst}T07:00:00+09:00`);

describe('planIssue: 요일별 처리', () => {
  it('한국 화요일 = 미국 월요일 장, 놀라움은 건너뜀', () => {
    const p = planIssue(at7('2026-11-17'));
    expect(p).toMatchObject({
      mode: 'session', kstDate: '2026-11-17', usDate: '2026-11-16', lastSessionDate: '2026-11-16',
      label: '11/16 월 미국장', checkSurprise: false, watchCryptoMove: false,
    });
  });

  it('한국 수~토 = 전날 미국장, 놀라움까지 봄', () => {
    for (const [kst, us, label] of [
      ['2026-11-18', '2026-11-17', '11/17 화 미국장'],
      ['2026-11-19', '2026-11-18', '11/18 수 미국장'],
      ['2026-11-20', '2026-11-19', '11/19 목 미국장'],
      ['2026-11-21', '2026-11-20', '11/20 금 미국장'],
    ]) {
      expect(planIssue(at7(kst))).toMatchObject({ mode: 'session', usDate: us, label, checkSurprise: true });
    }
  });

  it('한국 일요일 = 미국 토요일 휴장, 직전 금요일 장 기준', () => {
    expect(planIssue(at7('2026-11-22'))).toMatchObject({
      mode: 'closed', usDate: '2026-11-21', lastSessionDate: '2026-11-20',
      label: '주말', fallbackLabel: '11/20 금 미국장 기준',
      checkSurprise: false, watchCryptoMove: true,
    });
  });

  it('한국 월요일 = 주말, 주말 뉴스·코인 움직임으로 요약(이번 주 일정 없음)', () => {
    expect(planIssue(at7('2026-11-23'))).not.toHaveProperty('showWeekSchedule');
    expect(planIssue(at7('2026-11-23'))).toMatchObject({
      mode: 'weekend', usDate: '2026-11-22', lastSessionDate: '2026-11-20',
      label: '주말', fallbackLabel: '11/20 금 미국장 기준',
      checkSurprise: false, watchCryptoMove: true,
    });
  });
});

describe('planIssue: 미국 휴장일은 일요일처럼', () => {
  it('추수감사절(목) 다음 날 아침은 휴장, 수요일 장 기준', () => {
    expect(planIssue(at7('2026-11-27'))).toMatchObject({
      mode: 'closed', usDate: '2026-11-26', lastSessionDate: '2026-11-25',
      label: '11/26 목 미국 휴장', fallbackLabel: '11/25 수 미국장 기준', watchCryptoMove: true,
    });
  });

  it('추수감사절 다음 날(조기 폐장)은 장이 열린 날', () => {
    expect(planIssue(at7('2026-11-28'))).toMatchObject({ mode: 'session', label: '11/27 금 미국장' });
  });

  it('월요일 휴장(MLK)은 한국 화요일에 휴장 처리, 직전 금요일 기준', () => {
    expect(planIssue(at7('2026-01-20'))).toMatchObject({
      mode: 'closed', usDate: '2026-01-19', fallbackLabel: '1/16 금 미국장 기준',
    });
  });

  it('성금요일(금) 휴장은 한국 토요일에 휴장 처리', () => {
    expect(planIssue(at7('2026-04-04'))).toMatchObject({
      mode: 'closed', label: '4/3 금 미국 휴장', fallbackLabel: '4/2 목 미국장 기준',
    });
  });

  it('연말·연초 경계: 2027-01-01(금) 휴장이면 2026-12-31 장 기준', () => {
    expect(planIssue(at7('2027-01-02'))).toMatchObject({
      mode: 'closed', usDate: '2027-01-01', lastSessionDate: '2026-12-31',
      fallbackLabel: '12/31 목 미국장 기준',
    });
  });

  it('휴장일 목록이 없는 연도는 holidaysKnown: false', () => {
    expect(planIssue(at7('2026-11-18')).holidaysKnown).toBe(true);
    expect(planIssue(at7('2028-01-05')).holidaysKnown).toBe(false);
  });
});

describe('날짜 도우미', () => {
  it('cron 시각(UTC 22:00)은 다음 날 한국 7시', () => {
    expect(kstDay(new Date('2026-11-17T22:00:00Z'))).toBe('2026-11-18');
    expect(planIssue(new Date('2026-11-17T22:00:00Z')).usDate).toBe('2026-11-17');
  });

  it('한국 자정 경계', () => {
    expect(kstDay(new Date('2026-11-17T14:59:59Z'))).toBe('2026-11-17');
    expect(kstDay(new Date('2026-11-17T15:00:00Z'))).toBe('2026-11-18');
  });

  it('장이 열린 날 판단과 직전 장 찾기', () => {
    expect(isUsTradingDay('2026-11-20')).toBe(true); // 금
    expect(isUsTradingDay('2026-11-21')).toBe(false); // 토
    expect(isUsTradingDay('2026-12-25')).toBe(false); // 크리스마스
    expect(lastUsTradingDay('2026-11-22')).toBe('2026-11-20');
    expect(lastUsTradingDay('2026-12-27')).toBe('2026-12-24'); // 금 휴장 + 주말
  });

  it('짧은 날짜 문구', () => {
    expect(shortDayLabel('2026-11-14')).toBe('11/14 토');
    expect(shortDayLabel('2026-01-05')).toBe('1/5 월');
  });

  it('휴장일 목록: 연도마다 10일, 모두 평일', () => {
    for (const y of HOLIDAY_YEARS) {
      const days = [...US_MARKET_HOLIDAYS].filter((d) => d.startsWith(`${y}-`));
      expect(days).toHaveLength(10);
      for (const d of days) expect([0, 6]).not.toContain(new Date(`${d}T00:00:00Z`).getUTCDay());
    }
  });
});
