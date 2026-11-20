# MarketPeek 시세 서버

Cloudflare Workers 무료 플랜에서 돌아가는 시세 서버입니다. 카드 등록 없이 쓸 수 있습니다.

- 1시간마다 한국수출입은행에서 환율을 받아 KV에 캐시합니다.
- 앱은 `GET /quotes?fx=USD,JPY`로 캐시된 값만 읽습니다. API 키는 서버에만 있습니다.
- 코인은 앱이 업비트에서 직접 받습니다.
- 주식(국내·미국)은 앱이 한국투자증권 Open API에서 사용자 키로 직접 받습니다 (키 신청: 저장소 루트 `key.md`).
  KIS 주소는 포트 9443을 쓰는데 Cloudflare Workers는 배포 환경에서 사용자 지정 포트를 무시해서 서버에서 부를 수 없습니다.
  예전에 쓰던 Finnhub는 재배포 금지 약관 때문에 뺐습니다.

## 처음 한 번 설정

1. cloudflare.com에 가입합니다(무료, 카드 불필요).
2. 키를 발급받습니다.
   - 한국수출입은행 환율: https://www.koreaexim.go.kr → 환율 Open API 인증키 신청
3. 이 폴더에서 아래를 실행합니다.

```sh
cd server
npm install
npx wrangler login                      # 브라우저로 Cloudflare 로그인
npx wrangler kv namespace create QUOTES # 출력된 id를 wrangler.toml의 REPLACE_WITH_KV_ID 자리에 붙여넣기
npx wrangler secret put EXIM_API_KEY    # 키 붙여넣기 (화면에 안 보임)
npx wrangler secret put FRED_API_KEY    # (선택) AI 이슈용 S&P500·나스닥·VIX. FRED 무료 키
npm run deploy                          # 출력된 https://marketpeek-api.<계정>.workers.dev 주소를 기억
```

4. 확인합니다.

```sh
curl 'https://marketpeek-api.<계정>.workers.dev/quotes?fx=USD,JPY'
```

## 앱에서 쓰기

서버 주소를 빌드할 때 넣습니다. 넣지 않으면 앱은 환율에 예시 값을 씁니다.

```sh
flutter run --dart-define=API_BASE_URL=https://marketpeek-api.<계정>.workers.dev
```

## 개발

```sh
npm test            # 단위 테스트 (외부 API는 부르지 않음)
npm run typecheck
cp .dev.vars.example .dev.vars   # 로컬 키 입력 (git에 안 올라감)
npm run dev         # http://localhost:8787, 예약 실행은 curl 'localhost:8787/__scheduled'로 직접 실행
```

## 무료 플랜 한도

- 요청 하루 10만 회. 넘으면 막힐 뿐 과금되지 않습니다.
- KV 쓰기 하루 1,000회. 지금 설정은 하루 약 49회입니다(1시간마다 환율 1회 + 환율 기록 1회 + 한국 7시 AI 이슈 1회). cron 간격을 바꿀 때 확인하세요.
- Workers AI 하루 10,000 뉴런. AI 이슈는 하루 1번이라 수십 뉴런 정도입니다.
- 수출입은행은 하루 1,000회입니다. 환율 기록은 1시간에 최대 6회(오늘 1 + 지난 날짜 5) 더 부릅니다.

## 응답 형식

> 앱에서 쓰는 모든 주소·필드·화면 표시 규칙은 **[`API.md`](API.md)(서버 API 설명서)** 에 정리되어 있습니다. 아래는 요약입니다.

```json
{
  "fx": { "USD": { "rateKrw": 1430.5, "changePct": 0.4 }, "JPY": { "rateKrw": 950.0, "changePct": -0.2 } },
  "issue": null,
  "fxUpdatedAt": "2026-11-06T06:00:00.000Z"
}
```

- `fx.JPY`는 100엔 기준입니다. 위안화(CNY)는 수출입은행의 CNH 고시 값입니다.
- `issue`(AI 어제 이슈)는 한국 7시 작업이 실제로 만든 요약이 있을 때만 들어가고, 아직 없으면 `null`입니다(예시 문장은 넣지 않음). 형식은 아래 `GET /issue`.

### `GET /fx/history?code=USD&days=30` (환율 차트용 기록)

```json
{ "code": "USD", "points": [{ "date": "2026-10-08", "rate": 1398.2 }, { "date": "2026-11-18", "rate": 1430.5 }] }
```

- 최근 영업일(고시가 있던 날) 환율을 오래된 것부터 줍니다. `days`는 2~40, 기본 30.
- cron이 1시간마다 오늘 환율을 다시 받고, 기록에 없는 지난 날짜를 5일씩 채웁니다(KV `fx:history`, 45일 보관).
  처음 배포한 뒤 30일치가 모이기까지 몇 시간 걸립니다.

### `GET /issue` (AI 어제 이슈)

매일 한국 7시(cron `0 22 * * *`)에 만들어 KV `issue`에 저장한 요약입니다. 아직 한 번도 만들지 않았으면 예시(`sample: true`)를 줍니다.

```json
{
  "text": "…다우 지수가 급락하는 등 미 증시가 하락세를 보인 영향으로 풀이됩니다.",
  "shortText": "미 증시 급락 · 비트코인 하락",
  "generatedAt": "2026-11-19T22:00:05.000Z",
  "date": "2026-11-19",
  "sample": false,
  "label": "11/19 목 미국장",
  "items": [{ "text": "…", "shortText": "…" }],
  "basis": "news",
  "credit": { "name": "GDELT Project", "url": "https://www.gdeltproject.org/" },
  "sources": [{ "title": "Wall Street Slump Continues as Dow Falls Over 1,100 Points", "url": "https://…", "domain": "…" }]
}
```

- 위젯·라이브 액티비티는 `shortText`(1위 한 줄, 1·2위가 비슷하면 " · "로 함께), 앱은 `items`(최대 3개)를 씁니다. 제목 옆에는 `label`.
- `date`는 요약한 미국장 날짜입니다. 휴장·주말에 큰 일이 없으면 직전 요약을 유지하고 `label`이 "11/20 금 미국장 기준"처럼 바뀝니다(`basis: "kept"`).
- `basis`: `news`(뉴스 + 숫자로 AI 요약), `numbers`(AI 실패·뉴스 없음 등으로 숫자만), `kept`(직전 요약 유지).
- **`basis`가 `news`면 `credit`(GDELT Project + 링크)을 화면에 표시해야 합니다(GDELT 이용 조건).**
- 문구는 "무엇이 왜 움직였는지"만 씁니다. 투자 권유·단정 표현이 있으면 서버가 AI 답을 버리고 숫자만 저장합니다.
- 뉴스는 GDELT 영어 기사 제목만 씁니다. 네이버 검색 API는 약관(검색 API 특약 2.3)이 AI 입력을 금지해 쓰지 않습니다.
- AI 모델은 `src/issueAi.ts`의 `ISSUE_MODELS` 순서로 시도합니다(앞 모델이 폐기되면 다음 모델). `wrangler.toml`에 `ISSUE_MODEL`을 넣으면 그 모델을 먼저 씁니다.

### `GET /issue/run` (이슈 바로 만들기, 로컬 전용)

7시 작업을 지금 한 번 돌려 결과를 돌려줍니다(AI 호출과 로컬 KV 저장 포함). `npm run dev`에서만 열립니다.
Workers AI 는 로컬에서도 실제 Cloudflare 계정을 쓰므로 `npx wrangler login` 이 필요합니다. 20초~1분쯤 걸립니다.

### `GET /issue/data` (이슈 재료, 로컬 전용)

AI 요약의 재료인 한국 기준 어제의 주요 코인 등락(업비트 일봉)과 캐시된 환율 등락입니다.
요청마다 업비트를 부르므로 `npm run dev`(localhost)에서만 열리고, 배포된 서버에서는 404입니다.

```json
{
  "date": "2026-11-15",
  "coins": [{ "symbol": "BTC", "closeKrw": 89949000, "changePct": 1.23 }],
  "fx": { "USD": { "rateKrw": 1430.5, "changePct": 0.4 } },
  "fxUpdatedAt": "2026-11-16T00:30:00.000Z",
  "markets": [{ "id": "US10Y", "name": "미국 10년물 금리", "close": 5.04, "change": -0.03, "changePct": null, "…": "…" }]
}
```

- 코인 목록은 `wrangler.toml`의 `ISSUE_COINS`입니다. 받지 못한 코인은 빠집니다.
- 업비트 일봉은 한국 시간 09:00~다음 날 09:00이 하루라, 오전 9시 전에는 어제 봉이 아직 진행 중입니다.
- 환율은 수출입은행 최근 영업일 기준이라 주말·공휴일 다음 날에는 어제 값이 아닐 수 있습니다. 로컬에서 환율 키(`.dev.vars`)가 없으면 비어 있습니다.
