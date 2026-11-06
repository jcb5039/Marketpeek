# MarketPeek 시세 서버

Cloudflare Workers 무료 플랜에서 돌아가는 시세 서버입니다. 카드 등록 없이 쓸 수 있습니다.

- 5분마다 Finnhub에서 미국주식 시세를 받아 KV에 캐시합니다.
- 1시간마다 한국수출입은행에서 환율을 받아 KV에 캐시합니다.
- 앱은 `GET /quotes?stocks=TSLA,NVDA&fx=USD,JPY`로 캐시된 값만 읽습니다. API 키는 서버에만 있습니다.
- 코인은 앱이 업비트에서 직접 받으므로 이 서버에는 없습니다.

## 처음 한 번 설정

1. cloudflare.com에 가입합니다(무료, 카드 불필요).
2. 키를 발급받습니다.
   - Finnhub: https://finnhub.io 가입 → Dashboard의 API key
   - 한국수출입은행 환율: https://www.koreaexim.go.kr → 환율 Open API 인증키 신청
3. 이 폴더에서 아래를 실행합니다.

```sh
cd server
npm install
npx wrangler login                      # 브라우저로 Cloudflare 로그인
npx wrangler kv namespace create QUOTES # 출력된 id를 wrangler.toml의 REPLACE_WITH_KV_ID 자리에 붙여넣기
npx wrangler secret put FINNHUB_API_KEY # 키 붙여넣기 (화면에 안 보임)
npx wrangler secret put EXIM_API_KEY
npm run deploy                          # 출력된 https://marketpeek-api.<계정>.workers.dev 주소를 기억
```

4. 확인합니다.

```sh
curl 'https://marketpeek-api.<계정>.workers.dev/quotes?stocks=TSLA&fx=USD,JPY'
```

## 앱에서 쓰기

서버 주소를 빌드할 때 넣습니다. 넣지 않으면 앱은 미국주식·환율에 예시 값을 씁니다.

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
- KV 쓰기 하루 1,000회. 지금 설정은 하루 약 312회입니다(주식 288회 + 환율 24회). cron 간격이나 종목 수를 바꿀 때 확인하세요.
- 실행 한 번에 외부 호출 50회. 종목은 한 번에 1회씩 부르므로 `STOCK_TICKERS`는 40개 이하로 유지하세요.
- Finnhub 무료 플랜은 분당 60회, 수출입은행은 하루 1,000회입니다.

## 응답 형식

```json
{
  "stocks": { "TSLA": { "priceUsd": 450.0, "changePct": 3.1 } },
  "fx": { "USD": { "rateKrw": 1430.5, "changePct": 0.4 }, "JPY": { "rateKrw": 950.0, "changePct": -0.2 } },
  "issue": null,
  "stocksUpdatedAt": "2026-11-06T06:00:00.000Z",
  "fxUpdatedAt": "2026-11-06T06:00:00.000Z"
}
```

- `fx.JPY`는 100엔 기준입니다. 위안화(CNY)는 수출입은행의 CNH 고시 값입니다.
- `issue`(AI 어제 이슈)는 아직 구현되지 않아 항상 `null`입니다.
