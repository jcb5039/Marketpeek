# MarketPeek

iOS 잠금화면 위젯 중심 시세 앱. 코인 · 미국주식 · 선택형 환율 · AI 어제 이슈를 **서로 독립된 4종 위젯**으로 보여준다.
기획서: "시세 위젯 앱 기획서 (환율 선택 반영본, 2026.11.01)".

## 최우선 원칙: 위젯이 제품이다
- 앱은 "위젯에 무엇을 어떻게 보여줄지" 설정하는 도구다. 앱 화면 기능을 늘리기 전에 위젯에서 어떻게 보일지부터 판단한다.
- 앱의 모든 설정 변경은 `AppState` → `WidgetSync.push()`로 위젯 스냅샷 갱신까지 이어져야 한다.
- 잠금화면 위젯은 보통 단색(vibrant)으로 렌더링된다. 등락은 색만으로 구분하지 말고 ▲▼ 기호를 함께 쓴다.
- 위젯 갱신 시점은 iOS가 정한다. "실시간", "N분마다" 같은 보장 표현 금지. 마지막 갱신 시각을 표시한다.

## 제품 규칙 (기획서에서 자주 헷갈리는 부분)
- 코인과 미국주식은 목록·위젯 모두 분리. 하나의 관심종목 위젯에 섞지 않는다.
- 미국주식은 USD 가격 + KRW 환산가를 함께 보여준다. **원화 환산은 환율 위젯에서 고른 통화와 무관하게 항상 USD/KRW.**
- 환율 위젯 통화는 사용자가 선택 (USD/JPY/EUR/THB/CNY). JPY는 100단위 표기.
- 상승·하락 색: 한국식(상승 빨강/하락 파랑, 기본) · 해외식(상승 초록/하락 빨강).
- AI 이슈는 전날 시장 이슈 한 줄 요약만. 종목 추천·투자 권유로 읽힐 표현 금지.
- 이번 버전 제외: 초 단위 실시간, 김프 위젯, 국내주식, 계좌 연동, AI 종목 추천, 라이브 액티비티.

## 구조
```
lib/
  models/models.dart            도메인 모델
  data/catalog.dart             검색 가능한 코인·종목·통화 목록 (서버 연결 전 하드코딩)
  data/quote_repository.dart    QuoteRepository 인터페이스 + MockQuoteRepository (기획서 예시값, 실제 시세 아님)
  data/upbit_quote_repository.dart   코인: 업비트 공개 API (키 없음). 나머지는 fallback에 위임
  data/server_quote_repository.dart  미국주식·환율·AI 이슈: 우리 서버(server/) GET /quotes
  state/app_state.dart          설정·목록·시세 상태 (ChangeNotifier, shared_preferences 저장)
  widget_bridge/widget_sync.dart  App Group에 위젯 스냅샷 JSON 쓰기 + 타임라인 리로드
  util/format.dart              가격·환율·등락률 표기
  util/market_hours.dart        미국장 상태 (Swift MarketHours.swift와 같은 규칙)
  ui/                           홈/검색/환율/위젯 안내/설정 화면 (다크 테마, lib/app/theme.dart)
ios/MarketPeekWidget/           WidgetKit 확장 (SwiftUI). Widgets.swift에 4종 위젯 + 번들
server/                         시세 서버 (Cloudflare Workers 무료 플랜, TypeScript). 설정 방법은 server/README.md
```
- 앱 시세 구성(`main.dart`): `UpbitQuoteRepository(fallback: ServerQuoteRepository 또는 MockQuoteRepository)`.
  서버 주소는 `--dart-define=API_BASE_URL=...`로 넣고, 없으면 미국주식·환율·이슈는 예시 값.

### Flutter ↔ 위젯 데이터 계약
- App Group: `group.com.yoonhyukju.marketpeek`, 키 `snapshot` (JSON 문자열).
- 스키마는 `widget_sync.dart`의 `buildSnapshot`과 `Snapshot.swift`가 같이 정의한다. 한쪽을 바꾸면 다른 쪽도 고치고 `schemaVersion`을 올린다.
- 위젯 kind (`CoinWidget`, `StockWidget`, `FxWidget`, `IssueWidget`)는 Dart `widgetKinds`와 Swift 정의가 일치해야 한다.
- 현재 위젯은 앱이 쓴 스냅샷만 읽는다. 서버(server/) 연결 후에는 위젯 타임라인에서 직접 받아오도록 바꿀 예정.

## 명령
- `flutter analyze` / `flutter test`
- 서버: `cd server && npm test` / `npm run typecheck` / `npm run dev` / `npm run deploy`
- `flutter build ios --simulator --debug` → `xcrun simctl install booted build/ios/iphonesimulator/Runner.app`
- 잠금화면 위젯은 시뮬레이터/실기기에서 직접 추가해서 확인해야 한다 (자동 검증 불가).

## 주의
- iOS 최소 버전 16.0 (잠금화면 위젯 요구사항).
- Runner의 "Embed Foundation Extensions" 단계는 "Thin Binary"보다 앞에 있어야 한다 (뒤에 있으면 빌드 사이클 오류).
- 위젯 타깃은 Flutter/Debug·Release.xcconfig를 base config로 써서 앱과 같은 버전(FLUTTER_BUILD_NAME/NUMBER)을 갖는다.
- 번들 ID `com.yoonhyukju.marketpeek`, 서명은 개인 팀(5R86F56Q4T, 무료). 번들 ID·App Group을 바꾸면 pbxproj, 두 entitlements, Dart `WidgetSync.appGroupId`, Swift `Snapshot.appGroupId`를 함께 고친다.
- API 키는 앱에 넣지 않는다. 외부 시세 API는 서버에서만 호출.
