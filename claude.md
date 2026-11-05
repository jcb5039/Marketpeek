# MarketPeek

코인·미국주식·환율 시세와 AI 어제 이슈를 iOS 잠금화면 위젯으로 보여주는 Flutter 앱.

## 폴더 구조

### lib/
- `app/` — 앱 진입점(MaterialApp), 화면 라우팅, 하단 탭(홈 / 위젯 / 설정)
- `core/` — 앱 전체에서 쓰는 기반 코드
  - `theme/` — 색상(배경, 포인트, 상승·하락), 텍스트 스타일, ThemeData
  - `constants/` — 앱 상수, 지원 통화 목록
  - `utils/` — 가격·등락률 포맷, 미국장 상태 계산 같은 도우미 함수
- `data/` — 데이터 계층
  - `models/` — 코인, 미국주식, 환율, AI 이슈, 설정, 내 목록 데이터 모델
  - `sources/` — 외부 API(업비트, 미국주식, 환율, AI 이슈)와 기기 로컬 저장소 접근
  - `repositories/` — sources를 묶어 화면에 데이터를 제공 (캐시, 원화 환산, 목록 관리)
- `features/` — 화면 단위 기능
  - `home/` — 홈(내 목록): 코인·미국주식·환율 섹션, 편집 모드, 빈 상태
  - `search/` — 코인 추가, 미국주식 추가 검색 화면
  - `currency/` — 환율 위젯에 표시할 통화 선택
  - `widget_guide/` — 위젯 4종 안내, 잠금화면에 위젯 추가하는 방법
  - `settings/` — 위젯별 표시 항목, 상승·하락 색 방식 설정
- `shared/`
  - `widgets/` — 여러 화면에서 같이 쓰는 UI (종목 행, 섹션 헤더, 위젯 배지, 등락률, 갱신 시각)
- `widget_sync/` — 앱 데이터를 iOS 잠금화면 위젯(App Group)으로 넘기고 위젯 갱신 요청

### assets/
- `fonts/` — Noto Sans KR 폰트 파일
- `icons/` — 앱에서 쓰는 아이콘 이미지

### test/
- `data/` — 모델·repository·유틸 테스트
- `features/` — 화면 위젯 테스트

### 기타
- `ios/` — iOS 앱. 잠금화면 위젯(WidgetKit 확장)은 나중에 Xcode에서 타깃을 추가해 이 아래에 생성
- `android/`, `macos/`, `linux/`, `windows/`, `web/` — Flutter 기본 플랫폼 폴더

## 규칙
- 각 Dart 파일 첫 줄 주석에 그 파일이 맡을 기능이 적혀 있음. 구현할 때 그 범위를 따른다.
- 디자인 원본: claude.ai 아티팩트 "시세 위젯 잠금화면 디자인"
