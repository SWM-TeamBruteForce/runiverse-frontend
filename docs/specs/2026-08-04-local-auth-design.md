# 이메일 로그인 · 회원가입 설계

2026-08-04 · 대상 화면 S02.5 · 백엔드 `runiverse-backend` `dev` 브랜치

이 문서는 **무엇을 왜 그렇게 정했는지**만 적는다.
로그인이 어떻게 동작하는지에 대한 설명은 협업 문서(`Runiverse_인증_협업문서.md`)에 있다.

---

## 1. 범위

이메일·비밀번호 로그인과 회원가입, 그리고 자동 로그인까지.
카카오·애플은 다음이다.

백엔드에 이미 있는 것을 쓴다. 새로 요구하는 API는 없다.

| 엔드포인트 | 응답 |
|---|---|
| `POST /api/v1/auth/signup` | 201 `{userId}` |
| `POST /api/v1/auth/login` | 200 `{userId, accessToken, refreshToken}` |
| `POST /api/v1/auth/refresh` | 200 `{accessToken, refreshToken}` |
| `POST /api/v1/auth/logout` | 204 · Bearer 필요 |

---

## 2. 결정

### 2-1. 가입은 온보딩으로, 로그인은 홈으로 보낸다

서버는 **사용자가 온보딩을 마쳤는지 모른다.** `User` 애그리거트에 이메일·비밀번호·provider뿐이고
닉네임도, 약관 동의 기록도 없다.

그래서 서버 없이 쓸 수 있는 유일한 단서를 쓴다 — 가입한 사람은 신규고, 로그인한 사람은 기존이다.

- 가입 성공 → S03 약관 → S04 프로필 → 홈
- 로그인 성공 → 홈

**⚠️ 이 방식의 구멍.** 앱을 지웠다 깔면 기존 사용자도 프로필 없이 홈에 떨어진다.
프로필 API가 생기면 서버 응답으로 갈라야 한다. 그전까지 이 한계를 안고 간다.

### 2-2. 라우팅 보호에 `redirect`를 쓰지 않는다

화면이 직접 `context.go()`로 이동한다.

`redirect`는 조건이 어긋나면 무한 루프가 난다 —
`app_router.dart` 주석에도 이미 경고가 적혀 있다.
그리고 지금은 **딥링크로 홈에 바로 들어올 경로가 없다.** 막을 것이 없는데 관문을 세울 이유가 없다.

딥링크가 생기면 그때 `refreshListenable`과 함께 넣는다.

### 2-3. 에러 문구는 서버 것을 쓰지 않는다

서버 `message`는 이미 한국어다 — `"이미 가입된 이메일입니다."`
그런데 앱 문구는 해요체다 — `"쓸 수 있는 이름이에요"`. 그대로 쓰면 톤이 깨진다.

**`code`를 계약으로 보고 문구는 앱이 정한다.** 모르는 `code`가 왔을 때만 서버 `message`를 그대로 보여준다.

| 서버 code | 앱 문구 |
|---|---|
| `EMAIL_ALREADY_EXISTS` | 이미 가입한 이메일이에요 |
| `INVALID_CREDENTIALS` | 이메일이나 비밀번호가 맞지 않아요 |
| `INVALID_REFRESH_TOKEN` | (문구 없이 조용히 로그아웃) |
| 네트워크 끊김 | 인터넷 연결을 확인해주세요 |
| 500 | 잠시 후 다시 시도해주세요 |

서버가 `INVALID_EMAIL_CREDENTIALS`와 `INVALID_PASSWORD_CREDENTIALS`를 나눠 뒀지만
`ErrorExposurePolicy`에서 빼놔 클라이언트에 오지 않는다.
**의도된 설계다** — 어느 쪽이 틀렸는지 알려주면 이메일 존재 여부가 새어 나간다.
앱도 뭉뚱그린 문구 하나만 쓴다.

### 2-4. 비밀번호 확인 입력칸을 두지 않는다

서버가 확인값을 받지 않고, 화면이 짧아진다.
오타는 **눈 아이콘(보기 토글)**로 막는다. `AppInput`에 `obscureText`를 더한다.

### 2-5. 카카오·애플 버튼은 남기되 준비 중 안내를 띄운다

정본(와이어프레임 S02.5)에 셋 다 있다. 지우면 화면이 정본에서 멀어진다.

비활성 회색 버튼은 "이 앱은 미완성"으로 읽힌다.
CLAUDE.md가 피드·대회일정 탭에 정한 원칙(숨기지 않고, 눌리고, 준비중 화면이 뜬다)을 그대로 따른다.

### 2-6. freezed를 도입하지 않는다

CLAUDE.md는 "상태는 freezed sealed union"이라고 하지만,
Dart 3에 `sealed class`가 언어 기능으로 들어와 있다. 인증 상태는 네 가지뿐이다.

코드 생성 파이프라인(`build_runner`)을 통째로 들이는 비용이 손으로 쓰는 비용보다 크다.
DTO가 수십 개로 늘면 그때 도입한다.

---

## 3. 새 패키지

| 패키지 | 왜 |
|---|---|
| `dio` | 인터셉터가 있어 "Bearer 붙이기"와 "401이면 갱신 후 재시도"를 한 곳에 모을 수 있다. 그 재시도 로직은 앞으로 모든 API가 쓴다. CLAUDE.md에 이미 계획으로 적혀 있다 |
| `flutter_secure_storage` | 리프레시 토큰은 탈취되면 계정을 계속 쓸 수 있는 값이다. 안드로이드 Keystore·iOS Keychain에 암호화해 넣는다. `shared_preferences`는 안드로이드에서 XML 평문이라 부적절하다 |

---

## 4. 구조

```
core/config/app_config.dart          API 주소 (--dart-define)
core/storage/token_store.dart        토큰 읽기·쓰기·비우기
core/network/dio_client.dart         Dio 조립
core/network/auth_interceptor.dart   Bearer 부착 + 401 재시도
core/network/api_exception.dart      {code,message} → Dart 예외

features/auth/domain/        auth_repository · auth_failure · email_rule · password_rule
features/auth/data/          auth_api · auth_dto · auth_repository_impl
features/auth/presentation/  auth_state · auth_provider · 화면 3개
```

**의존 방향을 지키려고 인터셉터에 콜백을 주입한다.**
`AuthInterceptor`가 refresh를 부르는데 그건 auth 기능의 API다.
`core`가 `features`를 import하면 방향이 뒤집힌다.
그래서 인터셉터는 `Future<bool> Function()`을 받고, 배선할 때 채운다.

### 상태

```dart
sealed class AuthState {}
final class AuthUnknown   extends AuthState {}  // 저장된 토큰을 확인하는 중
final class AuthSignedOut extends AuthState {}
final class AuthSignedIn  extends AuthState { final String userId; }
```

폼의 loading·error는 전역 인증 상태가 아니라 화면이 들고 있는 `AsyncValue<void>`다.
로그인 버튼이 도는 것과 "이 앱이 로그인 상태인가"는 다른 질문이다.

---

## 5. 401 재시도에서 반드시 막아야 하는 것 세 가지

```
요청 → 401 → refreshToken 있나 → POST /auth/refresh → 새 토큰 저장 → 원 요청 재시도
                                        └ 실패 → 토큰 삭제 → 로그아웃
```

**① `/auth/login`의 401은 재시도하지 않는다.**
로그인 실패가 401이다. 그대로 두면 비밀번호를 틀릴 때마다 refresh를 부른다.
`signup` `login` `refresh` 세 경로는 인터셉터가 건너뛴다.

**② refresh를 동시에 두 번 부르지 않는다.**
백엔드가 리프레시 토큰을 회전시킨다 — `ReissueResult`가 새 `refreshToken`을 돌려준다.
401이 동시에 여러 개 나면 두 번째 호출은 이미 무효가 된 토큰을 쓰고,
**멀쩡한 세션이 로그아웃된다.** `Future<bool>?` 하나를 공유해 한 번만 부른다.

**③ 재시도한 요청이 또 401이면 멈춘다.** 아니면 무한 루프다.

---

## 6. 비밀번호 규칙이 두 곳에 생긴다

백엔드는 `6~16자` + `영문·숫자·특수문자 각 1개 이상`이다.
이걸 서버에 물어봐서 알 수 없어서 **같은 규칙을 앱에 다시 쓴다.**

**⚠️ 백엔드가 규칙을 바꾸면 앱이 어긋난다.**
그때 증상은 "앱은 통과시켰는데 서버가 400"이다.
`docs/implementation-notes.md`에 항목을 남긴다.

`PasswordRule`은 순수 함수라 테스트한다 — CLAUDE.md가 말한 "순수 계산 로직"에 해당한다.

---

## 7. 테스트

CLAUDE.md가 정한 세 가지 중 둘에 해당한다.

| 무엇 | 왜 |
|---|---|
| `password_rule_test` · `email_rule_test` | 순수 계산 로직 |
| `auth_failure_test` | 서버 code → 앱 실패 매핑. 순수 함수다 |
| `auth_controller_test` | 상태 전이. 가짜 repository를 넣는다 |
| `sign_in_page_test` | 버튼 활성화 조건과 에러 표시 |

---

## 8. PR을 둘로 나눈다

전부 세면 파일 28개다. CLAUDE.md의 20개 제한을 넘는다.

| | 내용 | 대략 |
|---|---|---|
| **A** | 배관 전부 + S02.5 + 로그인 화면 + 자동 로그인 | 20파일 |
| **B** | 가입 화면 + 비밀번호 규칙 + 테스트 | 8파일 |

둘 다 각자 동작한다. A만 머지해도 계정을 `curl`로 만들면 로그인이 된다.

---

## 9. 정본에서 벗어나는 것

**이메일·비밀번호를 입력하는 화면은 정본에 없다.**
와이어프레임 S02.5는 소셜 버튼 셋과 하단 링크뿐이다.
백엔드가 요구하는 건 그 화면이라 새로 만든다.

`docs/implementation-notes.md`에 사유를 남긴다 — S04 페이스 때와 같은 절차다.
