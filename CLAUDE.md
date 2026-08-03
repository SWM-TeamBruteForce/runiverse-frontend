# Project: Runiverse

러너를 매칭해 **같은 시간에 서로 다른 장소에서 함께 달리고**, 러닝 지표에서 파생된 고유 색을 수집하는 러닝 소셜 앱.
개발자는 Flutter 첫 프로젝트다.

## Tech Stack

- [Flutter](https://flutter.dev) + [fvm](https://fvm.app)으로 SDK 고정 (전역 flutter 금지)
- [Riverpod](https://riverpod.dev) 3 — 코드 생성 방식 `@riverpod`
- [go_router](https://pub.dev/packages/go_router) · [lucide_icons_flutter](https://pub.dev/packages/lucide_icons_flutter) — 아이콘은 **Lucide만** 쓴다. `Icons.*`(Material) 혼용 금지
- **(미도입)** [dio](https://pub.dev/packages/dio) + WebSocket / [freezed](https://pub.dev/packages/freezed) / riverpod 코드생성(`riverpod_annotation` `build_runner`)
- Android 우선, iOS는 이후 전환 · Windows + Android Studio 에뮬레이터 · 인프라 AWS

**(미도입)** 표시된 것은 아직 `pubspec.yaml`에 없다. 필요해지는 시점에 승인을 받고 추가한다.

## Architecture

- 저장소 루트 = Flutter 루트 = `frontend/`. 기획·디자인 문서는 저장소 **밖** `../Docs/`, `../design_system/`
- `lib/app/router/` - go_router 설정, 라우트 상수, 딥링크
- `lib/core/` - 기능 무관 공통: `config` `network` `storage` `theme/tokens` `theme/extensions` `strings` `utils` `widgets`
- `lib/features/<name>/` - `onboarding` `auth` `home` `matching` `session` `record` `color` `profile` `feed` `competition`
  - `data/` DTO·API·repo 구현 / `domain/` 엔티티·repo 인터페이스 / `presentation/` page·widget·provider
- **의존 방향: `presentation → domain ← data`.** presentation은 data를 import하지 않는다. domain은 순수 Dart만.
- 다른 feature의 `presentation/`을 import하지 않는다. 공유가 필요하면 `core/widgets/`로 올린다.

## Scope (MVP)

- 하단 탭 5개는 **홈 / 기록 / 피드 / 대회일정 / 프로필**이다. 일부 기획 문서의 `홈/러닝/기록/피드/마이`는 **낡은 것**이다.
- 피드 · 대회일정은 탭을 두되 화면은 `ComingSoonPage`. 탭을 숨기거나 비활성화하지 않는다 — 눌리고, 준비중 화면이 뜬다.
- 매칭은 **예약 매칭**이 MVP다. 실시간 매칭은 1차 확장. → 상세는 `docs/implementation-notes.md` 2절

## Conventions

- 파일·폴더 `snake_case` / 클래스 `PascalCase` / 변수·함수 `lowerCamelCase`
- 접미사로 계층을 드러낸다: `*_page` `*_view` `*_card` `*_provider` `*_state` / `*_entity` `*_repository` / `*_repository_impl` `*_dto` `*_api`
- 내부 import는 항상 `package:runiverse/...` 절대경로
- 상태는 freezed sealed union. 화면은 **loading / data / error 3분기를 반드시 처리**
- 화면을 만들 때 **empty 상태**와 **다크·라이트 두 테마**를 함께 정의한다
- 색·치수·타이포·문자열·모션은 전부 토큰: `context.appColors` `AppSpacing` `AppRadius` `AppTypography` `AppStrings` `AppMotion`
- 러닝 수치에는 `FontFeature.tabularFigures()` 적용 (실시간 갱신 시 자릿수 흔들림 방지)
- 위젯은 필요한 필드만 `select`해서 watch한다. 러닝 화면은 초당 여러 번 갱신된다
- UI 텍스트는 한국어. **"친구"라는 말은 쓰지 않는다** (요청→수락 모델)

## Commands

- run: `fvm flutter run`
- analyze: `fvm flutter analyze`
- format: `fvm dart format lib`
- test: `fvm flutter test` (파일 하나: `fvm flutter test test/foo_test.dart`)
- deps: `fvm flutter pub get` / `fvm flutter pub add <package>`
- codegen: `fvm dart run build_runner build --delete-conflicting-outputs`

## Git

규칙 전문은 `docs/CONTRIBUTING.md`. 자주 틀리는 것만 옮겨 적는다.

- 커밋: `<type>: <설명>` — **type 앞에 이모지가 붙는다.** `📍 Feat` `🔨 Fix` `📝 Docs` `🎨 Style` `🤖 Refactor` `✅ Test` `🚚 Chore` `✂️ Remove` `🔧 Rename`
- 브랜치: `<type>/<domain>` 소문자 kebab-case (`feat/oauth-login`)
- **PR의 base는 `dev`.** GitHub가 `main`으로 잡아두므로 열 때마다 확인한다
- 한 커밋에 논리적 변경 하나만. 각 커밋이 그 시점에 빌드되는지 본다
- **AI를 공동 작성자로 넣지 않는다.** `Co-Authored-By: Claude` 트레일러도, `🤖 Generated with` 푸터도 붙이지 않는다. GitHub 기여자 목록은 사람만 남긴다
- PR 본문은 `.github/pull_request_template.md`의 6개 절을 채운다. 그중 **💬 리뷰 포인트**에 확신이 없었던 선택과 디자인 확인이 필요한 값을 적는다

## Do

- 모든 flutter/dart 명령 앞에 `fvm`
- **한 번에 한 파일.** 왜 그렇게 하는지 1~2줄 근거를 붙이고, 동작 확인 방법(실행 커맨드·눌러볼 곳·기대 결과)을 함께 준다
- 구현 전에 전제를 말한다. 해석이 갈리면 선택지를 제시하고, 불분명하면 멈추고 묻는다
- 코드 작성 후 `fvm flutter analyze` 경고 0개 확인
- 테스트는 세 가지만: 순수 계산 로직 · 색 생성의 결정론성 · 상태 전이
- 새 패키지가 필요하면 **대안 1개와 선택 이유를 먼저 제안하고 승인받는다**
- 모르면 모른다고 한다. 존재하지 않는 API를 만들어내지 않는다

## Don't

- 전역 `flutter` / `dart` 명령 사용
- 요청 없이 이 파일 수정 — 새 규칙이 필요하면 **수정안만 제안**한다. 일회성 오류 해결법은 넣지 않는다
- 요청하지 않은 기능·추상화·설정 가능성 추가, 인접 코드 "개선", 안 고장난 것 리팩터링
- `core/theme/tokens/` 밖에서 `Color(0x...)` 등 값 하드코딩
- **API 키·시크릿 하드코딩** — `core/config`의 환경변수로만
- `StateProvider` / `StateNotifierProvider` 사용 (Riverpod 3 레거시. 블로그 예제 대부분이 2.x다)
- `*.g.dart` / `*.freezed.dart` 직접 수정, `// ignore:`로 analyze 경고 덮기
- **GPS 좌표·경로를 파티원에게 노출** (어떤 화면·API로도). 진행률과 격차만 공유한다
- 파티원 비교에 **순위(1등/2등) 표시** — 경쟁이 아니라 동행 프레임이다
- 시크릿 커밋 (`.env` `*.keystore` `key.properties` `google-services.json`)
- 검증하지 않은 코드를 "완성"이라고 보고
- 한 PR에 파일 20개 / 500줄 초과 (초기 세팅 등 생성물 위주는 예외 — 사유를 PR에 적는다)

## Docs

**저장소 안** — 코드와 함께 버전 관리한다.

| 주제 | 경로 |
|---|---|
| **구현 함정·문서 정본 규칙** | `docs/implementation-notes.md` |
| 협업 규칙 (커밋·브랜치·PR) | `docs/CONTRIBUTING.md` |

**저장소 밖** — 기획·디자인 원본. 버전 관리 대상이 아니고, 도구가 접근 권한을 따로 물을 수 있다.

| 주제 | 경로 |
|---|---|
| 화면 구조·범위 | `../Docs/IA/Runiverse_IA설계md.md` |
| 기능 요구사항 | `../Docs/기능명세서/Runiverse_기능명세서(최종).md` |
| 디자인 토큰 | `../design_system/Runiverse 디자인 시스템 v1.1 - 파운데이션.md` |
| **화면 레이아웃 (정본)** | `../Docs/UI화면설계_md/Runiverse_와이어프레임_최종.md` |
| **화면 시각 정본** | Figma `Runiverse — Design System & Screens` (파일 키 `Ds2URinGrgXo43wC5OFQ8x`) |
| 구현 제약·백엔드 요구사항 | `../Docs/UI화면설계_md/Runiverse_와이어프레임_FE노트.md` |

**화면은 `와이어프레임_최종.md` + Figma 두 가지를 근거로 만든다.** 같은 폴더의 `와이어프레임.md` · `와이어프레임_수정(1).md` · `와이어프레임_디자인리뷰.md`는 **낡았다. 보지 않는다.**

**화면 작업을 시작하기 전에** `와이어프레임_최종.md`의 해당 화면 절과 `docs/implementation-notes.md`의 해당 항목을 확인한다. 색 시스템·Riverpod·라우팅의 실전 함정이 후자에 모여 있다.
