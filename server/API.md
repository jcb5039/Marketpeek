# MarketPeek 서버 API 설명서

앱·위젯이 MarketPeek 시세 서버(Cloudflare Workers)에서 받을 수 있는 값을 정리한 문서입니다.
배포·설정 방법과 무료 플랜 한도는 [`README.md`](README.md)에 있습니다.

> 기준: PR #16(AI 어제 이슈 3단계) 코드. 코드가 바뀌면 이 문서도 함께 고칩니다.

## 한눈에 보기

| 주소 | 하는 일 | 어디서 |
|---|---|---|
| [`GET /quotes`](#get-quotes) | 환율 + AI 어제 이슈를 한 번에 | 앱·위젯 (주로 이것) |
| [`GET /issue`](#get-issue) | AI 어제 이슈만 | 앱·확인용 |
| [`GET /fx/history`](#get-fxhistory) | 환율 차트용 날짜별 기록 | 앱·위젯 차트 |
| [`GET /health`](#get-health) | 서버가 살아 있는지 | 확인용 |
| [`GET /issue/data`](#로컬-전용-주소) | 이슈 재료(시장 숫자·코인·환율) | **로컬 전용** |
| [`GET /issue/run`](#로컬-전용-주소) | 이슈를 지금 바로 만들어 보기 | **로컬 전용** |

### 공통
- 주소: `https://marketpeek-api.<계정>.workers.dev` (앱은 `--dart-define=API_BASE_URL=...` 로 받습니다).
- 모두 `GET` 이고 로그인·키가 필요 없습니다. 응답은 `application/json; charset=utf-8`.
- 다른 방식(`POST` 등)은 `405 {"error":"method not allowed"}`, 없는 주소는 `404 {"error":"not found"}`.
- 서버는 미리 받아 둔 값(KV 캐시)만 돌려주므로 응답이 빠르고, 앱이 자주 불러도 외부 API 를 부르지 않습니다.
  예외: 배포 직후 환율 캐시가 비어 있으면 `/quotes` 첫 요청에서 한 번 채웁니다.

## 값이 바뀌는 시각

| 무엇 | 언제 | 출처 |
|---|---|---|
| 환율 (`fx`) | 매시 정각에 확인, 실제 값은 영업일 하루 몇 번 고시 | 한국수출입은행 |
| 환율 기록 (`/fx/history`) | 매시 정각 (오늘 + 비어 있는 지난 날짜 5일씩) | 한국수출입은행 |
| AI 어제 이슈 (`issue`) | **매일 한국 7시 1번** (cron `0 22 * * *`, UTC) | GDELT 뉴스 + 시장 숫자 + Workers AI |

- 이슈는 하루 한 번만 바뀌므로 위젯이 자주 다시 받을 필요가 없습니다(지금 위젯은 2시간 간격 요청).
- 코인 시세는 서버를 거치지 않고 앱·위젯이 업비트에서 직접, 주식은 사용자 증권사(KIS) 키로 기기에서 직접 받습니다.

---

## `GET /quotes`

환율과 AI 어제 이슈를 한 번에 줍니다. 앱·위젯은 보통 이 주소 하나만 부릅니다.

**쿼리**

| 이름 | 예 | 설명 |
|---|---|---|
| `fx` | `USD,JPY,EUR` | 받을 통화 코드(쉼표로 구분, 대소문자 무관). 서버가 모르는 코드는 조용히 빠집니다. 없으면 `fx` 는 `{}`. |

지원 통화(22개, `wrangler.toml` `FX_CODES`): USD, JPY, EUR, CNY, THB, GBP, CHF, CAD, AUD, NZD, HKD, SGD, IDR, MYR, BND, AED, SAR, KWD, BHD, SEK, NOK, DKK

**응답**

```json
{
  "fx": {
    "USD": { "rateKrw": 1430.5, "changePct": 0.4 },
    "JPY": { "rateKrw": 950.0, "changePct": -0.2 }
  },
  "issue": { "text": "…", "shortText": "미 증시 급락 · 비트코인 하락", "generatedAt": "2026-11-19T22:00:05.000Z", "…": "아래 Issue 참고" },
  "fxUpdatedAt": "2026-11-20T06:00:00.000Z"
}
```

| 필드 | 타입 | 설명 |
|---|---|---|
| `fx` | `{ [코드]: FxQuote }` | 요청한 통화 중 서버에 있는 것만 |
| `fx.*.rateKrw` | number | 원화 값. **JPY·IDR 은 100 단위**(100엔 = 950원). CNY 는 수출입은행의 CNH(역외 위안) 고시 값 |
| `fx.*.changePct` | number | 전 영업일 대비 등락률(%) |
| `issue` | `Issue` \| `null` | AI 어제 이슈. **실제로 만든 요약이 있을 때만** 들어가고, 아직 없으면 `null`(예시 문장은 넣지 않음) |
| `fxUpdatedAt` | string \| `null` | 서버가 환율을 마지막으로 받은 시각(ISO 8601, UTC). 캐시가 없으면 `null` |

---

## `GET /issue`

AI 어제 이슈만 줍니다. `/quotes` 의 `issue` 와 같은 값이지만, 아직 한 번도 만들지 않았으면 **예시 문장**(`sample: true`)을 줍니다(확인용).

### Issue

```json
{
  "text": "앤스로픽의 IPO가 AI 관련주 상승을 이끌지 못하면서 다우 지수가 급락하는 등 미 증시가 하락세를 보인 영향으로 풀이됩니다.",
  "shortText": "미 증시 급락 · 비트코인 하락",
  "generatedAt": "2026-11-19T22:00:05.000Z",
  "date": "2026-11-19",
  "sample": false,
  "label": "11/19 목 미국장",
  "items": [
    { "text": "앤스로픽의 IPO가 … 영향으로 풀이됩니다.", "shortText": "AI 관련주 반등 실패 영향" },
    { "text": "비트코인 1.83% 하락, 뚜렷한 원인 보도 없음", "shortText": "비트코인 1.83% 하락" }
  ],
  "basis": "news",
  "credit": { "name": "GDELT Project", "url": "https://www.gdeltproject.org/" },
  "sources": [
    { "title": "Wall Street Slump Continues as Dow Falls Over 1,100 Points", "url": "https://…", "domain": "wflanews.iheart.com" }
  ]
}
```
(2026-11-20 로컬에서 실제로 만든 결과)

| 필드 | 타입 | 항상? | 설명 |
|---|---|---|---|
| `text` | string | ✅ | 1위 한 문장(90자 이내). 앱 화면용 |
| `shortText` | string | ✅ | **위젯·라이브 액티비티 한 줄**(40자 이내). 1위, 1·2위가 비슷하면 `" · "` 로 함께 |
| `generatedAt` | string | ✅ | 만든 시각(ISO 8601, UTC) |
| `date` | string | ✅ | 요약한 미국장 날짜(`YYYY-MM-DD`, 미국 기준) |
| `sample` | boolean | ✅ | 예시면 `true`. `/quotes` 에는 `false` 만 옵니다 |
| `label` | string | 실제 요약만 | **제목 옆 기준 날짜**. 아래 표 |
| `items` | `{text, shortText}[]` | 실제 요약만 | 순위대로 최대 3개. **앱 화면에서 3개 모두** 보여 줄 때 |
| `basis` | `"news"` \| `"numbers"` \| `"kept"` | 실제 요약만 | 어떻게 만들었는지. 아래 표 |
| `credit` | `{name, url}` | `basis: "news"` 일 때 | **화면에 표시해야 함**(GDELT 이용 조건) |
| `sources` | `{title, url, domain}[]` | `basis: "news"` 일 때 | 근거가 된 뉴스 최대 5개(영어 제목). 앱에서 "근거 기사" 링크로 쓸 수 있음 |

앱에 이미 있는 `MarketIssue`(`text`·`shortText`·`generatedAt`)는 그대로 동작합니다. 나머지는 모두 **추가된 필드**라 없을 수도 있다고 보고 읽어 주세요.

### `label` 예

| 한국 아침 7시 | `label` | 뜻 |
|---|---|---|
| 화 | `11/16 월 미국장` | 전날 미국장 요약 |
| 수~토 | `11/20 금 미국장` | 전날 미국장 요약 |
| 일 | `주말` | 주말 큰 일·비트코인 ±5% 이상이 있어 새로 요약 |
| 월 | `주말` | 주말 뉴스 요약 |
| 미국 휴장일 다음 날 | `11/26 목 미국 휴장` | 휴장일에 큰 일이 있어 새로 요약 |
| 휴장·주말에 큰 일 없음 | `11/20 금 미국장 기준` | 직전 요약을 그대로 유지(`basis: "kept"`) |

미국 휴장일은 NYSE 공식 발표(2026·2027)를 서버에 적어 두었습니다(`src/issueSchedule.ts`).

### `basis`

| 값 | 언제 | 화면 |
|---|---|---|
| `news` | 뉴스 제목 + 시장 숫자로 AI 가 요약 | `credit` 표시 필수 |
| `numbers` | AI 실패, AI 답에 금지 표현, 뉴스를 못 받음 → **원인 없이 숫자만** (예: `나스닥 19800 -1.98% · 비트코인 -1.20%`) | 그대로 |
| `kept` | 휴장·주말에 큰 일이 없어 직전 요약 유지 | `label` 에 "기준" 이 붙음 |

### 문구 원칙 (서버가 지킴)
- "무엇이 왜 움직였는지" 만 씁니다. 원인은 단정하지 않고 "~ 영향으로 보임/풀이" 로 씁니다.
- 투자 권유·단정 표현(매수, 매도, 기회, 추천, 주목할, 유망, 목표가, 반드시, 때문이다 …)이 있으면 서버가 AI 답을 버리고 숫자만 저장합니다.
- 종목별 이야기는 하지 않습니다(시장 전체만).

### 화면 표시 예시
```
[어제 이슈]  11/19 목 미국장
미 증시 급락 · 비트코인 하락          ← shortText (위젯·라이브 액티비티)

1. 앤스로픽의 IPO가 … 영향으로 풀이됩니다.   ← items (앱)
2. 비트코인 1.83% 하락, 뚜렷한 원인 보도 없음
출처: GDELT Project                      ← credit (basis 가 news 일 때)
```

### Dart 에서 읽기 (예)
```dart
final issue = body['issue'] as Map<String, dynamic>?;
if (issue != null) {
  final label = issue['label'] as String?;                     // 없을 수 있음
  final items = (issue['items'] as List?)
          ?.map((e) => (e as Map<String, dynamic>)['text'] as String)
          .toList() ??
      [issue['text'] as String];                               // 없으면 text 하나
  final credit = issue['credit'] as Map<String, dynamic>?;      // basis == 'news' 일 때만
  final creditName = credit?['name'] as String?;               // "GDELT Project"
}
```

---

## `GET /fx/history`

환율 차트용 날짜별 기록입니다.

**쿼리**

| 이름 | 예 | 설명 |
|---|---|---|
| `code` | `USD` | 통화 코드 1개(필수). 없으면 `400 {"error":"code required"}` |
| `days` | `30` | 최근 영업일 몇 개(2~40, 기본 30) |

**응답**
```json
{ "code": "USD", "points": [{ "date": "2026-10-08", "rate": 1398.2 }, { "date": "2026-11-18", "rate": 1430.5 }] }
```
- 고시가 있던 날만, 오래된 것부터. `rate` 단위는 `/quotes` 의 `rateKrw` 와 같습니다(JPY·IDR 100 단위).
- 처음 배포한 뒤 30일치가 모이기까지 몇 시간 걸립니다(매시 5일씩 채움).

## `GET /health`
```json
{ "ok": true }
```

---

## 로컬 전용 주소

`npm run dev`(localhost)에서만 열리고, 배포된 서버에서는 `404` 입니다. 요청마다 외부 API·AI 를 부르기 때문입니다.

### `GET /issue/data` — 이슈 재료
AI 에게 넘기는 숫자들입니다.
```json
{
  "date": "2026-11-19",
  "coins": [{ "symbol": "BTC", "closeKrw": 130000000, "changePct": -1.83 }],
  "fx": { "USD": { "rateKrw": 1430.5, "changePct": 0.4 } },
  "fxUpdatedAt": "2026-11-20T06:00:00.000Z",
  "markets": [
    { "id": "US10Y", "name": "미국 10년물 금리", "date": "2026-11-19", "close": 5.04,
      "prevDate": "2026-11-18", "prevClose": 5.07, "change": -0.03, "changePct": null }
  ]
}
```
- `coins`: `wrangler.toml` `ISSUE_COINS`(BTC, ETH, XRP, SOL, DOGE) 의 한국 기준 어제 업비트 일봉 등락.
- `markets`: 미국 10년물(미 재무부, 키 없음) + S&P500·나스닥·VIX(FRED, `FRED_API_KEY` 가 있을 때만). 금리는 `changePct` 가 `null` 이고 `change` 가 %p(−0.03 = −3bp).

### `GET /issue/run` — 이슈 지금 만들기
7시 작업을 바로 한 번 돌려 만든 `Issue` 를 돌려주고 로컬 KV 에 저장합니다. 20초~1분쯤 걸립니다.
Workers AI 는 로컬에서도 실제 Cloudflare 계정을 쓰므로 `npx wrangler login` 이 필요합니다.

---

## 데이터 출처와 표시 의무

| 데이터 | 출처 | 표시 |
|---|---|---|
| 환율 | 한국수출입은행 Open API | — |
| 뉴스 제목 | [GDELT Project](https://www.gdeltproject.org/) | **필수**: `credit` (이름 + 링크) |
| 미국 10년물 금리 | 미 재무부 Daily Treasury Par Yield Curve | — |
| S&P500·나스닥·VIX | FRED(세인트루이스 연준). 교육용 | — |
| 요약 문장 | Cloudflare Workers AI (Gemma 4 26B, 실패 시 GLM 4.7 Flash) | — |

네이버 검색 API 는 약관(검색 API 특약 2.3)이 "데이터를 AI에 입력"하는 것을 금지해 쓰지 않습니다.
