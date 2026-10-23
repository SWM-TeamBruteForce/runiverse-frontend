# 온보딩 · 자동 로그인 플로우 설계

2026-08-08 · 대상 화면 S01 스플래시 · S04 프로필 · 백엔드 `runiverse-backend` `dev` 브랜치

이 문서는 **무엇을 왜 그렇게 정했는지**만 적는다.

---

## 0. 이 문서가 대체하는 것

`2026-08-04-local-auth-design.md`의 두 항목이 낡았다.

| 낡은 것 | 지금 |
|---|---|
| 2-1 "서버는 사용자가 온보딩을 마쳤는지 모른다. 가입한 사람은 신규, 로그인한 사람은 기존" | **서버가 `isOnboarded`를 준다.** 추측하지 않는다 |
| 5 "401 재시도 인터셉터" | **만들지 않는다.** 2-6 참조 |

---

## 1. 범위

앱을 켰을 때 어디로 갈지 정하는 일과, 프로필 등록을 서버에 반영하는 일.

정의된 네 갈래는 이렇다.

| | 상황 | 경로 |
|---|---|---|
| 1 | 처음 켰다 | 스플래시 → 온보딩 소개 → 로그인 → 약관 → 가입 → (자동 로그인) → 프로필 → 홈 |
| 2 | 프로필 입력 중 이탈. `isOnboarded=false` | 스플래시 → (자동 로그인) → **홈 + 유도 카드** |
| 3 | 토큰이 살아 있다 | 스플래시 → (자동 로그인) → 홈 |
| 4 | 토큰이 만료됐다 | 스플래시 → 로그인 → 홈 |

> 2번은 처음에 "→ 프로필"로 정했다가 **2-9에서 뒤집었다.** 앱을 열자마자 폼이 뜨는 것이
> 당황스럽다. 이제 2와 3은 도착지가 같고, 유도 카드가 있느냐로만 갈린다.

**화면 이동 자체는 이미 다 배선돼 있다.** 바꾸는 것은 스플래시의 갈림길과, 그 갈림길이 읽을 값을 만드는 일이다.

| 지금 있는 배선 | |
|---|---|
| `onboarding_intro_page.dart:76` | → 로그인 |
| `sign_in_page.dart:206` | → 약관 |
| `terms_agreement_page.dart:80` | → 가입 |
| `sign_up_page.dart:94` | → 프로필 |
| `profile_setup_page.dart:263` | → 홈 |

### 쓰는 API

| 엔드포인트 | |
|---|---|
| `POST /api/v1/auth/refresh` | 바디 `{refreshToken}` · 인증 헤더 없음 |
| `POST /api/v1/users/onboarding` | **`Authorization: Bearer` 필요** · 201 `{userId, nickname}` |

새로 요구하는 API는 없다.

---

## 2. 결정

### 2-1. 스플래시 갈림길

```
스플래시 진입
│
├─ refreshToken 있음
│    └─ POST /api/v1/auth/refresh { refreshToken }     (5초)
│         │
│         ├─ 200 ─ 토큰 둘을 새 값으로 덮어쓴다  ← 회전. 5절
│         │         └─ /home                               [2][3]
│         │            (isOnboarded를 보지 않는다 — 2-9)
│         │
│         ├─ 401 ─ clearTokens()  ← userId·isOnboarded는 남긴다
│         │         └─ /auth/sign-in                        [4]
│         │
│         └─ 네트워크 · 5xx ─ 판정 불가. 2-3으로
│
├─ refreshToken 없음 · userId 있음 → /auth/sign-in
└─ 아무것도 없음                    → /onboarding           [1]
```

**로그인 화면도 같은 기준을 쓴다** — 둘 다 홈으로 보낸다. 한쪽만 고치면
**로그인 직후와 앱을 껐다 켰을 때가 갈리는** 어긋남이 생긴다. 에뮬레이터에서 실제로 드러났다.

**마지막 두 줄이 이 설계의 핵심이다.** "저장된 것이 하나도 없다"(진짜 첫 실행)와 "토큰만 없다"(만료됐거나 로그아웃했다)를 구분하면 플로우 1과 4가 **별도의 첫 실행 플래그 없이** 갈린다.

그래서 401에서 `userId`를 지우지 않는다. 지우면 다음 실행에 온보딩 소개를 다시 보게 된다.

**refresh 호출에만 5초 타임아웃을 건다.** dio 기본값은 10초인데, 스플래시 체류가 1.6초인 화면에서 10초는 멈춘 것으로 읽힌다.

### 2-2. 상태를 한 칸 넓힌다

```dart
sealed class AuthState

AuthUnknown                                    // 진입 직후 · 판정 실패 중
AuthSignedOut({ required bool returning })     // returning → 로그인 화면, 아니면 온보딩 소개
AuthSignedIn(String userId, bool isOnboarded)  // isOnboarded → 홈, 아니면 프로필
```

`returning`을 별도 상태로 나누지 않고 필드로 둔 이유는, **이 값으로 갈리는 곳이 스플래시 한 군데**여서다. sealed로 나눠 얻는 `switch` 망라성이 쓰일 자리가 없다.

`splash_page.dart:87`의 삼항 한 줄이 이 셋을 가르는 `switch`가 된다.

### 2-3. 오프라인을 허용하지 않는다

**정책이다.** 네트워크가 없으면 앱에 들어가지 못한다.

```
네트워크 · 5xx
 │
 1) 자동 재시도 1회 (5초 → 5초)     ← 터널·엘리베이터 같은 순간 끊김을 흡수
 │
 2) 그래도 실패 → 스플래시에 머무른다
      "연결할 수 없습니다"  [다시 시도]
      └─ 누르면 1)로 돌아간다
```

화면을 떠나지 않으므로 상태를 더 만들지 않는다 — `AuthUnknown`에 머무는 것이 곧 "아직 못 정했다"다.

**무한 자동 재시도는 넣지 않는다.** 비행기 모드인 기기에서는 배터리만 쓴다. 사용자가 눌러서 다시 시도한다.

저장된 값을 믿고 들여보내는 우회로는 두지 않는다. **판정에 실패한 것과 판정에 성공한 것은 다른 상태다.**

### 2-4. 페이스 `null`은 전송할 때만 720으로 바꾼다

서버 `averagePaceSecondsPerKm`는 `@NotNull`(120~1800)이다. 앱은 "재본 적 없음"을 `null`로 표현한다 — `profile_setup_page.dart:248`의 건너뛰기가 그것이고, 이유가 그 자리에 적혀 있다.

**치환은 DTO 한 줄에서만 한다.**

```dart
averagePaceSecondsPerKm: profile.paceSecondsPerKm ?? PaceRule.maxMinutes * 60,  // 720
```

- 화면은 그대로 `null`을 들고 있어 시그니처 컬러가 '미정 코럴'로 나온다
- 서버가 nullable로 바뀌면 **이 한 줄만 지운다**

⚠️ **서버가 아는 값(720)과 앱이 보여주는 색(코럴)이 다르다.** 지금은 색을 앱에서만 계산해 티가 나지 않지만, 서버가 색을 계산하게 되면 갈라진다.

### 2-5. 닉네임 규칙을 앱에 다시 쓴다

| | 앱 | 서버 |
|---|---|---|
| 길이 | 2~12 | 2~16 |
| 문자 | 제한 없음 | `^[가-힣a-zA-Z0-9_]+$` |

길이는 앱이 더 엄격해 항상 통과한다. **문자 제한은 지금 앱에 없어서 `"런서 김"`·`"runner!"`·이모지가 서버까지 갔다가 400으로 돌아온다.**

`NicknameStatus`에 `invalidChars`를 더해 **입력하는 자리에서** 막는다. 서버까지 갔다 와서 실패하면 사용자는 무엇이 문제인지 모른다.

⚠️ 비밀번호와 같은 문제다 — **서버가 규칙을 바꾸면 앱이 어긋난다.** `implementation-notes.md`에 항목을 남긴다.

### 2-6. 인증 인터셉터를 만들지 않는다

`Bearer`가 필요한 요청은 지금 `POST /users/onboarding` 하나뿐이다. 그 호출에 `Options(headers: …)`로 직접 붙인다.

인터셉터를 지금 만들면 요청마다 저장소를 읽거나 토큰 캐시를 따로 관리해야 한다. 대상이 하나인 상태에서는 **관리할 것만 늘어난다.** 인증 요청이 늘어나는 시점에 올린다.

401 자동 갱신도 마찬가지다. 지금 401이 날 수 있는 곳은 온보딩 전송 하나이므로 **그 자리에서 처리한다**(2-7).

### 2-7. `ALREADY_ONBOARD`는 성공으로 흡수한다

`HttpOnboardingRepository`가 409를 정상 반환으로 바꿔 돌려준다. 호출자는 이 예외를 모른다.

서버가 이미 온보딩했다고 하면 그게 사실이고, 뒤처진 것은 로컬 플래그다. **사용자를 프로필 화면에 가둘 이유가 없다.** 호출자마다 이 예외를 성공으로 번역하게 두면 언젠가 한 곳을 빠뜨린다.

### 2-8. `VALIDATION_FAILED`의 `message`를 파싱하지 않는다

서버는 검증 실패를 하나의 `code`로 묶고 사유를 `message`로만 구분한다.

```json
{ "code": "VALIDATION_FAILED", "message": "올바른 이메일 형식이 아닙니다." }
```

문구를 갈라 읽으면 **서버가 한 글자만 고쳐도 앱이 조용히 깨진다.**

그리고 400이 왔다는 것은 **앱이 먼저 막았어야 할 값이 서버까지 갔다는 뜻**이다. 사용자에게 정확한 사유를 옮길 게 아니라, 앱 검증에 구멍이 있다는 신호로 읽어야 한다.

- 화면에는 앱이 정한 문구 하나 (`AuthFailure.validation`)
- `message`는 `kDebugMode`에서만 로그로 남긴다 — 구멍을 찾는 단서다

### 2-9. 돌아온 사람을 폼으로 가로막지 않는다 `[2026-08-08 개정]`

**처음 정한 것을 뒤집는다.** 원래는 `isOnboarded=false`면 스플래시와 로그인이 프로필 등록으로
보냈다. 실제로 써 보니 **앱을 열자마자 입력 폼이 뜨는 것이 당황스럽다.** 돌아온 사람은
자기 계획이 있는데 폼이 그것을 가로막는다.

```
자동 로그인 (스플래시)  → /home          isOnboarded를 보지 않는다
로그인                  → /home          isOnboarded를 보지 않는다
가입 직후               → /onboarding/profile   그대로
```

**가입 직후만 남긴 이유** — 그 사람은 방금 계정을 만들었고 **흐름을 타고 있다.** 반면 로그인은
돌아온 사람이다. 그리고 가입 흐름까지 놓으면 프로필을 채울 계기가 사실상 사라진다 —
매칭도 러닝도 준비 중이라 카드를 눌러야 할 이유를 실감하기 어렵다.

**`isOnboarded`의 역할이 바뀐다 — "어디로 보낼지"에서 "무엇을 보여줄지"로.**
값과 저장 방식(4절·5절)은 그대로다. 읽는 곳만 옮긴다.

#### 대신 두 곳에서 만난다

**① 홈 유도 카드** (`isOnboarded=false`일 때만)

히어로 바로 아래에 둔다. **매칭 버튼 바로 아래**라 "이 버튼을 쓰려면 저게 필요하다"가
눈으로 이어진다. `EmptyStateCard`(담담한 회색)와 달리 primary 테두리와 버튼을 줘서
화면에서 유일하게 튀는 카드로 만든다 — 행동을 요구하는 카드이기 때문이다.

> **프로필을 완성해주세요**
> 매칭과 칼로리 계산에 필요해요

누르면 `push`한다. **`go`가 아니다** — 강제가 아니므로 뒤로가기로 나올 수 있어야 한다.

**② 프로필 등록의 "나중에 하기"**

`go(AppRoutes.home)`. 가입 직후 화면은 `go`로 열려 **스택에 그것 하나만 남는다** —
Android 뒤로가기를 누르면 앱이 꺼진다. 사용자가 의도한 동작이 아니므로 출구를 눈에 보이게 둔다.

둘이 짝을 이뤄 **"지금 안 해도 된다, 대신 여기서 다시 만난다"**가 일관된다.

#### 정본에서 벗어나는 것 둘

- 홈(S05)에 정본에 없는 카드가 생긴다
- 프로필 등록(S04)에 정본에 없는 버튼이 생긴다

`docs/implementation-notes.md`에 사유를 남긴다 — S02.5 때와 같은 절차다.

#### 지금 하지 않는 것

게이트를 걸 화면이 아직 없다. 각 화면이 붙을 때 함께 넣는다.

| | 언제 |
|---|---|
| 프로필 탭 유도 | S20이 생길 때 |
| 매칭 진입 게이트 | 매칭 화면이 생길 때 |
| 러닝 칼로리 게이트 | S11~S13이 생길 때 |

⚠️ **지금 매칭 버튼에 게이트를 걸면 헛수고가 된다** — 프로필을 다 채우고 다시 눌러도
"매칭은 아직 준비 중이에요"가 뜬다.

---

## 3. 새 패키지

| 패키지 | 왜 |
|---|---|
| `flutter_secure_storage` | 리프레시 토큰은 **60일**짜리다. 유출되면 두 달간 계정이 열린다. Android는 Keystore가 감싼 `EncryptedSharedPreferences`, iOS는 Keychain에 넣는다. 대안 `shared_preferences`는 평문 XML이라 루팅 기기나 ADB 백업으로 그대로 읽힌다 |

### 플랫폼 설정

**Android** — 이번에 넣는다.

- `AndroidOptions(encryptedSharedPreferences: true)`
- `AndroidManifest.xml`에 `android:allowBackup="false"`
  지금 백업할 로컬 데이터가 토큰뿐이라 통째로 끄는 편이 단순하다. 백업할 것이 생기면 그때 `dataExtractionRules`로 토큰만 제외하도록 세분화한다

**iOS** — 설정만 넣고 재설치 처리는 미룬다.

- `IOSOptions(accessibility: first_unlock_this_device)` — 기기 밖으로 백업되지 않고, 재부팅 후 첫 잠금해제 전에는 읽히지 않는다
- ⚠️ **iOS Keychain은 앱을 지워도 남는다.** 재설치한 기기에서 이전 사용자 토큰이 살아나므로 "첫 실행이면 한 번 비우기"가 필요한데, 그러려면 **앱과 함께 지워지는 저장소가 하나 더** 있어야 한다(`shared_preferences`). Android만 돌리는 지금 패키지를 더 넣는 것은 이르다. **iOS 전환 시 할 일**이다

---

## 4. 구조

### 저장소 — 읽기를 하나로 합친다

`flutter_secure_storage`는 호출마다 플랫폼 채널을 건너간다. 지금처럼 읽기가 셋으로 흩어져 있으면 **스플래시에서만 왕복이 네 번** 생기고, 나눠 읽는 사이에 값이 어긋날 수 있다.

```dart
class StoredAuth {
  final String? userId;
  final String? accessToken;
  final String? refreshToken;
  final bool isOnboarded;      // 저장된 것이 없으면 false
}

abstract interface class TokenStore {
  Future<StoredAuth> read();                    // 왕복 1회

  Future<void> saveSession({…, isOnboarded});   // 로그인 · 가입
  Future<void> saveTokens({…});                 // 갱신 ← 토큰 둘만
  Future<void> markOnboarded();                 // 온보딩 완료

  Future<void> clearTokens();                   // 401 ← userId·isOnboarded는 남는다
  Future<void> clear();                         // 로그아웃 ← 전부
}
```

빈 문자열은 `read()`에서 `null`로 걸러 내보낸다. 그래야 빈 `refreshToken`을 서버에 보내 `VALIDATION_FAILED`를 받는 일이 없다.

| 구현 | 쓰는 곳 |
|---|---|
| `SecureTokenStore` | 앱 |
| `InMemoryTokenStore` | 테스트. 위젯 테스트는 Keystore를 부를 수 없다 |

`auth_provider.dart:14`의 한 줄만 바뀐다.

### 파일

**PR 1 — 저장소 · 갱신 · 스플래시 분기**

```
신규  core/storage/secure_token_store.dart          flutter_secure_storage 구현
      features/auth/domain/auth_tokens.dart         갱신 결과 (userId 없음)

수정  core/storage/token_store.dart                 StoredAuth · 인터페이스 6개
      features/auth/domain/auth_repository.dart     refresh 추가
      features/auth/domain/auth_session.dart        isOnboarded 추가
      features/auth/domain/auth_failure.dart        sessionExpired · validation
      features/auth/data/http_auth_repository.dart  refresh 구현 · isOnboarded 읽기
      features/auth/data/fake_auth_repository.dart  refresh 구현
      features/auth/presentation/auth_state.dart    returning · isOnboarded
      features/auth/presentation/auth_provider.dart SecureTokenStore · restore 개편
      features/onboarding/presentation/splash_page.dart  분기 · 재시도 UI
      core/strings/app_strings.dart                 재시도 문구
      pubspec.yaml · android/app/src/main/AndroidManifest.xml
```

**PR 2 — 프로필 서버 전송**

```
신규  features/onboarding/domain/gender.dart                Gender enum
      features/onboarding/domain/onboarding_profile.dart    엔티티
      features/onboarding/domain/onboarding_repository.dart  인터페이스
      features/onboarding/domain/onboarding_failure.dart
      features/onboarding/data/onboarding_profile_dto.dart   직렬화 · 720 치환
      features/onboarding/data/http_onboarding_repository.dart
      features/onboarding/presentation/onboarding_provider.dart

수정  features/onboarding/domain/nickname_rule.dart          정규식
      features/onboarding/presentation/profile_setup_page.dart  provider · 전송 · 실패 UI
      features/auth/presentation/auth_provider.dart          markOnboarded 연결
      core/strings/app_strings.dart
```

`ProfileSetupPage`의 화면 상태를 provider로 올린다 — 그 파일 51행 주석이 이 시점을 예고해 뒀다.

---

## 5. 반드시 지켜야 할 것 둘

### ① 갱신 응답의 `refreshToken`을 반드시 덮어쓴다

`ReissueResponse`는 `accessToken`**과 `refreshToken`을 함께** 돌려준다. 서버가 리프레시 토큰을 **회전**시킨다는 뜻이다.

**새 값으로 덮어쓰지 않으면 다음 갱신이 401로 죽는다** — 60일이 남아 있어도.

증상은 "어제는 자동 로그인이 됐는데 오늘은 로그인 화면"이고, 원인에서 한참 떨어진 곳에서 나타난다.

### ② 지우는 메서드를 둘로 나눈다

| | 지우는 것 | 남는 것 |
|---|---|---|
| `clearTokens()` — 401 | accessToken · refreshToken | **userId · isOnboarded** |
| `clear()` — 로그아웃 | 전부 | |

이게 없으면 2-1의 "만료된 사람은 로그인 화면, 처음인 사람은 온보딩 소개"가 성립하지 않는다.

---

## 6. 서버 계약

### 검증 (`POST /users/onboarding`)

| 필드 | 서버 | 앱 |
|---|---|---|
| `nickname` | 2~16 · `^[가-힣a-zA-Z0-9_]+$` | 2~12 + 같은 정규식 |
| `gender` | `MALE` / `FEMALE` | `enum Gender` → 대문자 |
| `birthday` | `LocalDate` · 과거만 | `yyyy-MM-dd` |
| `averagePaceSecondsPerKm` | **필수** 120~1800 | `null`이면 720 |
| `weight` | 20~300 | int → 그대로 |
| `height` | 20~300 | int → 그대로 |

### 실패

| 상황 | 서버 | 앱 |
|---|---|---|
| refresh 만료·무효 | 401 `INVALID_REFRESH_TOKEN` | `sessionExpired` → `clearTokens()` → 로그인 화면 |
| 로그인 실패 | 401 `INVALID_CREDENTIALS` | `invalidCredentials` (그대로) |
| 형식 오류 (인증) | 400 `VALIDATION_FAILED` | `validation` — 2-8 |
| 형식 오류 (온보딩) | 400 `INVALID_REQUEST` · `MALFORMED_REQUEST_BODY` | `validation` — **code가 API마다 다르다** |
| access 만료 (온보딩 전송) | 401 | **refresh 1회 → 재시도.** 입력을 날리지 않는다 |
| 이미 온보딩 | 409 `ALREADY_ONBOARD` | repository가 성공으로 흡수 — 2-7 |
| 5xx | | `server` |
| 응답 없음 | | `network` |

**상태 코드를 1차 근거로 삼고 `code`는 보조로 쓴다.** 노출 정책이 바뀌어도 동작한다.

---

## 7. 테스트

CLAUDE.md가 정한 세 가지 중 둘에 해당한다.

| 무엇 | 왜 |
|---|---|
| `nickname_rule_test` | 순수 계산 로직. 정규식 경계 |
| `onboarding_profile_dto_test` | **`null` → 720 치환**과 성별 대문자 변환. 순수 함수 |
| `token_store_test` | `clearTokens()`가 `userId`를 남기는가 |
| `auth_controller_test` | 상태 전이 — 갱신 성공 / 401 / 네트워크 실패 |
| `splash_page_test` | 네 갈래가 각각 어디로 가는가 |

---

## 8. PR을 둘로 나눈다

전부 세면 22개를 넘는다. CLAUDE.md의 20개 제한을 넘는다.

| | 브랜치 | 내용 | 대략 | 확인 방법 |
|---|---|---|---|---|
| **1** | `feat/auto-sign-in` | 저장소 · 갱신 · 스플래시 분기 | 14~17 | 로그인 → 앱 종료 → 재실행 → **홈으로 바로** |
| **2** | `feat/onboarding-submit` | 프로필 서버 전송 | 12~14 | 프로필 입력 → 앱 종료 → 재실행 → **프로필이 아니라 홈** |

두 PR의 확인 방법이 갈리는 것이 분할선의 근거다. 1은 "토큰이 살아남는가", 2는 "`isOnboarded`가 서버에 켜지는가"다.

⚠️ **PR 1만 머지된 동안에는 모두가 프로필 화면으로 간다.** 서버 `isOnboarded`가 계속 false이기 때문이다. PR 1 설명에 그 사실과 "PR 2가 닫는다"를 적는다.

---

## 9. 한계

### 9-1. `isOnboarded`가 다른 기기와 어긋날 수 있다

`ReissueResponse`에는 `isOnboarded`가 없고, 서버에 조회 API(`GET /users/me` 같은)도 없다. **자동 로그인 경로에서는 로컬 값이 유일한 근거다.**

기기 A에서 온보딩을 마쳐도 기기 B는 모른다. 다만 기기 B가 서버로 전송을 시도하면 409 `ALREADY_ONBOARD`가 오고, 2-7이 그것을 성공으로 흡수하면서 로컬 값이 맞춰진다. **한 번 더 프로필을 입력하는 수고는 남는다.**

조회 API가 생기면 갱신 직후 한 번 물어 로컬 값을 덮어쓴다.

### 9-2. `signOut`이 여전히 서버를 부르지 않는다

`POST /auth/logout`은 있는데 앱이 부르지 않는다. 이번 변경으로 토큰이 저장소에 남으므로 **부를 수 있게는 됐다.** 다만 로그아웃 UI가 없어 이 설계의 범위 밖이다.

---

## 10. 백엔드에 확인 · 요청할 것

| | |
|---|---|
| **확인** | 회전 후 **옛 refreshToken을 무효화**하는지. 무효화하지 않으면 회전을 해도 탈취된 토큰이 60일간 살아 있어 회전의 의미가 없다 |
| **요청** | `averagePaceSecondsPerKm`를 nullable로. 받아들여지면 2-4의 치환 한 줄을 지운다 |
| **요청** | `ReissueResponse`에 `isOnboarded` 추가, 또는 `GET /users/me`. 9-1이 닫힌다 |
