# 이메일 인증 가입 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 서버가 요구하는 이메일 인증 3단계 가입에 앱을 맞춘다. 지금 앱의 회원가입은 dev 서버에서 400으로 실패한다.

**Architecture:** 인증을 마치면 서버가 **`verificationTicket`을 클라이언트에 넘긴다.** 그 티켓이 "이 사람은 이 이메일을 인증했다"는 증거이고, 가입 요청은 이메일 대신 티켓을 보낸다. **티켓은 가입 화면이 들고 있다가 그 화면을 떠날 때 함께 사라진다** — 저장하지 않는다.

**Tech Stack:** Flutter 3.44.8 (fvm) · Riverpod 3 · go_router 17 · dio

**선행:** PR #17(`feat/profile-prompt`)이 `dev`에 머지된 뒤 시작한다. `app_strings.dart`가 겹친다.

**닫은 PR:** #10 — 서버 없이 mock으로 계약을 추측해 만든 것이라 실제와 어긋났다. 브랜치 `feat/auth-verification`은 남아 있고 **아래에서 파일 단위로 가져온다.**

---

## Global Constraints

- **모든 flutter/dart 명령은 fvm SDK로 부른다.** `fvm`이 PATH에 없다:
  `& ".fvm\flutter_sdk\bin\flutter.bat" test` · `& ".fvm\flutter_sdk\bin\dart.bat" format lib test`
- 내부 import는 항상 절대경로 `package:runiverse/...`
- 색·치수·문자열은 토큰으로만: `context.appColors` `AppSpacing` `AppRadius` `AppTypography` `AppStrings`
- 아이콘은 **Lucide만**
- 커밋 메시지는 `<이모지> <Type>: <설명>` — `📍 Feat` `🔨 Fix` `📝 Docs` `🎨 Style` `🤖 Refactor` `✅ Test`
- **AI를 공동 작성자로 넣지 않는다.**
- 각 태스크 끝에 `analyze` 경고 0개
- 한 커밋에 논리적 변경 하나. 각 커밋 시점에 빌드가 되어야 한다
- **서버 주소·포트를 소스나 문서에 적지 않는다.** 주입은 `--dart-define=API_BASE_URL`

---

## 서버 계약 (2026-08-10 배포본 확인)

경로 접두사는 `/api/v1`.

| # | 엔드포인트 | 요청 | 성공 |
|---|---|---|---|
| 1 | `POST /auth/email/verifications` | `{email}` | **204** (몸통 없음) |
| 2 | `POST /auth/email/verifications/confirm` | `{email, code}` | **200** `{verificationTicket}` |
| 3 | `POST /auth/signup` | **`{verificationTicket, password}`** | **201** `{userId, accessToken, refreshToken, isOnboarded}` |

`code`는 **숫자 6자리** (`^\d{6}$`). `password`는 지금 규칙 그대로 (6~16자, 영문·숫자·특수문자 각 하나).

**티켓은 URL-safe base64 랜덤 문자열**이다 — `_YUW5lsbzTgNYp8-B6p73LnLjP6a4YgWlcQnaauHwhc` 같은 모양.
`-` `_`가 섞여 있지만 URL-safe라 **JSON에 그대로 실으면 되고, 앱이 인코딩할 것이 없다.**
길이·모양을 앱이 검증하지 않는다 — 서버가 형식을 바꿔도 앱이 깨지지 않아야 한다.

### 에러 코드

| code | HTTP | 어느 단계 | `AuthFailure` |
|---|---|---|---|
| `EMAIL_ALREADY_EXISTS` | 409 | **발송** (가입에서도) | `emailAlreadyExists` (이미 있음) |
| `EMAIL_VERIFICATION_COOLDOWN` | 429 | 발송 | `sendCooldown` |
| `EMAIL_VERIFICATION_DAILY_LIMIT_EXCEEDED` | 429 | 발송 | `sendDailyLimit` |
| `EMAIL_SEND_FAILED` | 503 | 발송 | `sendFailed` |
| `INVALID_VERIFICATION_CODE` | 400 | 확인 | `invalidCode` |
| `EMAIL_VERIFICATION_NOT_FOUND` | 400 | 확인 | `codeExpired` |
| `TOO_MANY_VERIFICATION_ATTEMPTS` | 429 | 확인 | `tooManyCodeAttempts` |
| `EMAIL_NOT_VERIFIED` | 403 | 가입 | `emailNotVerified` |

⚠️ **`EMAIL_SEND_FAILED`는 503이다.** `HttpAuthRepository._failureOf`가 **5xx를 먼저 `server`로 잘라내므로** 그 앞에서 `code`를 봐야 한다. 지금 코드는 상태 코드를 먼저 본다 — 이 순서를 뒤집지 않으면 `sendFailed`가 영원히 안 나온다.

---

## 반드시 먼저 알아야 할 것 넷

### ① 티켓은 1회용이고, 가입이 실패해도 소비된다

`SignUpHandler`는 `consume(ticket)` → `register(email, password)` 순서다. 등록에서 `EMAIL_ALREADY_EXISTS`가 나면 **티켓은 이미 사라진 뒤**다. Redis라 롤백도 없다.

**그래서 가입 실패는 전부 "인증부터 다시"다.** 화면은 실패 시 티켓을 버리고 인증 단계를 다시 열어야 한다. 티켓을 들고 재시도 버튼을 주면 두 번째도 반드시 실패한다.

### ② 이미 가입된 이메일은 **발송 단계**에서 막힌다

`POST /auth/email/verifications`가 `EMAIL_ALREADY_EXISTS`(409)를 준다. 인증번호를 치기도 전에 알 수 있다 — **사용자가 한 일이 버려지지 않는다.**

⚠️ **2026-08-10 배포본에는 이 검사가 없었다.** 그때는 발송·확인 어느 단계에도 중복 검사가 없어 가입에서야 409가 났다(배포 서버로 확인했다). 발송 단계로 앞당기기로 정해졌으므로 **앱은 새 동작을 기준으로 만든다.**

**그래도 가입 단계의 `EMAIL_ALREADY_EXISTS` 처리를 지우지 않는다.** 발송과 가입 사이에 다른 사람이 같은 이메일로 먼저 가입할 수 있다. 드물지만 그때 앱이 `unknown`을 띄우면 사용자는 무슨 일이 났는지 알 수 없다.

**확인 단계에서는 처리하지 않는다.** 서버가 그 단계에서 이 코드를 주지 않는다.

### ③ 가입 응답이 토큰을 준다 — 재로그인 코드를 지운다

`HttpAuthRepository.signUp`은 지금 signup 뒤에 `_login`을 이어 부른다. 서버가 `SignUpResult`에 토큰을 실어주므로 **그 두 번째 호출이 사라진다.** `isOnboarded`는 가입 직후라 항상 `false`다.

### ④ 카운트다운 5분은 앱의 가정이다

서버 `codeTtl`은 설정값(`EmailVerificationProperties`)이고 응답에 실리지 않는다. yml이 레포에 없어 **실제 값을 모른다.** 5분으로 그리기로 했다(사용자 결정).

**만료 판정은 절대 화면 타이머로 하지 않는다.** 타이머는 숫자를 그릴 뿐이고, 판정은 서버가 `EMAIL_VERIFICATION_NOT_FOUND`로 알려준다. 0이 됐는데 서버는 아직 살아 있을 수도, 반대일 수도 있다.

→ 백엔드에 `expiresIn` 응답을 요청해 두고, 오면 그 값으로 바꾼다.

---

## File Structure

```
신규  features/auth/domain/verification_code_rule.dart      인증번호 모양 규칙
      test/verification_code_rule_test.dart
      test/email_verification_test.dart                     저장소 계층 테스트

수정  features/auth/domain/auth_failure.dart                 실패 사유 7개
      features/auth/domain/auth_repository.dart             메서드 2개 + signUp 시그니처
      features/auth/data/fake_auth_repository.dart          인증 흉내
      features/auth/data/http_auth_repository.dart          엔드포인트 2개 + 코드 매핑
      features/auth/presentation/auth_provider.dart         컨트롤러 메서드 2개
      features/auth/presentation/sign_up_page.dart          3단계로 재작성
      core/strings/app_strings.dart                         문구 12개
      test/sign_up_page_test.dart                           재작성
      test/auth_controller_test.dart                        signUp 호출부
      docs/implementation-notes.md                          티켓 소비 함정
```

---

## PR 분할 — 둘로 나눈다

**한 PR로는 1100줄이 넘는다.** `signUp` 시그니처를 바꾸는 순간 화면이 컴파일되지 않으므로, 그 변경을 두 번째 PR로 미뤄 첫 PR이 온전히 빌드되게 한다.

| | 무엇 | 대략 |
|---|---|---|
| **PR A** | 규칙 · 실패 사유 · 문구 · 저장소 계층에 **메서드 2개 추가** · 컨트롤러 | 9파일 ~500줄 |
| **PR B** | `signUp` 시그니처 변경 · 화면 재작성 · 문서 | 7파일 ~630줄 |

**PR A는 아무도 부르지 않는 코드를 넣는다.** 화면이 없으니 동작이 바뀌지 않는다 — 그래서 안전하고, 리뷰가 계약과 매핑에만 집중된다.

PR B는 500줄을 넘는다. 화면 하나를 반으로 자를 수 없어서다. **PR 본문에 사유를 적는다** (CLAUDE.md의 예외 조항).

---

# PR A — 붙일 준비

**브랜치:** `feat/email-verification-core` (upstream/dev 기준, PR #17 머지 후)

---

## Task A1: 인증번호 규칙

**Files:**
- Create: `lib/features/auth/domain/verification_code_rule.dart`
- Create: `test/verification_code_rule_test.dart`

**Interfaces:**
- Produces: `VerificationCodeRule.of(String) → VerificationCodeStatus` · `VerificationCodeRule.length` · `VerificationCodeRule.ttl`

- [ ] **Step 1: 닫힌 PR에서 그대로 가져온다**

```bash
git fetch upstream 'refs/pull/10/head:pr10'
git show pr10:lib/features/auth/domain/verification_code_rule.dart > lib/features/auth/domain/verification_code_rule.dart
git show pr10:test/verification_code_rule_test.dart > test/verification_code_rule_test.dart
```

**고칠 것이 없다.** 서버 정규식이 `^\d{6}$`로 이 파일과 정확히 같다.

- [ ] **Step 2: `ttl` 주석에 근거를 적는다**

파일의 `ttl` 주석에 **5분이 앱의 가정임**을 남긴다. 지금 주석은 "서버가 `expiresIn`을 응답에 실어주면"이라고만 되어 있어, 값이 어디서 왔는지가 없다.

```dart
  /// ⚠️ **서버 값이 아니라 앱의 가정이다.**
  ///
  /// 서버 `codeTtl`은 설정값(`EmailVerificationProperties`)이고 응답에 실리지 않는다.
  /// 실제 값이 다르면 이 숫자는 틀린다 — 그래서 **판정에 쓰지 않는다.**
  /// 만료는 서버가 `EMAIL_VERIFICATION_NOT_FOUND`로 알려준다.
  static const ttl = Duration(minutes: 5);
```

- [ ] **Step 3: 통과 확인**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/verification_code_rule_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

- [ ] **Step 4: 커밋**

```bash
git add lib/features/auth/domain/verification_code_rule.dart test/verification_code_rule_test.dart
git commit -m "📍 Feat: 인증번호 모양 규칙을 둔다"
```

---

## Task A2: 실패 사유와 문구

**Files:**
- Modify: `lib/features/auth/domain/auth_failure.dart`
- Modify: `lib/core/strings/app_strings.dart`

**이 태스크에는 테스트가 없다.** enum과 상수뿐이다. 쓰이는 것은 A3~A4가 확인한다.

- [ ] **Step 1: `AuthFailure`에 7개를 더한다**

`invalidCredentials` 아래에 넣는다.

```dart
  /// 인증번호 확인: 번호가 맞지 않다. 서버 `INVALID_VERIFICATION_CODE` (400)
  invalidCode,

  /// 인증번호 확인: 발급된 번호가 없다 — 만료됐거나 받은 적이 없다.
  /// 서버 `EMAIL_VERIFICATION_NOT_FOUND` (400)
  ///
  /// [invalidCode]와 나눈 이유는 **사용자가 할 행동이 다르기** 때문이다.
  /// 이쪽은 다시 받아야 하고, 저쪽은 메일을 다시 보고 치면 된다.
  codeExpired,

  /// 인증번호 확인: 시도 횟수를 다 썼다. 서버 `TOO_MANY_VERIFICATION_ATTEMPTS` (429)
  ///
  /// 번호를 다시 받아야 풀린다. 서버가 시도 횟수를 번호에 매달아 두기 때문이다.
  tooManyCodeAttempts,

  /// 발송: 방금 보냈다. 서버 `EMAIL_VERIFICATION_COOLDOWN` (429)
  sendCooldown,

  /// 발송: 하루 한도를 넘겼다. 서버 `EMAIL_VERIFICATION_DAILY_LIMIT_EXCEEDED` (429)
  ///
  /// [sendCooldown]과 달리 **오늘 안에는 풀리지 않는다.** 기다리라고 하면 안 된다.
  sendDailyLimit,

  /// 발송: 메일 서버가 받지 못했다. 서버 `EMAIL_SEND_FAILED` (503)
  ///
  /// ⚠️ 5xx지만 [server]로 흡수하지 않는다. 사용자가 한 일(이메일 입력)은 멀쩡하고
  /// 다시 누르면 될 수 있다 — 화면이 할 말이 다르다.
  sendFailed,

  /// 가입: 티켓이 없거나 만료됐다. 서버 `EMAIL_NOT_VERIFIED` (403)
  ///
  /// **인증을 마치고 비밀번호를 오래 고민하면 여기 온다.** 티켓에도 유효기간이 있다.
  emailNotVerified,
```

- [ ] **Step 2: 문구 12개를 더한다**

`authFailedEmailTaken` 뒤에 넣는다.

```dart
  // ── 이메일 인증 ──────────────────────────────────────────────
  //
  // 이메일 → 인증번호 → 비밀번호 순으로 한 화면에서 열린다.
  // 앞 단계를 마쳐야 다음 칸이 나타난다.

  static const authVerifySend = '인증번호 받기';
  static const authVerifyResend = '다시 받기';

  static const authVerifyLabel = '인증번호';
  static const authVerifyHint = '메일로 보낸 6자리 숫자';
  static const authVerifyConfirm = '확인';

  /// 전송 직후 안내. 메일함을 열어보라고 말해주지 않으면 화면에서 기다린다.
  static const authVerifySent = '메일을 보냈어요. 받은 편지함을 확인해주세요';

  static const authVerifyIncomplete = '숫자 6자리를 입력해주세요';

  /// 인증을 마친 뒤. 이 줄이 없으면 됐는지 안 됐는지 알 수 없다.
  static const authVerifyDone = '인증됐어요';

  /// 이메일을 고쳐서 인증이 풀렸을 때. **왜 풀렸는지**를 밝힌다.
  static const authVerifyReset = '이메일이 바뀌어서 인증을 다시 받아야 해요';

  static const authFailedInvalidCode = '인증번호가 맞지 않아요';
  static const authFailedCodeExpired = '인증번호가 만료됐어요. 다시 받아주세요';
  static const authFailedTooManyAttempts = '인증 시도가 많아요. 인증번호를 다시 받아주세요';
  static const authFailedSendFailed = '메일을 보내지 못했어요. 잠시 후 다시 시도해주세요';

  /// 티켓이 만료돼 처음부터 다시 해야 한다. **"다시 받아주세요"로는 부족하다** —
  /// 티켓은 1회용이라 인증 단계로 돌아가야 한다.
  static const authFailedNotVerified = '인증이 만료됐어요. 인증번호를 다시 받아주세요';

  /// ⚠️ 아래 둘은 **서버 문구를 그대로 쓴다**(사용자 지시).
  /// 다른 문구가 해요체인 것과 다르다. 톤을 맞추려면 리뷰에서 정한다.
  static const authFailedSendCooldown = '인증 메일을 방금 보냈습니다. 잠시 후 다시 시도해 주세요.';
  static const authFailedSendDailyLimit = '하루 인증 메일 발송 횟수를 초과했습니다.';
```

- [ ] **Step 3: analyze**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 경고 0개

⚠️ `sign_up_page.dart`의 `_FailureNotice._message`가 **`switch`로 모든 `AuthFailure`를 나열**한다. 사유를 7개 더하면 그 `switch`가 exhaustive하지 않아 깨진다. **여기서 그 화면의 `switch`에 새 사유를 임시로 `authFailedUnknown`에 묶는다** — PR B가 제대로 나눈다.

```dart
    AuthFailure.invalidCredentials ||
    AuthFailure.sessionExpired ||
    // 아직 이 화면에 인증 단계가 없다. PR B에서 각자 문구를 받는다.
    AuthFailure.invalidCode ||
    AuthFailure.codeExpired ||
    AuthFailure.tooManyCodeAttempts ||
    AuthFailure.sendCooldown ||
    AuthFailure.sendDailyLimit ||
    AuthFailure.sendFailed ||
    AuthFailure.emailNotVerified ||
    AuthFailure.unknown => AppStrings.authFailedUnknown,
```

- [ ] **Step 4: 커밋**

```bash
git add lib/features/auth/domain/auth_failure.dart lib/core/strings/app_strings.dart lib/features/auth/presentation/sign_up_page.dart
git commit -m "📍 Feat: 이메일 인증 실패 사유와 문구를 더한다"
```

---

## Task A3: 저장소 인터페이스와 가짜 구현

**Files:**
- Modify: `lib/features/auth/domain/auth_repository.dart`
- Modify: `lib/features/auth/data/fake_auth_repository.dart`
- Create: `test/email_verification_test.dart`

**Interfaces:**
- Produces: `AuthRepository.sendVerificationCode(String)` · `AuthRepository.verifyCode({email, code}) → String`

**`signUp`은 이 PR에서 건드리지 않는다.** 바꾸는 순간 화면이 깨진다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/email_verification_test.dart`를 만든다. **가짜 저장소가 서버 규칙을 흉내 내는지**를 본다.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';

/// 이메일 인증 3단계 — 가짜 저장소가 서버 규칙을 흉내 내는가.
///
/// 여기서 보는 것은 **티켓의 수명**이다. 서버에서 티켓은 1회용이고 가입이
/// 실패해도 소비된다. 가짜가 그것을 흉내 내지 않으면, 실패 후 재시도가
/// 되는 것처럼 보이는 화면을 만들고 실제 서버에서만 깨진다.
void main() {
  FakeAuthRepository make() => FakeAuthRepository(latency: Duration.zero);

  group('인증번호 확인', () {
    test('맞는 번호를 내면 티켓이 나온다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');

      final ticket = await repo.verifyCode(
        email: 'new@example.com',
        code: repo.lastCode!,
      );

      expect(ticket, isNotEmpty);
    });

    test('틀린 번호는 invalidCode다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');

      await expectLater(
        repo.verifyCode(email: 'new@example.com', code: '000000'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.invalidCode,
          ),
        ),
      );
    });

    test('보낸 적 없는 이메일은 codeExpired다', () async {
      final repo = make();

      await expectLater(
        repo.verifyCode(email: 'nobody@example.com', code: '123456'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.codeExpired,
          ),
        ),
      );
    });

    test('맞은 번호는 두 번 쓸 수 없다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');
      final code = repo.lastCode!;
      await repo.verifyCode(email: 'new@example.com', code: code);

      // 서버는 맞은 코드를 지운다. 같은 번호로 티켓을 또 받으면 안 된다.
      await expectLater(
        repo.verifyCode(email: 'new@example.com', code: code),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('발송 제한', () {
    test('연달아 보내면 sendCooldown이다', () async {
      final repo = make();
      await repo.sendVerificationCode('new@example.com');

      await expectLater(
        repo.sendVerificationCode('new@example.com'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.sendCooldown,
          ),
        ),
      );
    });

    test('이미 가입된 이메일은 보내기 전에 막힌다', () async {
      final repo = make();
      repo.seedAccount(email: 'taken@example.com', password: 'runi123!');

      // 인증번호를 치기도 전에 알려주는 것이 이 단계의 존재 이유다.
      await expectLater(
        repo.sendVerificationCode('taken@example.com'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.emailAlreadyExists,
          ),
        ),
      );
    });

    test('가입된 이메일로 두 번 눌러도 이유가 바뀌지 않는다', () async {
      final repo = make();
      repo.seedAccount(email: 'taken@example.com', password: 'runi123!');

      // 중복을 쿨다운보다 먼저 보지 않으면 두 번째가 sendCooldown이 된다.
      for (var i = 0; i < 2; i++) {
        await expectLater(
          repo.sendVerificationCode('taken@example.com'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.failure,
              'failure',
              AuthFailure.emailAlreadyExists,
            ),
          ),
        );
      }
    });
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/email_verification_test.dart
```
기대: 컴파일 실패 — 메서드가 없다.

- [ ] **Step 3: 인터페이스에 메서드 둘을 더한다**

`auth_repository.dart`의 `signIn` 아래에 넣는다.

```dart
  /// 이메일로 인증번호를 보낸다.
  ///
  /// **이미 가입된 이메일이면 여기서 `emailAlreadyExists`가 난다.** 인증번호를
  /// 치기도 전에 알려주는 것이 중요하다 — 다 치고 나서 알려주면 사용자가 한 일이
  /// 통째로 버려진다.
  ///
  /// 실패: `emailAlreadyExists` · `sendCooldown` · `sendDailyLimit` · `sendFailed`
  Future<void> sendVerificationCode(String email);

  /// 인증번호를 확인하고 **티켓을 받는다.**
  ///
  /// 이 티켓이 "이 사람은 이 이메일을 인증했다"는 증거고, [signUp]에 넘긴다.
  /// **서버는 티켓을 한 번만 받아준다** — 저장하지 말고 그 화면에서만 들고 있는다.
  ///
  /// 티켓은 URL-safe base64 문자열이다. 앱은 **모양을 검사하지 않는다** —
  /// 서버가 형식을 바꿔도 앱이 깨지지 않아야 한다.
  ///
  /// 실패: `invalidCode` · `codeExpired` · `tooManyCodeAttempts`
  Future<String> verifyCode({required String email, required String code});
```

- [ ] **Step 4: `FakeAuthRepository`에 구현한다**

필드를 더한다.

```dart
  /// 보낸 인증번호. 이메일 하나당 하나만 산다 — 새로 보내면 옛것은 죽는다.
  final Map<String, String> _codes = {};

  /// 마지막으로 보낸 번호. **테스트가 메일함을 열 수 없으니** 여기서 꺼내 쓴다.
  String? lastCode;

  /// 발급한 티켓 → 이메일. 서버가 Redis에 두는 것과 같은 역할이다.
  final Map<String, String> _tickets = {};

  /// 방금 보낸 이메일. 쿨다운을 흉내 낸다.
  final Set<String> _cooldown = {};

  int _ticketSeq = 0;
```

메서드를 더한다.

```dart
  @override
  Future<void> sendVerificationCode(String email) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    // ⚠️ 중복을 **쿨다운보다 먼저** 본다. 뒤에 두면 이미 가입된 이메일로
    // 두 번 눌렀을 때 두 번째가 sendCooldown이 되어, 같은 조작에 다른 이유가
    // 나온다. 사용자는 무엇이 문제인지 알 수 없다.
    if (_accounts.containsKey(key)) {
      throw const AuthException(AuthFailure.emailAlreadyExists);
    }
    if (!_cooldown.add(key)) {
      throw const AuthException(AuthFailure.sendCooldown);
    }

    // 고정값이다. 무작위로 만들면 테스트가 번호를 알 수 없다.
    const code = '123456';
    _codes[key] = code;
    lastCode = code;
  }

  @override
  Future<String> verifyCode({
    required String email,
    required String code,
  }) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    final issued = _codes[key];
    // 보낸 적이 없는 것과 만료된 것을 서버가 같은 코드로 답한다. 여기도 같게 둔다.
    if (issued == null) {
      throw const AuthException(AuthFailure.codeExpired);
    }
    if (issued != code) {
      throw const AuthException(AuthFailure.invalidCode);
    }

    // 맞은 번호는 지운다. 같은 번호로 티켓을 여러 장 받을 수 없다.
    _codes.remove(key);
    _cooldown.remove(key);

    _ticketSeq++;
    final ticket = 'fake-ticket-$_ticketSeq';
    _tickets[ticket] = key;
    return ticket;
  }

  /// **기다리지 않고** 티켓을 만든다. 인증을 마친 상태를 세우는 용도다.
  ///
  /// [issueSession]과 같은 이유로 동기다 — `testWidgets`는 가짜 시간 위에서 돌고,
  /// `pumpWidget` 전에 `Future`를 기다리면 멈춘다.
  String issueTicket(String email) {
    _ticketSeq++;
    final ticket = 'fake-ticket-$_ticketSeq';
    _tickets[ticket] = _normalize(email);
    return ticket;
  }

  /// 티켓을 **소비하고** 이메일을 돌려준다. 없으면 `null`.
  ///
  /// PR B의 `signUp`이 쓴다. 서버 `SignUpHandler`가 하는 일과 같다.
  String? consumeTicket(String ticket) => _tickets.remove(ticket);
```

- [ ] **Step 5: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/email_verification_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

- [ ] **Step 6: 커밋**

```bash
git add lib/features/auth/domain/auth_repository.dart lib/features/auth/data/fake_auth_repository.dart test/email_verification_test.dart
git commit -m "📍 Feat: 가짜 저장소가 이메일 인증을 흉내 낸다"
```

---

## Task A4: 서버 호출

> **실행 중 발견:** A3과 **한 커밋으로 묶었다.** 인터페이스에 메서드를 더하는
> 순간 `HttpAuthRepository`와 `auth_controller_test`의 `_OfflineAuthRepository`가
> 함께 깨진다 — A3만 커밋하면 그 시점에 빌드되지 않는다.
> `sign_in_page.dart`의 `switch`도 A2에서 함께 고쳐야 했다(계획에 없었다).

**Files:**
- Modify: `lib/features/auth/data/http_auth_repository.dart`

**이 태스크에는 테스트가 없다.** dio를 세우는 비용이 크고, 이 저장소가 하는 일은 경로와 코드 매핑뿐이다. **매핑이 맞는지는 에뮬레이터로 본다** (Task B4).

- [ ] **Step 1: 경로 둘을 더한다**

```dart
  static const _sendCodePath = '/api/v1/auth/email/verifications';
  static const _verifyCodePath = '/api/v1/auth/email/verifications/confirm';
```

- [ ] **Step 2: `_failureOf`의 순서를 뒤집는다**

⚠️ **이것이 이 태스크의 핵심이다.** 지금은 5xx를 먼저 `server`로 잘라낸다. `EMAIL_SEND_FAILED`가 **503**이라 그 앞에서 `code`를 봐야 한다.

```dart
  AuthFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return AuthFailure.network;
    }

    final body = error.response?.data;
    final code = body is Map ? body['code'] : null;

    // ⚠️ 상태 코드보다 `code`를 먼저 본다. EMAIL_SEND_FAILED가 503이라
    // 5xx를 먼저 자르면 그 사유가 영원히 나오지 않는다.
    final known = switch (code) {
      'INVALID_CREDENTIALS' => AuthFailure.invalidCredentials,
      'EMAIL_ALREADY_EXISTS' => AuthFailure.emailAlreadyExists,
      'INVALID_REFRESH_TOKEN' => AuthFailure.sessionExpired,
      'INVALID_VERIFICATION_CODE' => AuthFailure.invalidCode,
      'EMAIL_VERIFICATION_NOT_FOUND' => AuthFailure.codeExpired,
      'TOO_MANY_VERIFICATION_ATTEMPTS' => AuthFailure.tooManyCodeAttempts,
      'EMAIL_VERIFICATION_COOLDOWN' => AuthFailure.sendCooldown,
      'EMAIL_VERIFICATION_DAILY_LIMIT_EXCEEDED' => AuthFailure.sendDailyLimit,
      'EMAIL_SEND_FAILED' => AuthFailure.sendFailed,
      'EMAIL_NOT_VERIFIED' => AuthFailure.emailNotVerified,
      _ => null,
    };
    if (known != null) return known;

    if (code == 'VALIDATION_FAILED') {
      if (kDebugMode) {
        debugPrint('[api] 검증 거절: ${body is Map ? body['message'] : ''}');
      }
      return AuthFailure.validation;
    }

    // 아는 코드가 없을 때만 상태 코드로 판단한다.
    if ((error.response?.statusCode ?? 0) >= 500) return AuthFailure.server;
    return AuthFailure.unknown;
  }
```

- [ ] **Step 3: 메서드 둘을 구현한다**

```dart
  @override
  Future<void> sendVerificationCode(String email) async {
    try {
      // 204라 몸통이 없다. 읽을 것이 없으니 타입을 세우지 않는다.
      await _dio.post<void>(_sendCodePath, data: {'email': email});
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }

  @override
  Future<String> verifyCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _verifyCodePath,
        data: {'email': email, 'code': code},
      );
      final ticket = response.data?['verificationTicket'];
      // 200을 받아도 티켓이 없으면 가입을 시작할 수 없다. 빈 문자열로
      // 넘기면 가입 단계에서 403이 나고 원인이 한참 떨어진 곳에 남는다.
      if (ticket is! String || ticket.isEmpty) {
        throw const AuthException(AuthFailure.unknown);
      }
      return ticket;
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }
```

- [ ] **Step 4: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 전체 PASS · 경고 0개

- [ ] **Step 5: 커밋**

```bash
git add lib/features/auth/data/http_auth_repository.dart
git commit -m "📍 Feat: 이메일 인증 두 엔드포인트를 부른다"
```

---

## Task A5: 컨트롤러

**Files:**
- Modify: `lib/features/auth/presentation/auth_provider.dart`
- Modify: `test/auth_controller_test.dart`

- [ ] **Step 1: 테스트를 더한다**

`auth_controller_test.dart`에 묶음을 더한다. **상태가 바뀌지 않는 것**이 핵심이다.

```dart
  group('이메일 인증', () {
    test('인증번호를 확인해도 로그인 상태가 되지 않는다', () async {
      final repository = FakeAuthRepository(latency: Duration.zero);
      final container = makeContainer(repository: repository);
      final controller = container.read(authControllerProvider.notifier);

      await controller.sendVerificationCode('new@example.com');
      final result = await controller.verifyCode(
        email: 'new@example.com',
        code: repository.lastCode!,
      );

      expect(result.ticket, isNotNull);
      expect(result.failure, isNull);
      // 인증은 신원 확인일 뿐 로그인이 아니다. 여기서 AuthSignedIn이 되면
      // 비밀번호도 안 정한 사람이 홈에 들어간다.
      expect(container.read(authControllerProvider), isA<AuthUnknown>());
    });

    test('실패하면 이유를 돌려주고 티켓은 없다', () async {
      final repository = FakeAuthRepository(latency: Duration.zero);
      final container = makeContainer(repository: repository);
      final controller = container.read(authControllerProvider.notifier);

      await controller.sendVerificationCode('new@example.com');
      final result = await controller.verifyCode(
        email: 'new@example.com',
        code: '000000',
      );

      expect(result.ticket, isNull);
      expect(result.failure, AuthFailure.invalidCode);
    });
  });
```

⚠️ 기존 파일의 컨테이너 생성 헬퍼 이름이 `makeContainer`가 아닐 수 있다. **파일을 먼저 읽고 그 이름을 쓴다.**

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/auth_controller_test.dart
```
기대: 컴파일 실패

- [ ] **Step 3: 컨트롤러에 메서드 둘을 더한다**

`signUp` 아래에 넣는다.

```dart
  /// 성공하면 `null`. **상태를 바꾸지 않는다.**
  Future<AuthFailure?> sendVerificationCode(String email) async {
    try {
      await _repository.sendVerificationCode(email);
      return null;
    } on AuthException catch (error) {
      return error.failure;
    }
  }

  /// 성공하면 `ticket`, 실패하면 `failure`. **둘 중 하나만 채워진다.**
  ///
  /// ## 왜 상태를 바꾸지 않는가
  ///
  /// 인증은 **신원 확인이지 로그인이 아니다.** 여기서 [AuthSignedIn]으로 만들면
  /// 비밀번호도 정하지 않은 사람이 홈에 들어간다. 토큰이 생기는 곳은 [signUp]뿐이다.
  ///
  /// ## 티켓을 저장하지 않는다
  ///
  /// 가입 화면이 받아서 들고 있다가 [signUp]에 넘긴다. 저장소에 넣으면 지울
  /// 자리를 따로 찾아야 하고, 앱을 껐다 켠 사람에게 남아 있을 이유가 없다.
  Future<({String? ticket, AuthFailure? failure})> verifyCode({
    required String email,
    required String code,
  }) async {
    try {
      final ticket = await _repository.verifyCode(email: email, code: code);
      return (ticket: ticket, failure: null);
    } on AuthException catch (error) {
      return (ticket: null, failure: error.failure);
    }
  }
```

- [ ] **Step 4: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 전체 PASS · 경고 0개

- [ ] **Step 5: 커밋**

```bash
git add lib/features/auth/presentation/auth_provider.dart test/auth_controller_test.dart
git commit -m "📍 Feat: 컨트롤러가 인증번호 발송과 확인을 맡는다"
```

---

## Task A6: PR A를 연다

- [ ] **Step 1: 전체를 돌린다**

```powershell
& ".fvm\flutter_sdk\bin\dart.bat" format lib test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug
```

⚠️ `format`이 이번에 손대지 않은 파일을 바꾸면 되돌린다 (`git checkout -- <파일>`).
지난 세 PR에서 `dio_client.dart`와 `home_page_test.dart`가 매번 걸렸다.

- [ ] **Step 2: PR을 연다**

```bash
git push -u origin feat/email-verification-core
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend --base dev \
  --title "📍 Feat: 이메일 인증 계약을 앱에 옮긴다"
```

**base가 `dev`인지 확인한다.**

💬 리뷰 포인트에 적는다.

- **동작이 바뀌지 않는다** — 화면이 아직 이 코드를 부르지 않는다. PR B가 붙인다
- **`_failureOf`의 순서를 뒤집었다** — `EMAIL_SEND_FAILED`가 503이라 5xx를 먼저 자르면 그 사유가 안 나온다. 이 PR에서 가장 실수하기 쉬운 곳이다
- **쿨다운·일일 한도 문구는 서버 문구를 그대로 썼다** (지시). 다른 문구가 해요체라 톤이 섞인다 — 해요체로 옮길지 정해달라
- **`emailNotVerified`가 아직 안 쓰인다** — PR B의 `signUp`이 쓴다
- **중복 검사가 발송 단계에 있다고 전제했다** — 가짜 저장소가 그렇게 동작한다. 배포가 아직이면 실제 서버에서만 가입 단계에서 409가 난다(앱은 양쪽 다 처리한다)
- **가짜 저장소에서 중복을 쿨다운보다 먼저 본다** — 뒤에 두면 같은 조작에 두 번째만 다른 이유가 나온다. 테스트가 있다
- 티켓 저장 위치를 화면에 뒀다 — 저장소에 넣지 않은 이유는 `AuthController.verifyCode` 주석에

---

# PR B — 붙이기

**브랜치:** `feat/email-verification-ui` (PR A 머지 후)

---

## Task B1: `signUp` 시그니처를 바꾼다

**Files:**
- Modify: `lib/features/auth/domain/auth_repository.dart`
- Modify: `lib/features/auth/data/fake_auth_repository.dart`
- Modify: `lib/features/auth/data/http_auth_repository.dart`
- Modify: `lib/features/auth/presentation/auth_provider.dart`

**이 태스크는 화면을 깨뜨린다.** B2가 고친다. 커밋은 B2와 **함께** 한다 — 중간 커밋이 빌드되지 않기 때문이다.

- [ ] **Step 1: 인터페이스**

```dart
  /// 인증을 마치고 받은 티켓으로 가입한다.
  ///
  /// **이메일을 받지 않는다** — 티켓 안에 들어 있다. 서버가 티켓에서 꺼내 쓴다.
  ///
  /// ## ⚠️ 티켓은 실패해도 소비된다
  ///
  /// 서버는 티켓을 먼저 소비하고 계정을 만든다. `emailAlreadyExists`로 실패하면
  /// **그 티켓은 이미 없다.** 화면은 실패를 받으면 티켓을 버리고 인증 단계를
  /// 다시 열어야 한다 — 같은 티켓으로 재시도하면 반드시 `emailNotVerified`다.
  ///
  /// 실패: `emailAlreadyExists` · `emailNotVerified` · `validation`
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  });
```

- [ ] **Step 2: `FakeAuthRepository.signUp`**

A3에서 만든 `consumeTicket`을 쓴다. **서버와 같은 순서**여야 한다.

```dart
  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) async {
    await Future<void>.delayed(latency);

    // ⚠️ 서버와 같은 순서다 — 티켓을 **먼저** 소비하고 계정을 만든다.
    // 순서를 바꾸면 실패했을 때 티켓이 남아, 실제 서버에선 안 되는 재시도가
    // 테스트에서만 통과한다.
    final email = consumeTicket(verificationTicket);
    if (email == null) {
      throw const AuthException(AuthFailure.emailNotVerified);
    }

    if (_accounts.containsKey(email)) {
      throw const AuthException(AuthFailure.emailAlreadyExists);
    }
    _accounts[email] = password;
    return _sessionFor(email);
  }
```

- [ ] **Step 3: `HttpAuthRepository.signUp` — 재로그인을 지운다**

```dart
  /// 가입 응답이 **토큰까지 준다.** 이어서 로그인할 필요가 없다.
  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _signUpPath,
        data: {
          'verificationTicket': verificationTicket,
          'password': password,
        },
      );
      return _sessionOf(response.data);
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }
```

⚠️ `_sessionOf`는 그대로 쓴다. 가입 응답의 필드 이름이 로그인과 같다.
`isOnboarded`는 가입 직후라 서버가 항상 `false`를 준다.

- [ ] **Step 4: `AuthController.signUp`**

```dart
  /// 성공하면 `null`.
  Future<AuthFailure?> signUp({
    required String verificationTicket,
    required String password,
  }) => _authenticate(
    () => _repository.signUp(
      verificationTicket: verificationTicket,
      password: password,
    ),
  );
```

---

## Task B2: 가입 화면을 3단계로 만든다

**Files:**
- Modify: `lib/features/auth/presentation/sign_up_page.dart`
- Modify: `test/sign_up_page_test.dart`

**Interfaces:**
- Consumes: `AuthController.sendVerificationCode` · `verifyCode` · `signUp` · `VerificationCodeRule`

- [ ] **Step 1: 닫힌 PR의 화면을 가져온다**

```bash
git show pr10:lib/features/auth/presentation/sign_up_page.dart > lib/features/auth/presentation/sign_up_page.dart
```

이 화면이 이미 갖고 있는 것 — **그대로 둔다.**

| 무엇 | 왜 좋은가 |
|---|---|
| `_verifiedEmail`에 **이메일 자체**를 담고 현재 입력과 비교 | `bool _verified` 하나면 A로 인증받고 B로 가입하는 구멍이 생긴다. 비교식이라 입력이 바뀌면 저절로 풀린다 |
| 단계별로 칸이 열린다 | 비밀번호를 다 지어놓고 인증에서 막히면 그 일이 버려진다 |
| 카운트다운은 표시 전용 | 판정은 서버가 한다 |
| `_codeSentTo` · `_justSent` · `_verificationReset` | 왜 이 상태인지를 화면이 말해준다 |

- [ ] **Step 2: 티켓을 들고 있게 고친다**

필드를 더한다.

```dart
  /// 인증을 마치고 받은 티켓. **가입 요청에 이것을 보낸다.**
  ///
  /// 저장하지 않는다 — 이 화면이 사라지면 함께 사라진다.
  /// 서버가 한 번만 받아주므로 실패하면 반드시 버린다.
  String? _ticket;
```

`_verify()`에서 티켓을 받는다.

```dart
    final result = await ref
        .read(authControllerProvider.notifier)
        .verifyCode(email: _normalizedEmail, code: _code.text);

    if (!mounted) return;

    setState(() {
      _verifying = false;
      _failure = result.failure;
      if (result.ticket != null) {
        _ticket = result.ticket;
        _verifiedEmail = _normalizedEmail;
        _ticker?.cancel();
      }
    });
```

이메일이 바뀌어 인증이 풀리면 **티켓도 버린다.** `_onEmailChanged`에서:

```dart
  void _onEmailChanged(String _) {
    setState(() {
      _failure = null;
      // 이메일이 바뀌면 그 티켓은 다른 사람 것이다. 들고 있으면 안 된다.
      if (!_verified) _ticket = null;
    });
  }
```

- [ ] **Step 3: 발송 실패를 이메일 칸에서 만난다**

이미 가입된 이메일이면 **[인증번호 받기]를 누른 그 자리에서** 막힌다. 인증번호 칸을 열지 않는다.

```dart
  Future<void> _send() async {
    if (!_emailValid || _busy) return;

    setState(() {
      _sending = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .sendVerificationCode(_normalizedEmail);

    if (!mounted) return;

    setState(() {
      _sending = false;
      _failure = failure;
      if (failure == null) {
        _codeSentTo = _normalizedEmail;
        _justSent = true;
        _startCountdown();
      }
    });
  }
```

**실패하면 `_codeSentTo`를 세우지 않는다** — 그래서 인증번호 칸이 열리지 않는다.
`emailAlreadyExists`일 때 사용자가 갈 곳은 바로 아래 **"이미 계정이 있나요? 로그인"** 이다.
그 버튼이 이미 화면에 있으므로 따로 만들지 않는다.

- [ ] **Step 4: 가입 실패를 인증 단계로 되돌린다**

⚠️ **이 PR에서 가장 중요한 동작이다.**

```dart
  Future<void> _submit() async {
    final ticket = _ticket;
    if (ticket == null || !_canSubmit) return;

    setState(() {
      _submitting = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .signUp(verificationTicket: ticket, password: _password.text);

    if (!mounted) return;

    setState(() {
      _submitting = false;
      _failure = failure;

      // ⚠️ 실패했으면 티켓을 반드시 버린다.
      //
      // 서버는 티켓을 **먼저** 소비하고 계정을 만든다. 이미 가입된 이메일로
      // 실패했어도 그 티켓은 없다. 들고 있으면 사용자가 다시 눌렀을 때
      // emailNotVerified가 나고, 왜 이유가 바뀌는지 알 수 없다.
      if (failure != null) {
        _ticket = null;
        _verifiedEmail = null;
      }
    });

    if (failure == null) {
      // 가입에 성공하면 이미 로그인된 상태다. 약관은 앞에서 받았으므로
      // 남은 것은 프로필뿐이다.
      context.go(AppRoutes.profileSetup);
    }
  }
```

- [ ] **Step 5: `_FailureNotice`에 사유 7개를 나눈다**

A2에서 `authFailedUnknown`에 묶어 둔 것을 푼다.

```dart
  String get _message => switch (failure) {
    AuthFailure.emailAlreadyExists => AppStrings.authFailedEmailTaken,
    AuthFailure.invalidCode => AppStrings.authFailedInvalidCode,
    AuthFailure.codeExpired => AppStrings.authFailedCodeExpired,
    AuthFailure.tooManyCodeAttempts => AppStrings.authFailedTooManyAttempts,
    AuthFailure.sendCooldown => AppStrings.authFailedSendCooldown,
    AuthFailure.sendDailyLimit => AppStrings.authFailedSendDailyLimit,
    AuthFailure.sendFailed => AppStrings.authFailedSendFailed,
    AuthFailure.emailNotVerified => AppStrings.authFailedNotVerified,
    AuthFailure.network => AppStrings.authFailedNetwork,
    AuthFailure.server => AppStrings.authFailedServer,
    AuthFailure.validation => AppStrings.authFailedValidation,
    AuthFailure.invalidCredentials ||
    AuthFailure.sessionExpired ||
    AuthFailure.unknown => AppStrings.authFailedUnknown,
  };
```

- [ ] **Step 6: 테스트를 가져와 고친다**

```bash
git show pr10:test/sign_up_page_test.dart > test/sign_up_page_test.dart
```

**더할 것 셋** — PR #10에 없던 동작이다.

```dart
  testWidgets('이미 가입된 이메일이면 인증번호 칸이 열리지 않는다', (tester) async {
    final repository = FakeAuthRepository(latency: Duration.zero);
    repository.seedAccount(email: 'taken@example.com', password: 'runi123!');

    await pumpSignUp(tester, repository: repository);
    await tester.enterText(find.byType(AppInput).first, 'taken@example.com');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, AppStrings.authVerifySend));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedEmailTaken), findsOneWidget);
    // 칸이 열리면 사용자는 오지 않을 메일을 기다린다.
    expect(find.text(AppStrings.authVerifyLabel), findsNothing);
  });

  testWidgets('가입에 실패하면 인증이 풀린다', (tester) async {
    // 인증을 마친 뒤 누군가 같은 이메일로 먼저 가입한 상황이다. 드물지만
    // 서버는 409를 주고, 그때 티켓은 **이미 소비됐다.**
    final repository = FakeAuthRepository(latency: Duration.zero);

    await pumpSignUp(tester, repository: repository);
    await verifyEmail(tester, 'race@example.com', repository);
    // 인증을 마친 다음에 심는다. 먼저 심으면 발송 단계에서 막혀 여기까지 못 온다.
    repository.seedAccount(email: 'race@example.com', password: 'runi123!');

    await enterPassword(tester, 'runi123!');
    await tester.tap(find.widgetWithText(AppButton, AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedEmailTaken), findsOneWidget);
    // 인증됨 표시가 사라지고 인증번호 받기가 다시 열린다.
    expect(find.text(AppStrings.authVerifyDone), findsNothing);
  });

  testWidgets('이메일을 고치면 인증이 풀린다', (tester) async {
    final repository = FakeAuthRepository(latency: Duration.zero);

    await pumpSignUp(tester, repository: repository);
    await verifyEmail(tester, 'new@example.com', repository);
    expect(find.text(AppStrings.authVerifyDone), findsOneWidget);

    await tester.enterText(find.byType(AppInput).first, 'other@example.com');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authVerifyReset), findsOneWidget);
  });
```

⚠️ `verifyEmail` 헬퍼는 `repository.lastCode!`를 써야 한다. 무작위 번호를 만들면 테스트가 맞출 수 없다.

- [ ] **Step 7: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 전체 PASS · 경고 0개

- [ ] **Step 8: 커밋 (B1과 함께)**

```bash
git add lib/features/auth lib/core/strings/app_strings.dart test/sign_up_page_test.dart test/auth_controller_test.dart
git commit -m "📍 Feat: 인증 티켓으로 가입한다"
```

---

## Task B3: 문서

**Files:**
- Modify: `docs/implementation-notes.md`

- [ ] **Step 1: 함정을 적는다**

§9 뒤에 넣는다.

```markdown
### 9-4. 이메일 인증 티켓 — 실패해도 소비된다

가입은 세 단계다. 발송 → 확인(**티켓을 받는다**) → 가입(**티켓을 보낸다**).
이메일은 티켓 안에 들어 있어 가입 요청이 따로 받지 않는다.

**티켓은 1회용이고, 가입이 실패해도 소비된다.** 서버 `SignUpHandler`가
`consume(ticket)`을 먼저 하고 계정을 만들기 때문이다. Redis라 롤백도 없다.

⚠️ **그래서 가입 실패에 "다시 시도" 버튼을 주면 안 된다.** 두 번째는 반드시
`EMAIL_NOT_VERIFIED`가 나고, 사용자는 이유가 바뀌는 것만 본다.
실패하면 티켓을 버리고 인증 단계를 다시 연다.

**이미 가입된 이메일은 발송 단계에서 막힌다.** `POST /auth/email/verifications`가
`EMAIL_ALREADY_EXISTS`(409)를 준다 — 인증번호를 치기 전에 알 수 있다.

⚠️ 2026-08-10 배포본에는 이 검사가 없어 가입 단계에서야 409가 났다.
**가입 단계의 처리를 지우지 않는 이유**는 발송과 가입 사이에 다른 사람이 같은
이메일로 먼저 가입할 수 있어서다. 드물지만 그때 `unknown`을 띄우면 사용자는
무슨 일이 났는지 알 수 없다.

**카운트다운 5분은 앱의 가정이다.** 서버 `codeTtl`은 설정값이고 응답에 실리지
않는다. 만료 판정은 절대 화면 타이머로 하지 않는다 — 서버가
`EMAIL_VERIFICATION_NOT_FOUND`로 알려준다.

⚠️ **`EMAIL_SEND_FAILED`는 503이다.** `_failureOf`가 상태 코드보다 `code`를
먼저 보는 이유가 이것이다. 5xx를 먼저 자르면 이 사유가 영원히 나오지 않는다.
```

- [ ] **Step 2: 커밋**

```bash
git add docs/implementation-notes.md
git commit -m "📝 Docs: 인증 티켓이 실패해도 소비되는 것을 기록"
```

---

## Task B4: 에뮬레이터 확인과 PR

- [ ] **Step 1: 전체를 돌린다**

```powershell
& ".fvm\flutter_sdk\bin\dart.bat" format lib test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug --dart-define=API_BASE_URL=<주입>
```

- [ ] **Step 2: 에뮬레이터에서 확인한다**

**실제 메일을 받아야 한다.** 인증번호는 서버가 메일로만 보낸다.

| # | 조작 | 기대 |
|---|---|---|
| 1 | **이미 가입된 이메일** → [인증번호 받기] | "이미 가입한 이메일이에요" · **인증번호 칸이 열리지 않는다** |
| 2 | 새 이메일 → [인증번호 받기] | "메일을 보냈어요" · 인증번호 칸이 열린다 |
| 3 | 곧바로 [다시 받기] | **쿨다운 문구** |
| 4 | 틀린 번호 6자리 | "인증번호가 맞지 않아요" |
| 5 | 메일의 번호 | "인증됐어요" · 비밀번호 칸이 열린다 |
| 6 | 이메일을 한 글자 고친다 | "이메일이 바뀌어서 인증을 다시 받아야 해요" |
| 7 | 비밀번호 입력 → [가입하고 시작하기] | **프로필 등록으로** |

**1·3·7이 핵심이다.** 1은 중복 검사가 발송 단계로 왔는지를, 3은 코드 매핑을,
7은 티켓 계약 전체를 본다.

⚠️ **1번이 "메일을 보냈어요"로 나오면 백엔드에 중복 검사가 아직 없는 것이다.**
앱 버그가 아니다 — 그때는 인증을 끝까지 밟아 가입 단계에서 409가 나는지 본다.

**7이 성공하면 `isOnboarded=false` 계정이 생긴다** — PR #17의 에뮬레이터 확인
7개(태스크 #26)를 그 계정으로 이어서 한다.

- [ ] **Step 3: PR을 연다**

```bash
git push -u origin feat/email-verification-ui
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend --base dev \
  --title "📍 Feat: 이메일 인증을 거쳐 가입한다"
```

💬 리뷰 포인트에 적는다.

- **500줄을 넘는다** — 화면 하나를 반으로 자를 수 없었다. 계약 부분은 PR A로 이미 나눴다
- **중복 이메일은 [인증번호 받기]에서 막는다** — 인증번호 칸을 열지 않는다. 다 치고 나서 알려주면 사용자가 한 일이 통째로 버려진다
- **그래도 가입 단계의 409 처리를 남겼다** — 발송과 가입 사이에 다른 사람이 먼저 가입하는 경합이 있다. 드물지만 그때 `unknown`이 뜨면 이유를 알 수 없다
- **가입 실패가 인증을 푼다** — 티켓이 실패해도 소비되기 때문이다. 이 PR에서 가장 중요한 동작이고 테스트가 있다
- **`_verifiedEmail`에 이메일 자체를 담는다** — `bool` 하나면 A로 인증받고 B로 가입하는 구멍이 생긴다
- **카운트다운 5분은 가정이다** — 서버 값을 모른다. `expiresIn` 응답을 요청해 뒀다
- **재로그인 코드를 지웠다** — 가입 응답이 토큰을 준다
- 인증번호 칸의 배치와 "다시 받기" 버튼 위치는 디자인 확인이 필요하다

---

## 완료 조건

- [ ] `flutter test` 전체 통과
- [ ] `flutter analyze` 경고 0개
- [ ] `flutter build apk --debug` 성공
- [ ] Task B4의 에뮬레이터 확인 7개 (특히 2·6·7)
- [ ] PR 둘 다 base가 `dev`

---

## 이 계획이 하지 않는 것

| | 어디서 |
|---|---|
| 소셜 로그인(카카오·Apple) | 서버 `POST /auth/oauth/{provider}`는 있다. 별도 작업 |
| 로그아웃 서버 호출 | `POST /auth/logout`이 생겼다. 토큰을 헤더에 실어야 해서 별도 |
| 마케팅 동의 | 보류 중 (태스크 #1~#4) |
| 비밀번호 재설정 | 서버에 없다 |

---

## 백엔드에 물어볼 것

계획을 막지는 않지만 답이 오면 고칠 곳이 있다.

1. **`codeTtl` · `cooldown` · `ticketTtl` · `maxAttempts` · `dailyLimit` 값** — yml이 레포에 없어 전부 모른다
2. **확인 응답에 `expiresIn`을 실어줄 수 있는가** — 카운트다운이 앱의 가정(5분)에 기대고 있다
3. **발송 단계 중복 검사가 배포됐는가** — 앱은 이것을 전제로 만든다. 아직이면 Task B4의 1번이 통과하지 않는다
4. **`ticketTtl`이 얼마나 되는가** — 비밀번호를 고민하는 동안 만료될 수 있다
