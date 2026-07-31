# CLAUDE.md — Runiverse

## 경로 기준 — 먼저 읽는다

- **저장소 루트 = Flutter 프로젝트 루트 = 이 파일이 있는 `frontend/`.** `pubspec.yaml`이 여기 있다. `lib/`, `android/`, `assets/` 모두 이 아래다.
- **기획·디자인 문서는 저장소 밖에 있다** — `../Docs/`, `../design system/`. 버전 관리 대상이 아니고, 도구에 따라 접근 권한을 따로 물을 수 있다.

---

## 프로젝트

조건이 맞는 러너를 매칭해 **같은 시간에 서로 다른 장소에서 함께 달리고**, 러닝 지표에서 파생된 고유 색을 수집하는 러닝 소셜 앱.

핵심 축 4개: ① 매칭 ② 실시간 러닝 세션 ③ 기록/통계 ④ 소셜(피드·팔로우)

**MVP의 매칭은 예약 매칭이다** — 30분 슬롯 × 거리(3/5/10km) × 페이스 수준으로 2~4명 자동 매칭. 실시간 매칭은 1차 확장이다. 지역은 매칭 조건이 아니다(원격 매칭이므로).

**기술 리스크 1순위는 백그라운드 GPS 추적과 다중 사용자 실시간 동기화다.** 이 둘은 다른 화면보다 먼저 프로토타입으로 검증한다.

---

## 개발 환경

| 항목 | 값 |
|---|---|
| OS | Windows |
| SDK 관리 | **fvm** (전역 flutter 사용 금지) |
| 상태관리 | **Riverpod** (코드 생성 방식 `@riverpod`) |
| 라우팅 | go_router |
| 네트워크 | dio + WebSocket |
| 검증 | Android Studio 에뮬레이터 |
| 인프라 | AWS |


**패키지는 임의로 추가하지 않는다.** 필요해지면 pubspec에 들어갈 정확한 줄 + 대안 1개 + 선택 이유를 먼저 제안하고 승인을 받는다.

### 명령어 — 반드시 `fvm`을 앞에 붙인다

```powershell
fvm flutter run
fvm flutter pub get
fvm flutter pub add <package>
fvm flutter analyze
fvm flutter test
fvm flutter test test/foo_test.dart          # 파일 하나만
fvm flutter test --plain-name '페이스 환산'    # 이름이 맞는 테스트만
fvm dart format lib
fvm dart run build_runner build --delete-conflicting-outputs
```

절대 `flutter run`, `dart run ...` 처럼 fvm 없이 실행하지 않는다.

---

## 개발 우선순위 (MVP)

1. **Android 먼저.** iOS 전환은 그 다음. iOS 전용 코드를 미리 쓰지 않는다.
2. **피드(feed) · 대회일정(competition) 탭은 MVP 제외.** 하단 탭바에는 그대로 두되 화면은 `ComingSoonPage`로 둔다. 탭을 숨기거나 비활성화하지 않는다 — 눌리고, 준비중 화면이 뜬다.
3. 인증은 **이메일 인증 기반 로컬 로그인 먼저**, 소셜(구글·카카오)은 그 다음.

하단 탭 5개는 **홈 / 기록 / 피드 / 대회일정 / 프로필**이다. (일부 기획 문서에 `홈/러닝/기록/피드/마이`로 적혀 있는데 **낡은 것**이다.)

---

## 아키텍처

```
lib/
├─ main.dart
├─ app/router/          # go_router 설정, 라우트 이름 상수, 딥링크
├─ core/                # 기능 무관 공통
│   ├─ config/          # 환경변수 + 정책 상수
│   ├─ network/         # dio 클라이언트·인터셉터·에러 모델, WebSocket
│   ├─ storage/         # secure_storage(토큰) / shared_preferences / 로컬 DB
│   ├─ theme/
│   │   ├─ tokens/      # palette · spacing · sizes · radii · typography · motion
│   │   └─ extensions/  # AppColors · AppElevation · AppGlow (ThemeExtension)
│   ├─ strings/         # 사용자 노출 문자열
│   ├─ utils/           # 페이스·거리·시간 포맷터
│   └─ widgets/         # 2개 이상 feature에서 쓰는 공통 위젯
└─ features/<name>/
    ├─ data/            # DTO, API, repository 구현
    ├─ domain/          # 엔티티, repository 인터페이스
    └─ presentation/    # page, widgets, provider
```

feature 목록: `onboarding` `auth` `home` `matching` `session` `record` `color` `profile` `feed` `competition`

`lib/` 밖에서 앱이 쓰는 것은 `assets/fonts/`(Pretendard) 하나다.

### 계층 의존 규칙 — 위반 시 코드를 다시 짠다

```
presentation ──▶ domain ◀── data
```

- `presentation`에서 **`data/`를 import하지 않는다.** domain의 인터페이스·엔티티만 쓴다.
- `domain`은 순수 Dart만. `dio`, `flutter/material.dart` import 금지.
- DTO ↔ Entity 변환은 `data` 안에서 끝낸다. Entity에 `fromJson`을 넣지 않는다.
- **다른 feature의 `presentation/`을 import하지 않는다.** 공유가 필요하면 `core/widgets/`로 올린다.
- 프로젝트 내부 import는 **항상 `package:runiverse/...` 절대경로**. 상대경로 금지(`analyze`가 잡는다).

**색은 feature 3개(S15 리빌 · S20 오라 · S21 모자이크)에 걸친다.** 의존 규칙에 예외를 만들지 말고 역할로 나눈다 — `core/widgets/color/`는 `Color`를 파라미터로 받아 그리기만 하는 순수 표현 위젯, `features/color/`는 지표→색 매핑·팔레트·컬렉션 같은 도메인 로직과 전용 화면.

---

## 디자인 시스템 — 하드코딩 절대 금지

앱의 핵심 자산은 **러닝에서 파생되는 고유 색**이다. 기반 UI는 저채도 중립색으로만 구성해 러닝 색이 도드라지게 한다. 기본 테마는 **다크**, 라이트는 완전 대칭 제공.

| 금지 | 대신 |
|---|---|
| `Color(0xFF141924)` | `context.appColors.bgSurface` |
| `EdgeInsets.all(16)` | `EdgeInsets.all(AppSpacing.space4)` |
| `BorderRadius.circular(16)` | `AppRadius.lg` |
| `TextStyle(fontSize: 64, ...)` | `AppTypography.metricHero` |
| `Text('매칭하기')` | `AppStrings.matchingStart` |
| `Duration(milliseconds: 200)` | `AppMotion.base` |

**`core/theme/tokens/` 밖에서 `Color(0x`가 나오면 그건 버그다.**

### 반드시 지킬 표현 규칙

- **러닝 수치에는 `fontFeatures: [FontFeature.tabularFigures()]`를 항상 적용한다.** 페이스·시간이 실시간 갱신될 때 자릿수가 흔들리면 달리면서 읽을 수 없다. ⚠️ **폰트가 `tnum`을 지원하지 않으면 Flutter는 조용히 무시한다**(에러도 경고도 없다). Pretendard 파일에 실제로 들어 있는지 눈으로 확인한다.
- 러닝 중 화면(S11~S13) 터치 타깃은 **56px**, 그 외는 44px.
- 러닝 색 글로우(`glow.*`)와 기반 UI 그림자(`elevation.*`)는 **역할이 다르다. 섞지 않는다.** `glow`는 반드시 색을 인자로 받는 형태(`glow.md(runColor)`)로 만들어 앱 크롬에 실수로 쓸 수 없게 한다. `Material(elevation:)` 단축 경로가 둘을 섞기 가장 쉬운 지점이다.
- **러닝 색은 테마가 아니라 데이터다.** 한 화면에 여러 개가 동시에 뜬다(모자이크 캘린더는 30개). ThemeExtension에 넣지 말고 위젯 파라미터로 전달한다.
- **글로우를 텍스트 뒤에 깔지 않는다.** 러닝 중 수치는 대비 7:1을 만족해야 하는데 숫자 뒤 색 번짐이 이를 무너뜨린다.
- 색만으로 정보를 전달하지 않는다. 컬렉션 슬롯엔 범주·shade 라벨, 모자이크 셀엔 날짜를 병기한다.
- 파괴적 액션은 탭이 아니라 **hold-to-end(2초) 또는 2단계 확인**으로만.

---

## Riverpod 규칙

- 코드 생성 방식(`@riverpod`)으로 통일. 손으로 `Provider(...)`를 만들지 않는다.
- ⚠️ `StateProvider` · `StateNotifierProvider`는 **Riverpod 3에서 레거시**다. 블로그 예제 대부분이 2.x라 이걸 쓰는데, 새 코드에서는 쓰지 않는다.
- provider 파일은 `features/<name>/presentation/provider/*_provider.dart`.
- 상태 클래스는 **freezed sealed union**으로. 홈 히어로 4상태(기본/대기중/확정/실패)가 정확히 이 패턴이다.
- 화면 상태는 항상 `loading / data / error` **3분기를 처리한다.** 에러 무시 금지.
- **UI는 상태를 계산하지 않는다.** 페이스 환산, 상위 % 산출, 히스테리시스 판정은 `domain/`이나 provider에 둔다.
- 여러 화면이 공유하는 전역 상태(매칭 대기 상태, 스티키 배너)는 `keepAlive`를 명시한다. **숨은 탭의 provider는 실제로 dispose된다** — 매칭 상태를 홈 화면 안에 두면 탭을 옮기는 순간 타이머와 WebSocket 구독이 끊긴다. 글로벌 배너와 홈 히어로는 **같은 하나의 provider**를 구독한다.
- 위젯에서는 **필요한 필드만 `select`** 해서 watch한다. 러닝 화면은 초당 여러 번 갱신되므로 상태 전체를 watch하면 화면 전체가 리빌드된다.
- Stream 구독(GPS, WebSocket)은 반드시 `ref.onDispose`에서 취소한다.

### 라우팅

- 5탭은 `StatefulShellRoute`로 구성해 탭 전환 시 스크롤·상태를 보존한다.
- 글로벌 매칭 스티키 배너는 **Shell 레이어에 1개만** 둔다. 화면마다 복붙 금지.
- ⚠️ **`redirect` 안에서 `ref.watch`를 쓰지 않는다.** 무한 리빌드가 난다. `refreshListenable`을 쓴다.
- 알림 딥링크는 매핑 테이블 1곳으로 관리하고, 대상이 없으면 홈으로 폴백한다.

---

## 네이밍

| 대상 | 규칙 |
|---|---|
| 폴더·파일 | `snake_case` |
| 클래스·enum | `PascalCase` |
| 변수·함수·상수 | `lowerCamelCase` |

| 접미사 | 계층 | 역할 |
|---|---|---|
| `*_page.dart` | presentation | 라우트가 가리키는 화면 |
| `*_view.dart` | presentation | 페이지 내부 큰 구획 |
| `*_card.dart` `*_sheet.dart` `*_chip.dart` | presentation | 위젯 |
| `*_provider.dart` `*_state.dart` | presentation | Riverpod |
| `*_entity.dart` `*_repository.dart` | domain | 모델 / 인터페이스 |
| `*_repository_impl.dart` `*_dto.dart` `*_api.dart` | data | 구현 |

**UI 문자열과 코드에서 "친구"라는 말을 쓰지 않는다.** 소셜 모델은 요청→수락이다.


## 작업 방식

### 한 세션 = 한 이슈

한 대화에서 화면 3개를 만들지 않는다. 컨텍스트가 섞이면 앞서 정한 규칙을 잊는다.

### 코드를 만든 뒤 반드시

```powershell
fvm dart format lib
fvm flutter analyze     # 경고 0개가 아니면 커밋하지 않는다
fvm flutter run         # 에뮬레이터에서 눈으로 확인
```

### 화면을 만들 때 항상 함께 정의할 것

- 로딩 상태 / 비어 있음(empty) 상태 / 에러 상태
- 다크 · 라이트 두 테마 모두

### 테스트

커버리지를 좇지 않는다. 대신 이건 반드시 테스트한다.

- **순수 계산 로직** — 페이스 환산, 거리 누적, 구간 분할, 시간 포맷
- **색 생성의 결정론성** — 같은 기록은 항상 같은 색, 블렌드는 순서와 무관하게 같은 결과. 결정론성 자체가 요구사항이다
- **상태 전이** — 매칭 대기 → 확정/실패, 러닝 시작 → 중지 → 종료

⚠️ **`test/widget_test.dart`는 `flutter create` 기본 카운터 테스트다.** `main.dart`의 `MyApp`을 직접 import하므로 `main.dart`를 교체하는 순간 컴파일조차 되지 않는다. **교체하는 커밋에서 함께 지우거나 다시 쓴다.**

---

## 이 파일 자체의 유지 규칙

- **요청 없이 `CLAUDE.md`를 수정하지 않는다.**
- 새로운 영구 규칙이 필요하다고 판단되면, 직접 고치지 말고 **먼저 수정안을 제안한다.** 반영 여부는 사람이 결정한다.
- **일회성 오류 해결 방법은 여기에 추가하지 않는다.**
- **프로젝트 코드에서 확인 가능한 사실을 불필요하게 반복하지 않는다.** (패키지 버전, 함수 시그니처, 폴더에 실제로 뭐가 있는지 등) 코드를 읽으면 알 수 있는 것 말고, **코드를 읽어도 알 수 없는 의도·제약·금지사항**만 적는다.
- 아래가 바뀌면 **같은 커밋에서** 짝을 맞춘다.

| 바뀐 것 | 같이 고칠 곳 |
|---|---|
| `pubspec.yaml` 의존성 | 이 문서 "개발 환경"의 미도입 목록 |
| `.fvmrc` 버전 | `.vscode/settings.json`의 `dart.flutterSdkPath` (버전 문자열이 박혀 있다. `fvm use <버전>`이 대신 갱신해 주기도 한다) |
| `main.dart` 교체 | `test/widget_test.dart` |
| `assets/` 파일 추가 | `pubspec.yaml`의 `assets:` / `fonts:` 블록 (선언 없이는 번들되지 않는다) |
| 앱 식별자(org) | `android/app/build.gradle.kts`와 iOS `Runner.xcodeproj/project.pbxproj` **양쪽** |

---

## 작업 원칙

### 코딩 전에 생각한다

**추측하지 않는다. 혼란을 감추지 않는다. 트레이드오프를 드러낸다.**

구현 전에:

- 전제하고 있는 것을 명시적으로 말한다. 확실하지 않으면 묻는다.
- 해석이 여러 갈래면 그것들을 제시한다. 조용히 하나를 고르지 않는다.
- 더 단순한 방법이 있으면 말한다. 필요하면 반대 의견을 낸다.
- 불분명한 게 있으면 멈춘다. 무엇이 헷갈리는지 이름 붙여 말하고 묻는다.
- **모르는 것은 모른다고 말한다. 존재하지 않는 API·패키지를 만들어내지 않는다.** 인터넷 예제를 그대로 믿지 않는다 — Riverpod은 3.x인데 블로그 대부분이 2.x 기준이고, `freezed`·`google_sign_in`도 최근 API가 크게 바뀌었다.

### 단순함이 먼저다

**문제를 푸는 최소한의 코드만. 미리 만들어두는 것은 없다.**

- 요청받지 않은 기능은 만들지 않는다.
- 한 곳에서만 쓰는 코드에 추상화를 만들지 않는다.
- 요청받지 않은 "유연성"·"설정 가능성"을 넣지 않는다.
- 일어날 수 없는 상황에 대한 에러 처리를 넣지 않는다.
- 200줄을 썼는데 50줄로 될 일이면 다시 쓴다.
- 파일이 300줄을 넘으면 위젯을 분리한다.

스스로에게 묻는다: *"선임 개발자가 이걸 보고 과하다고 할까?"* 그렇다면 단순화한다.

### 최소 범위만 건드린다

**꼭 필요한 것만 손댄다. 내가 만든 흔적만 치운다.**

기존 코드를 수정할 때:

- 옆에 있는 코드·주석·포맷을 "개선"하지 않는다.
- 고장 나지 않은 것을 리팩터링하지 않는다.
- 내가 다르게 짤 것 같아도 기존 스타일에 맞춘다.
- 관련 없는 죽은 코드를 발견하면 **말만 한다. 지우지 않는다.**

내 변경이 고아를 만들었다면:

- **내 변경 때문에** 안 쓰이게 된 import·변수·함수는 제거한다.
- 원래부터 죽어 있던 코드는 요청받기 전까지 건드리지 않는다.

기준: **변경된 모든 줄이 사용자의 요청으로 직접 추적되어야 한다.**

### 목표 기반으로 실행한다

**성공 기준을 먼저 정의하고, 검증될 때까지 반복한다.**

작업을 검증 가능한 목표로 바꾼다:

- "유효성 검사 추가" → "잘못된 입력에 대한 테스트를 쓰고, 통과시킨다"
- "버그 수정" → "버그를 재현하는 테스트를 쓰고, 통과시킨다"
- "X 리팩터링" → "전후로 테스트가 모두 통과함을 확인한다"

여러 단계짜리 작업은 짧은 계획을 먼저 말한다:

```
1. [단계] → 검증: [확인 방법]
2. [단계] → 검증: [확인 방법]
3. [단계] → 검증: [확인 방법]
```

성공 기준이 강할수록 혼자 반복해서 완료할 수 있다. 기준이 약하면("돌아가게 해줘") 계속 되물어야 한다.

### 입문자 모드

개발자는 **Flutter 첫 프로젝트**다. 따라서:

- **왜 그렇게 하는지 1~2줄 근거를 항상 붙인다.** 코드만 던지지 않는다.
- **한 번에 한 단계.** 파일 10개를 동시에 쏟아내지 않고 "이 파일 → 확인 → 다음"으로 진행한다.
- 처음 등장하는 개념은 짧게 정의한다(`Widget`, `Future`, `Stream`, `ThemeExtension` 등).
- **동작 확인 방법을 함께 알려준다.** 실행 커맨드, 눌러볼 버튼, 기대 결과.
- 에러가 나면 **에러 메시지 읽는 법**부터 설명한다(어떤 파일·몇 번째 줄·무슨 타입 문제인지).
- 파일을 수정할 때는 **전체 파일**을 주거나 넣을 위치를 명확히 지시한다. "적당한 곳에 추가" 금지.

---

## 하지 말 것

- `main` 브랜치에 직접 커밋·push (**아직 원격이 없고 브랜치도 `main` 하나뿐이다** — 작업 브랜치를 먼저 만든다)
- 전역 `flutter` / `dart` 명령 사용 (항상 `fvm` 경유)
- 저장소를 **한글·공백이 든 경로**에 두기 — `flutter analyze`가 분석 서버 크래시로 죽는다(실제로 겪은 고장). ASCII 경로에만 둔다
- `.env`, `*.keystore`, `key.properties`, `google-services.json` 커밋
- API 키·시크릿 하드코딩 (`core/config`의 환경변수로만). 소셜 로그인 시크릿은 서버 보관이 원칙
- `// ignore:` 로 analyze 경고 덮기 (불가피하면 이유를 주석으로 남긴다)
- `*.g.dart` / `*.freezed.dart` 를 직접 수정 (생성 파일이다. 원본을 고치고 build_runner를 돌린다)
- 실제 GPS 좌표·경로를 파티원에게 노출 (**어떤 화면·어떤 API로도.** 진행률과 격차만 공유한다)
- 파티원 비교에 **순위(1등/2등) 표시** — 경쟁이 아니라 동행 프레임이다. 격차만 보여준다
- 피드 공개 범위(팔로워/전체/나만)를 UI만 만들고 서버 필터를 안 걸기
- 검증되지 않은 코드를 "완성"이라고 보고하기
- 한 PR에 파일 20개 / 500줄 초과

---

## 참고 문서

전부 이 저장소 안에 있다. 화면 작업 전 해당 섹션을 읽는다.

| 주제 | 문서 |
|---|---|
| 화면 구조·내비게이션·기능 범위 | `../Docs/Runiverse_IA설계md.md` |
| 기능 요구사항·수용 기준 | `../Docs/Runiverse_기능명세서(최종).md` |
| 디자인 토큰·컬러 시스템·접근성 | `../design system/Runiverse 디자인 시스템 v1 — 파운데이션.md` |
| 화면 레이아웃 | `../Docs/UI화면설계_md/Runiverse_와이어프레임_수정(1).md` |
| 구현 제약·백엔드 요구사항 | `../Docs/UI화면설계_md/Runiverse_와이어프레임_FE노트.md` |
| **진행 상황·다음 할 일·미결 사항** | `../Docs/작업현황.md` |

디자인 시스템은 Figma에도 있다(파일 키 `Ds2URinGrgXo43wC5OFQ8x`). **Figma는 정본이 아니라 구현체다** — 표현할 수 없어 대역을 쓴 곳이 있으므로(폰트가 대표적) **Figma에서 잰 픽셀값이 문서와 다르면 문서가 이긴다.**

### 문서가 서로 다를 때

> **범위·구조 충돌** → `IA` > `기능명세서` > `와이어프레임`
> **비주얼·토큰 충돌** → `디자인 시스템` > `Figma` > `와이어프레임`

⚠️ **와이어프레임은 컬러 시스템이 기획되기 전에 작성됐다.** 아래 3개 화면은 와이어프레임만 보고 만들면 **틀린 화면을 만들게 된다.**

| 화면 | 와이어프레임(낡음) | 실제로 만들 것 |
|---|---|---|
| S15 종료 요약 | 색 리빌 단계 없음 | **색 리빌 연출 포함** |
| S20 프로필 | 잔디 히트맵 + 뱃지 | **시그니처 오라 + 컬러 컬렉션** |
| S21 기록 | 일반 캘린더 | **색 모자이크 캘린더** |

⚠️ **같은 문서의 사본이 `../Docs/` 안에 두 벌씩 있다.** 최상위(`../Docs/*.md`)가 프론트엔드가 쓰던 쪽이고, 하위 폴더(`../Docs/기능명세서/`, `../Docs/IA/`)가 원본이다. **기능명세서는 둘의 내용이 실제로 다르다**(소셜 로그인 2종 vs 3종 — **2종이 맞다**). IA는 두 사본이 동일하다. 정본이 정리되기 전까지 **최상위 쪽을 본다.**
