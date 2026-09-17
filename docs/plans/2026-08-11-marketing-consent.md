# 마케팅 동의 구현 계획

> ## ⏸️ 보류 — 서버가 필드를 열면 시작한다 (2026-08-11)
>
> `SignUpRequest`에 `alertConsent`가 아직 없다. 백엔드에 요청해 둔 상태다.
>
> **지금 구현하지 않는 이유는 요청 계약이 확정되지 않아서다.** 필드 이름이나
> 타입이 바뀌면 저장소·컨트롤러·화면을 다시 고치고 커밋을 또 쌓게 된다.
> 서버가 열린 뒤에 한 번에 만드는 편이 낫다.
>
> **조사와 설계는 끝나 있다.** 아래 그대로 따르면 된다.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 약관 화면에서 마케팅 수신 동의를 **선택 항목**으로 받고, 가입 요청에 실어 보낸다.

**Architecture:** 동의 값은 **약관 화면 → 가입 화면 → 서버**로 한 방향으로만 흐른다. 앱 전역 상태를 만들지 않는다 — 가입이 끝나면 쓸 일이 없는 값이다.

**Tech Stack:** Flutter 3.44.8 (fvm) · Riverpod 3 · go_router 17 · dio

**브랜치:** `feat/marketing-consent` (upstream/dev 기준)

---

## Global Constraints

- **모든 flutter/dart 명령은 fvm SDK로 부른다.** `fvm`이 PATH에 없다:
  `& ".fvm\flutter_sdk\bin\flutter.bat" test` · `& ".fvm\flutter_sdk\bin\dart.bat" format lib test`
- 내부 import는 항상 절대경로 `package:runiverse/...`
- 색·치수·문자열은 토큰으로만
- 커밋 메시지는 `<이모지> <Type>: <설명>`
- **AI를 공동 작성자로 넣지 않는다.**
- 각 태스크 끝에 `analyze` 경고 0개 · 커밋 시점마다 빌드
- **UI 텍스트는 한국어.** "친구"라는 말을 쓰지 않는다

---

## 서버 계약 — 아직 열려 있지 않다

```
POST /api/v1/auth/signup
{"verificationTicket": "...", "password": "...", "alertConsent": true}
                                                  ↑ 서버가 아직 안 받는다
```

| | |
|---|---|
| `User.alertConsent` (boolean) | ✅ 도메인에 **있다** |
| `User(userId, email, passwordHash, alertConsent)` | ✅ **있다** (주석: "로컬 회원가입 할때 사용") |
| `SignUpUserRegistrar.register(email, rawPassword)` | ❌ `alertConsent`를 **false로 고정**해 부른다 |
| `SignUpRequest`의 필드 | ❌ **없다** |

**받을 준비는 반쯤 돼 있고 API만 닫혀 있다.** 앱이 먼저 보내기 시작한다 —
서버가 필드를 열면 그날부터 그대로 동작한다.

⚠️ **필드 이름은 `alertConsent`다.** 서버 도메인이 이미 그 이름을 쓴다. `marketingAgreed`
같은 이름으로 보내면 서버가 다시 매핑해야 한다.

### 백엔드에 요청할 것

```java
public record SignUpRequest(String verificationTicket, String password, Boolean alertConsent) {}
// SignUpHandler → SignUpUserRegistrar.register(email, password, alertConsent)
// → new User(userId, email, hashedPassword, alertConsent)
```

---

## 반드시 먼저 알아야 할 것 넷

### ① 화면이 이 작업을 예견해 뒀다

`terms_agreement_page.dart`의 주석 두 곳이 그대로 지시문이다.

```dart
/// 선택 항목이 다시 생기면 그때 [_Term]에 필드를 추가한다.
/// 선택 항목이 생기면 이 둘이 갈라지므로 지금부터 이름을 나눠 둔다.
```

`_canContinue`와 `_allAgreed`가 **미리 나뉘어 있다.** 지금은 같은 값이지만
선택 항목이 들어오면 갈라진다 — 이 계획이 그 갈라짐을 만든다.

### ② `_allAgreed`와 `_canContinue`가 하는 일이 다르다

| | 무엇 | 선택 항목이 생기면 |
|---|---|---|
| `_allAgreed` | 전체 동의 카드의 체크 상태 | **선택까지 전부** 켜져야 true |
| `_canContinue` | 하단 CTA 활성 조건 | **필수만** 켜지면 true |

⚠️ **둘을 섞으면 마케팅에 동의하지 않은 사람이 가입할 수 없게 된다.** 선택 항목의
뜻이 사라진다.

### ③ 동의 값은 `extra`로 넘긴다

```dart
context.push(AppRoutes.signUp, extra: _alertConsent);
```

**앱 전역 상태를 만들지 않는다.** 두 화면 사이에서만 사는 값이고, 가입이 끝나면
쓸 일이 없다. provider로 올리면 지우는 시점을 따로 관리해야 한다.

⚠️ **딥링크로 가입 화면에 바로 오면 `extra`가 `null`이다.** 그때는 **`false`**로 본다 —
동의하지 않은 것으로 보는 쪽이 안전하다. 동의를 받지 않고 마케팅 메일을 보내는 것보다
받았는데 안 보내는 쪽이 낫다.

### ④ 서버가 모르는 필드를 무시하는지 확인해야 한다

Spring Boot는 기본으로 알 수 없는 JSON 필드를 무시한다
(`fail-on-unknown-properties=false`). 그래서 지금 보내도 400이 나지 않을 **것으로 보인다.**

⚠️ **추측이다.** 설정이 다르면 가입이 통째로 깨진다. **Task 5에서 실제로 확인한다** —
이 계획에서 가장 위험한 가정이다.

---

## File Structure

```
수정  features/onboarding/presentation/terms_agreement_page.dart  선택 항목 + extra 전달
      features/auth/presentation/sign_up_page.dart                extra 수신 → signUp
      app/router/app_router.dart                                  extra를 화면에 넘긴다
      features/auth/domain/auth_repository.dart                   signUp에 alertConsent
      features/auth/data/http_auth_repository.dart                요청 몸통
      features/auth/data/fake_auth_repository.dart                기억해 두기
      features/auth/presentation/auth_provider.dart               컨트롤러
      core/strings/app_strings.dart                               문구 2개
      docs/implementation-notes.md                                함정

테스트 test/terms_agreement_test.dart                             선택 항목 동작
      test/sign_up_page_test.dart                                 동의 값이 전달되는가
```

**10파일 · 300줄 남짓.** PR 하나로 충분하다.

---

## Task 1: 약관 화면에 선택 항목을 더한다

**Files:**
- Modify: `lib/features/onboarding/presentation/terms_agreement_page.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/terms_agreement_test.dart`

- [ ] **Step 1: 문구 둘을 더한다**

`termsRequired` 근처에 넣는다.

```dart
  /// 선택 항목 배지. `필수`와 나란히 서므로 같은 길이(두 글자)로 맞춘다.
  static const termsOptional = '선택';

  /// 마케팅 수신 동의. **무엇을 보내는지** 밝힌다 —
  /// "마케팅 정보"만으로는 무엇에 동의하는지 알 수 없다.
  static const termsMarketing = '매칭 소식과 이벤트 알림 받기';
```

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`test/terms_agreement_test.dart`를 만든다.

```dart
/// 약관 동의(S03) — 필수와 선택이 갈라지는가.
///
/// 이 화면의 핵심 규칙은 **필수만 켜도 다음으로 갈 수 있다**는 것이다.
/// 선택 항목이 CTA를 막으면 그것은 선택이 아니다.
void main() {
  Future<void> pumpTerms(WidgetTester tester) async { ... }

  bool ctaEnabled(WidgetTester tester) { ... }

  testWidgets('선택 항목은 CTA를 막지 않는다', (tester) async {
    await pumpTerms(tester);

    // 필수 셋만 켠다.
    await tapTerm(tester, AppStrings.termsService);
    await tapTerm(tester, AppStrings.termsPrivacy);
    await tapTerm(tester, AppStrings.termsHealth);

    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('필수가 하나라도 빠지면 막힌다', (tester) async {
    await pumpTerms(tester);

    await tapTerm(tester, AppStrings.termsService);
    await tapTerm(tester, AppStrings.termsMarketing);   // 선택만 켜도 소용없다

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('전체 동의는 선택까지 켠다', (tester) async {
    await pumpTerms(tester);
    await tapTerm(tester, AppStrings.termsAgreeAll);

    // 하나라도 빠지면 "전체"가 아니다.
    for (final label in [
      AppStrings.termsService,
      AppStrings.termsPrivacy,
      AppStrings.termsHealth,
      AppStrings.termsMarketing,
    ]) {
      expect(isChecked(tester, label), isTrue);
    }
  });

  testWidgets('필수만 켜면 전체 동의는 꺼진 채다', (tester) async {
    // 전체 동의 카드가 CTA와 같은 조건이면 선택 항목의 뜻이 사라진다.
    ...
    expect(isChecked(tester, AppStrings.termsAgreeAll), isFalse);
  });
}
```

⚠️ 체크 상태는 `Semantics(checked:)`로 읽는다. 화면이 이미 그것을 세워 뒀다.

- [ ] **Step 3: `_Term`에 필드를 더한다**

```dart
/// 약관 한 건. 지금은 라벨과 필수 여부뿐이지만, 약관 전문 URL이 정해지면 여기 붙는다.
class _Term {
  const _Term(this.label, {this.isRequired = true});

  final String label;

  /// 선택 항목은 **CTA를 막지 않는다.** 막으면 그것은 선택이 아니다.
  final bool isRequired;
}
```

목록에 더한다. **마케팅은 맨 아래**다 — 법적 무게 순 뒤에 온다.

```dart
  static const _terms = [
    _Term(AppStrings.termsService),
    _Term(AppStrings.termsPrivacy),
    _Term(AppStrings.termsHealth),
    _Term(AppStrings.termsMarketing, isRequired: false),
  ];
```

- [ ] **Step 4: 두 조건을 갈라놓는다**

```dart
  /// 전체 동의 카드의 상태. **선택까지 전부** 켜져야 한다.
  bool get _allAgreed => _agreed.length == _terms.length;

  /// CTA 활성 조건. **필수만** 보면 된다 —
  /// 선택 항목이 여기 끼면 그것은 선택이 아니게 된다.
  bool get _canContinue => _terms
      .asMap()
      .entries
      .where((e) => e.value.isRequired)
      .every((e) => _agreed.contains(e.key));

  /// 가입 요청에 실어 보낼 값.
  bool get _alertConsent =>
      _agreed.contains(_terms.indexWhere((t) => !t.isRequired));
```

⚠️ `_alertConsent`가 `indexWhere`를 쓰는 이유는 **선택 항목의 위치를 못 박지 않기
위해서**다. 항목이 늘거나 순서가 바뀌어도 따라온다.

- [ ] **Step 5: 배지를 나눈다**

`_TermRow`에 `isRequired`를 넘기고 배지를 바꾼다.

```dart
                Text(
                  isRequired
                      ? AppStrings.termsRequired
                      : AppStrings.termsOptional,
                  style: AppTypography.caption.copyWith(
                    // 선택은 primary를 쓰지 않는다. 필수와 같은 색이면
                    // 눈으로 구분되지 않아 배지 글자를 읽어야만 안다.
                    color: isRequired ? colors.primary : colors.textTertiary,
                  ),
                ),
```

- [ ] **Step 6: 통과를 확인하고 커밋**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/terms_agreement_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```

```bash
git commit -m "📍 Feat: 약관에 선택 항목을 둔다"
```

---

## Task 2: 동의 값을 가입 화면까지 옮긴다

**Files:**
- Modify: `terms_agreement_page.dart` · `app_router.dart` · `sign_up_page.dart`

- [ ] **Step 1: 약관 화면이 값을 실어 보낸다**

```dart
  void _submit() {
    // push라 정보 입력 화면에서 뒤로가기를 누르면 여기로 돌아온다.
    // 동의한 것을 잃지 않는다 — 이 화면이 살아 있어 상태가 남는다.
    context.push(AppRoutes.signUp, extra: _alertConsent);
  }
```

- [ ] **Step 2: 라우터가 화면에 넘긴다**

```dart
      GoRoute(
        path: AppRoutes.signUp,
        // 약관 화면이 넘긴 마케팅 동의. **딥링크로 바로 오면 null이다** —
        // 그때는 동의하지 않은 것으로 본다.
        builder: (context, state) =>
            SignUpPage(alertConsent: state.extra as bool? ?? false),
      ),
```

- [ ] **Step 3: 가입 화면이 받아서 넘긴다**

```dart
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({this.alertConsent = false, super.key});

  /// 약관 화면에서 받은 마케팅 수신 동의.
  ///
  /// 기본값이 `false`인 이유는 **딥링크로 이 화면에 바로 올 수 있어서**다.
  /// 동의를 받지 않고 보내는 것보다 받았는데 안 보내는 쪽이 낫다.
  final bool alertConsent;
```

`_submit`에서 넘긴다.

```dart
        .signUp(
          verificationTicket: ticket,
          password: _password.text,
          alertConsent: widget.alertConsent,
        );
```

- [ ] **Step 4: analyze → 커밋**

이 시점에는 저장소가 아직 인자를 안 받으므로 **Task 3과 함께 커밋한다.**

---

## Task 3: 저장소와 컨트롤러가 값을 나른다

**Files:**
- Modify: `auth_repository.dart` · `http_auth_repository.dart` · `fake_auth_repository.dart` · `auth_provider.dart`

- [ ] **Step 1: 인터페이스**

```dart
  /// [alertConsent]는 **마케팅 수신 동의**다. 선택 항목이라 기본값이 `false`다.
  ///
  /// ⚠️ 서버가 이 필드를 아직 받지 않는다. 보내도 무시되고 `false`로 저장된다 —
  /// `SignUpRequest`에 열리면 그날부터 그대로 동작한다.
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
    bool alertConsent = false,
  });
```

- [ ] **Step 2: HTTP 구현**

```dart
        data: {
          'verificationTicket': verificationTicket,
          'password': password,
          // 서버 도메인이 쓰는 이름 그대로다(`User.alertConsent`).
          'alertConsent': alertConsent,
        },
```

- [ ] **Step 3: 가짜 저장소가 기억한다**

```dart
  /// 가입할 때 받은 마케팅 동의. **테스트가 값이 전달됐는지 확인하는 데 쓴다.**
  bool? lastAlertConsent;
```

`signUp`에서 `lastAlertConsent = alertConsent;`

- [ ] **Step 4: 컨트롤러**

```dart
  Future<AuthFailure?> signUp({
    required String verificationTicket,
    required String password,
    bool alertConsent = false,
  }) => _authenticate(
    () => _repository.signUp(
      verificationTicket: verificationTicket,
      password: password,
      alertConsent: alertConsent,
    ),
  );
```

- [ ] **Step 5: 화면 테스트를 더한다**

`test/sign_up_page_test.dart`에.

```dart
  testWidgets('약관에서 받은 동의가 가입 요청까지 간다', (tester) async {
    await pumpSignUp(tester, alertConsent: true);
    await verifyEmail(tester);
    await enterPassword(tester, 'runi123!');
    await tester.tap(find.widgetWithText(AppButton, AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    // 화면이 값을 받아만 두고 넘기지 않으면 아무도 눈치채지 못한다.
    expect(repository.lastAlertConsent, isTrue);
  });

  testWidgets('동의하지 않았으면 false로 간다', (tester) async {
    await pumpSignUp(tester);   // 기본값
    ...
    expect(repository.lastAlertConsent, isFalse);
  });
```

⚠️ `pumpSignUp`이 `SignUpPage`를 라우터로 띄우므로 `extra`를 넘기도록 고친다.

- [ ] **Step 6: 통과를 확인하고 커밋 (Task 2와 함께)**

```bash
git commit -m "📍 Feat: 마케팅 동의를 가입 요청에 싣는다"
```

---

## Task 4: 문서

**Files:**
- Modify: `docs/implementation-notes.md`

- [ ] **Step 1: §9-9를 더한다**

담을 것.

- **필드 이름이 `alertConsent`다** — 서버 도메인이 쓰는 이름. `marketing*`이 아니다
- **서버가 아직 안 받는다** — `SignUpRequest`에 없고 `SignUpUserRegistrar`가 `false`로 고정
- **`_allAgreed`와 `_canContinue`를 섞지 않는다** — 섞으면 선택 항목이 필수가 된다
- **`extra`가 null이면 `false`** — 딥링크로 가입 화면에 바로 올 수 있다

---

## Task 5: 검증과 PR

- [ ] **Step 1: 전체를 돌린다**

```powershell
& ".fvm\flutter_sdk\bin\dart.bat" format lib test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug
```

⚠️ `format`이 이번에 손대지 않은 파일을 바꾸면 되돌린다. `dio_client.dart`가 매번 걸린다.

- [ ] **Step 2: ⚠️ 서버가 모르는 필드를 거부하지 않는지 확인한다**

**이 계획에서 가장 위험한 가정이다.** 거부하면 **가입이 통째로 깨진다.**

터널을 열고 curl로 먼저 본다 — 앱을 띄우기 전에 알 수 있다.

```bash
curl -s -w "\nHTTP %{http_code}\n" -X POST http://localhost:8080/api/v1/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"verificationTicket":"probe","password":"runi123!","alertConsent":true}'
```

| 응답 | 뜻 |
|---|---|
| `403 EMAIL_NOT_VERIFIED` | ✅ **필드를 무시했다.** 티켓이 가짜라 그다음에서 막힌 것 |
| `400 INVALID_REQUEST` | ❌ 거부한다. 서버가 열릴 때까지 이 값을 빼야 한다 |

- [ ] **Step 3: 에뮬레이터에서 확인한다**

| # | 조작 | 기대 |
|---|---|---|
| 1 | 약관 화면 | 마케팅 항목에 **`선택` 배지** |
| 2 | 필수 셋만 체크 | **[동의하고 계속]이 열린다** |
| 3 | 그 상태의 전체 동의 카드 | **꺼져 있다** |
| 4 | 전체 동의 탭 | 선택까지 **전부 켜진다** |
| 5 | 마케팅만 체크하고 필수 하나 해제 | CTA가 **잠긴다** |

**2번과 3번이 핵심이다.** 선택 항목이 CTA를 막지 않으면서도 전체 동의와는 구분되는지 본다.

⚠️ 가입까지 끝내려면 인증 메일이 필요하다. **SES 샌드박스라 검증된 주소로만 간다** —
그 계정은 이미 가입돼 있어 409가 난다. **화면 동작(1~5)까지만 확인하고,
서버 전달은 Step 2의 curl로 갈음한다.**

- [ ] **Step 4: PR을 연다**

```bash
git push -u origin feat/marketing-consent
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend --base dev \
  --title "📍 Feat: 마케팅 수신 동의를 받아 가입에 싣는다"
```

💬 리뷰 포인트에 적는다.

- **서버가 아직 이 필드를 받지 않는다** — `SignUpRequest`에 추가가 필요하다. 앱은 먼저 보낸다
- **필드 이름을 `alertConsent`로 맞췄다** — 서버 도메인이 쓰는 이름이다
- **`_allAgreed`와 `_canContinue`를 갈랐다** — 섞으면 선택 항목이 필수가 된다
- **`extra`가 null이면 false** — 딥링크 대비. 동의 없이 보내는 것보다 안전한 쪽
- `선택` 배지 색을 `textTertiary`로 뒀다 — 필수와 같은 색이면 눈으로 구분되지 않는다
- 마케팅 문구는 디자인 확인이 필요하다

---

## 완료 조건

- [ ] `flutter test` 전체 통과 · `analyze` 경고 0개
- [ ] `build apk --debug` 성공
- [ ] **Step 2의 curl 확인** (서버가 필드를 거부하지 않는가)
- [ ] Task 5 Step 3의 화면 확인 5개 (특히 2·3)
- [ ] PR base가 `dev`

---

## 이 계획이 하지 않는 것

| | 왜 |
|---|---|
| 카카오 가입의 동의 | 서버가 소셜 가입에서 `alertConsent`를 받지 않는다. 약관 화면을 거치지도 않는다 |
| 동의 철회 화면 | 프로필 탭(S22)이 생길 때 |
| 약관 전문 보기 | URL이 정해지지 않았다 |
| 푸시 알림 | 별개 작업. 이 동의는 **저장만** 한다 |
