# 카카오 로그인에 약관 동의를 붙이는 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 카카오로 처음 들어오는 사람에게도 **개인정보를 수집하기 전에** 약관 동의를 받는다.

**Architecture:** 약관 화면은 이미 있다(S03). **카카오 버튼과 카카오 인가 사이에 그 화면을 끼운다.** 한 번 동의하면 기기에 기록해 다음부터 건너뛴다.

**Tech Stack:** Flutter 3.44.8 (fvm) · Riverpod 3 · go_router 17 · flutter_secure_storage

**브랜치:** `feat/kakao-terms` (upstream/dev 기준)

---

## Global Constraints

- **모든 flutter/dart 명령은 fvm SDK로 부른다.** `fvm`이 PATH에 없다:
  `& ".fvm\flutter_sdk\bin\flutter.bat" test` · `& ".fvm\flutter_sdk\bin\dart.bat" format lib test`
- 내부 import는 항상 절대경로 `package:runiverse/...`
- 색·치수·문자열은 토큰으로만 · 아이콘은 **Lucide만**
- 커밋 메시지는 `<이모지> <Type>: <설명>` · **AI를 공동 작성자로 넣지 않는다**
- 각 태스크 끝에 `analyze` 경고 0개 · 커밋 시점마다 빌드
- **새 패키지를 추가하지 않는다** (아래 ③)

---

## 왜 필요한가

| | 무엇에 대한 동의인가 |
|---|---|
| 카카오 동의항목 | **카카오가 우리에게** 이메일을 넘기는 것 |
| 우리 약관 | **우리가** 서비스를 제공하고 개인정보를 수집·이용하는 것 |

카카오 화면의 동의는 카카오와 사용자 사이의 일이다. **우리 약관을 갈음하지 못한다.**

특히 **생체·운동 정보**는 민감정보라 다른 동의와 **분리한 별도 동의**가 필요하다.
지금 카카오 로그인은 이 셋을 전부 건너뛰고 계정을 만든다.

⚠️ **법률 자문이 아니다.** 실제 적용은 법무 검토를 받는다.

---

## 반드시 먼저 알아야 할 것 넷

### ① 순서가 핵심이다 — 인가보다 먼저 받는다

```
[카카오로 계속하기]
  ├─ 동의 기록 있음 ──────────────→ 카카오 인가 → 서버 → 홈
  └─ 없음 → 약관(S03) → 동의 ────→ 카카오 인가 → 서버 → 홈
```

**카카오 인가가 끝나면 서버가 곧바로 계정을 만들고 이메일을 저장한다.** 그 뒤에 약관을
보이면 이미 수집한 뒤다. 그래서 **버튼과 인가 사이**여야 한다.

### ② 기기 단위로만 기억할 수 있다 — 알려진 한계다

서버가 필수 약관 동의를 저장하지 않는다(`User`에 `alertConsent`뿐). 그래서 앱이 로컬에
기록한다. 여기서 오는 한계가 둘이다.

| 상황 | 무슨 일이 일어나나 |
|---|---|
| 앱 재설치 · 기기 변경 | 이미 동의한 사람이 약관을 다시 본다 |
| 같은 기기, 다른 계정 | 동의한 적 없는 계정이 약관을 건너뛴다 |

⚠️ **두 번째가 더 나쁘다.** 기기에 남은 기록은 "이 기기 사용자가 동의했다"는 뜻이지
"이 계정이 동의했다"가 아니다.

**그래도 지금보다 낫다** — 현재는 **아무도 동의하지 않은 채** 계정이 만들어진다.
서버가 `termsAgreed`를 저장하면 판정 근거만 로컬에서 서버로 옮긴다.

### ③ 새 패키지를 쓰지 않는다

동의 기록은 민감하지 않아 `flutter_secure_storage`가 과하다. 그렇다고
`shared_preferences`를 새로 넣지 않는다 — **값 하나를 위해 의존성을 늘리지 않는다.**
이미 있는 secure storage를 쓰되 **`TokenStore`와는 나눈다.**

```dart
/// 약관 동의 기록. [TokenStore]와 나누는 이유는 **수명이 다르기 때문**이다.
///
/// 토큰은 로그아웃하면 지워지지만, 약관 동의는 남아야 한다 —
/// 로그아웃했다고 다시 동의를 받으면 같은 사람에게 같은 것을 두 번 묻는 셈이다.
abstract interface class ConsentStore { ... }
```

⚠️ **`TokenStore.clear()`가 이것을 지우면 안 된다.** 테스트로 고정한다.

### ④ 약관 화면이 두 곳에서 쓰인다

지금은 이메일 가입 전용이라 동의하면 `context.push(AppRoutes.signUp)`으로 **가입 화면이
못 박혀 있다.** 카카오에서도 쓰려면 **다음에 갈 곳을 밖에서 정해야 한다.**

`extra`로 넘긴다 — 마케팅 동의를 넘길 때 쓴 것과 같은 방법이다.

---

## 마케팅 동의도 이번에 화면에 넣는다

요청대로 선택 항목을 함께 만든다. **다만 서버로 보내지 않는다** —
`SignUpRequest`에 `alertConsent`가 아직 없고, 카카오 로그인(`/auth/oauth/kakao`)은
아예 `{authorizationCode, codeVerifier}`만 받는다.

**보류 중인 계획**(`2026-08-11-marketing-consent.md`)의 **Task 1(화면)만 여기서 한다.**
서버 전송은 그 계획이 열릴 때 이어서 한다.

---

## File Structure

```
신규  core/storage/consent_store.dart              동의 기록 (인터페이스 + 구현 + 인메모리)
      test/kakao_terms_test.dart                   흐름 테스트

수정  features/onboarding/presentation/terms_agreement_page.dart  선택 항목 + 다음 목적지
      features/auth/presentation/sign_in_page.dart                카카오 버튼 앞에 약관
      app/router/app_router.dart                                  약관 라우트가 extra를 받는다
      core/strings/app_strings.dart                               문구 2개
      test/terms_agreement_test.dart                              선택 항목 동작
      docs/implementation-notes.md                                한계와 함정
```

**8파일 · 350줄 남짓.** PR 하나.

---

## Task 1: 동의 기록 저장소

**Files:**
- Create: `lib/core/storage/consent_store.dart`

- [x] **Step 1: 인터페이스와 구현**

`token_store.dart`의 구조를 그대로 따른다 — 인터페이스 + secure 구현 + 인메모리(테스트용).

```dart
abstract interface class ConsentStore {
  /// 필수 약관에 동의한 적이 있는가.
  Future<bool> hasAgreedTerms();

  /// 동의를 기록한다. **되돌리는 메서드를 두지 않는다** —
  /// 철회는 계정 삭제나 설정 화면의 일이지 이 저장소가 할 일이 아니다.
  Future<void> markTermsAgreed();
}
```

⚠️ **마케팅 동의는 여기 넣지 않는다.** 그것은 서버로 갈 값이고, 지금 보낼 곳이 없어
버려진다. 로컬에 남기면 "저장했으니 반영됐다"고 오해할 자리가 생긴다.

- [x] **Step 2: 테스트**

| 무엇 | 왜 |
|---|---|
| 기록하면 `true` | |
| 기록 전에는 `false` | |
| **`TokenStore.clear()`가 지우지 않는다** | ⚠️ 로그아웃해도 남아야 한다 |

- [x] **Step 3: analyze → 커밋**

```bash
git commit -m "📍 Feat: 약관 동의 기록을 남긴다"
```

---

## Task 2: 약관 화면에 선택 항목과 목적지

**Files:**
- Modify: `terms_agreement_page.dart` · `app_strings.dart` · `app_router.dart`
- Test: `test/terms_agreement_test.dart`

- [x] **Step 1: 문구**

```dart
  /// 선택 항목 배지. `필수`와 나란히 서므로 같은 두 글자로 맞춘다.
  static const termsOptional = '선택';

  /// 마케팅 수신 동의. **무엇을 보내는지** 밝힌다 —
  /// "마케팅 정보"만으로는 무엇에 동의하는지 알 수 없다.
  static const termsMarketing = '매칭 소식과 이벤트 알림 받기';
```

- [x] **Step 2: 필수와 선택을 가른다**

화면 주석이 이 작업을 예견해 뒀다 — *"선택 항목이 다시 생기면 그때 `_Term`에 필드를
추가한다"*, *"선택 항목이 생기면 이 둘이 갈라지므로 지금부터 이름을 나눠 둔다"*.

```dart
class _Term {
  const _Term(this.label, {this.isRequired = true});
  final String label;
  /// 선택 항목은 **CTA를 막지 않는다.** 막으면 그것은 선택이 아니다.
  final bool isRequired;
}
```

| | 무엇 | 조건 |
|---|---|---|
| `_allAgreed` | 전체 동의 카드의 체크 | **선택까지 전부** |
| `_canContinue` | 하단 CTA 활성 | **필수만** |

⚠️ **둘을 섞으면 마케팅에 동의하지 않은 사람이 가입할 수 없게 된다.**

배지 색도 나눈다 — 선택은 `textTertiary`. 필수와 같은 `primary`면 눈으로 구분되지 않아
글자를 읽어야만 안다.

- [x] **Step 3: 다음에 갈 곳을 밖에서 정한다**

```dart
/// 동의를 마치면 무엇을 할 것인가.
///
/// 이메일 가입은 가입 화면으로 가고, 카카오는 인가를 시작한다.
/// **화면이 목적지를 알지 못하게 한다** — 알게 하면 흐름이 늘 때마다 이 파일을 고친다.
enum TermsNext { signUp, kakao }
```

라우터가 `extra`로 받아 넘긴다. 기본값은 `signUp`이다 — 딥링크로 이 화면에 바로 와도
기존 동작이 유지된다.

- [x] **Step 4: 테스트**

| 무엇 |
|---|
| 선택 항목은 CTA를 막지 않는다 |
| 필수가 하나라도 빠지면 막힌다 |
| 전체 동의는 선택까지 켠다 |
| **필수만 켜면 전체 동의는 꺼진 채다** |

- [x] **Step 5: analyze → 커밋**

---

## Task 3: 카카오 버튼 앞에 약관을 끼운다

**Files:**
- Modify: `sign_in_page.dart`
- Test: `test/kakao_terms_test.dart`

- [x] **Step 1: 갈림길**

```dart
  Future<void> _startKakao() async {
    // ⚠️ 인가보다 **먼저** 확인한다. 인가가 끝나면 서버가 계정을 만들고
    // 이메일을 저장하므로, 그 뒤의 동의는 이미 늦다.
    final agreed = await ref.read(consentStoreProvider).hasAgreedTerms();
    if (!mounted) return;

    if (agreed) {
      await _signInWithKakao();
      return;
    }
    // 약관 화면이 동의를 받고 기록한 뒤 돌아온다.
    context.push(AppRoutes.terms, extra: TermsNext.kakao);
  }
```

- [x] **Step 2: 약관 화면이 카카오를 이어받는다**

동의하면 `markTermsAgreed()` → 로그인 화면으로 `pop` → 카카오 인가.

⚠️ **약관 화면이 카카오 SDK를 직접 부르지 않는다.** 그러면 온보딩 feature가 auth의
구현을 알게 된다. **동의만 기록하고 돌아온다** — 인가는 로그인 화면의 몫이다.

`pop`의 결과로 "동의했다"를 돌려주고, 로그인 화면이 그것을 받아 인가를 시작한다.

- [x] **Step 3: 테스트**

| 무엇 | 왜 |
|---|---|
| 동의 기록이 없으면 **약관 화면이 뜬다** | |
| **그때 카카오 인가를 부르지 않는다** | ⚠️ 핵심. `FakeOauthCodeSource.callCount`로 본다 |
| 동의 기록이 있으면 곧바로 인가 | 두 번 묻지 않는다 |
| 동의를 마치면 인가가 시작된다 | |

**두 번째가 이 PR의 핵심이다.** 동의 전에 인가가 나가면 이 작업 전체가 무의미하다.

- [x] **Step 4: analyze → 커밋**

---

## Task 4: 문서 · 검증 · PR

- [x] **Step 1: `implementation-notes.md`에 §9-9**

담을 것 — 카카오 동의와 우리 약관이 다르다 · 인가보다 먼저 받아야 하는 이유 ·
**기기 단위 기록의 한계 둘** · `ConsentStore`를 `TokenStore`와 나눈 이유

- [x] **Step 2: 전체 검증**

```powershell
& ".fvm\flutter_sdk\bin\dart.bat" format lib test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug
```

⚠️ `format`이 이번에 손대지 않은 파일을 바꾸면 되돌린다. `dio_client.dart`가 매번 걸린다.

- [ ] **Step 3: 에뮬레이터**

앱 데이터를 지우고 시작한다 — 동의 기록이 남아 있으면 1번을 볼 수 없다.

| # | 조작 | 기대 |
|---|---|---|
| 1 | 새로 설치 → [카카오로 계속하기] | **약관 화면** (카카오가 열리지 않는다) |
| 2 | 마케팅 항목 | `선택` 배지 · 안 켜도 CTA가 열린다 |
| 3 | 동의하고 계속 | 카카오 인가 → 홈 |
| 4 | 로그아웃 후 다시 카카오 | **약관 없이 곧바로 인가** |
| 5 | 앱 데이터 삭제 후 다시 | 약관이 다시 뜬다 (알려진 한계) |

**1번과 4번이 핵심이다.** 동의 전에 카카오가 열리면 안 되고, 동의한 뒤에는 다시 묻지 않아야 한다.

- [ ] **Step 4: PR**

💬 리뷰 포인트에 적는다.

- **인가보다 먼저 받는다** — 인가가 끝나면 서버가 계정을 만들고 이메일을 저장한다
- **기기 단위 기록의 한계 둘** — 재설치 시 다시 묻고, 같은 기기의 다른 계정은 건너뛴다. 서버가 `termsAgreed`를 저장하면 해결된다
- **`ConsentStore`를 `TokenStore`와 나눴다** — 로그아웃해도 남아야 한다. 테스트로 고정했다
- **약관 화면이 카카오 SDK를 부르지 않는다** — 동의만 기록하고 돌아온다
- **마케팅 동의는 화면에만 있다** — 서버가 받지 않는다. 보류 계획이 열릴 때 잇는다
- 마케팅 문구는 디자인 확인이 필요하다

---

## 완료 조건

- [x] `flutter test` 전체 통과 · `analyze` 경고 0개
- [x] `build apk --debug` 성공
- [ ] Task 4 Step 3의 확인 5개 (특히 1·4)
- [ ] PR base가 `dev`

---

## 이 계획이 하지 않는 것

| | 왜 |
|---|---|
| 마케팅 동의를 서버로 전송 | 받을 API가 없다. 보류 계획에 있다 |
| 약관 전문 보기 | URL이 정해지지 않았다 |
| 동의 철회 | 설정 화면(S22.2)의 일이다 |
| 계정별 동의 관리 | 서버가 저장해야 가능하다 |

---

## 백엔드에 요청할 것

```java
// User
private final boolean termsAgreed;      // 필수 3종 동의 여부
private final Instant termsAgreedAt;    // 동의 시각 (분쟁 대비)

// OauthLoginResponse · LoginResponse
Boolean termsAgreed                      // false면 앱이 약관 화면을 띄운다
```

이것이 생기면 **기기 단위 한계 둘이 모두 사라진다.** 판정 근거를 로컬에서 서버로 옮기면 된다.

---

## 실제로 해보고 계획에서 달라진 것

| 무엇 | 왜 |
|---|---|
| `SecureTokenStore.clear()`를 함께 고쳤다 | `deleteAll()`이었다. 계획의 파일 목록에 없던 파일인데, **여기가 진짜 위험이었다** — 같은 저장소를 쓰므로 로그아웃이 동의 기록까지 지운다 |
| `consentStoreProvider`를 `auth_provider.dart`에 뒀다 | `core`에 Riverpod이 하나도 없어 거기 두면 새 패턴이 된다. `tokenStoreProvider`와 성격이 같고 `onboarding_provider.dart`가 그것을 가져다 쓰는 선례가 있다 |
| `TermsNext`를 `app_routes.dart`에 뒀다 | 화면 파일에 두면 auth가 onboarding의 **화면**을 import해야 한다. `extra`로 건너가는 값이라 라우팅 상수 옆이 맞다 |
| 동의 기록을 **약관 화면**이 남긴다 | 부르는 쪽에 맡기면 흐름이 늘 때 한 곳이 빠뜨린다. 그러면 동의 없이 지나가는 길이 생긴다 |
| 저장소 테스트를 `consent_store_test.dart`로 분리 | `token_store_test.dart`와 짝을 맞췄다. `kakao_terms_test.dart`는 흐름만 본다 |
| "재로그인해도 안 묻는다"를 저장소 검증으로 바꿨다 | 화면을 다시 `pumpWidget`해도 라우터가 홈에 남아 로그인으로 돌아오지 않는다. 그 경로는 에뮬레이터 확인 4번이 본다 |
| `sign_in_page_test.dart`·`onboarding_flow_test.dart`도 고쳤다 | 앞의 것은 동의를 마친 기기로 시작해야 기존 카카오 테스트가 그대로 산다. 뒤의 것은 override가 없어 약관 CTA에서 죽었다 |

**두 번 되돌려 확인했다.** `clear()`를 `deleteAll()`로 돌리니 저장소 테스트가 깨졌고,
카카오 버튼을 인가에 직결하니 흐름 테스트 8개 중 7개가 깨졌다. 가드가 실제로 잡는다.

### 남은 것

`docs/implementation-notes.md` §9-8의 취소 경로 표가 낡았다 — 브라우저를 닫으면
`KakaoClientException`이 아니라 `PlatformException(CANCELED)`이 온다(PR #21에서 고친 것).
이 PR의 범위 밖이라 손대지 않았다.
