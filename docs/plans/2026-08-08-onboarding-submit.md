# 프로필 서버 전송 (PR 2) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 프로필 등록(S04)을 마치면 서버에 반영되고, 다음에 앱을 켜면 프로필이 아니라 홈으로 들어간다.

**Architecture:** `POST /api/v1/users/onboarding`을 부르는 repository를 `features/onboarding/data`에 만들고, 화면이 domain 인터페이스만 보고 부른다. 서버가 거절하는 값(닉네임 문자·성별 표기·필수 페이스)은 **DTO 경계에서** 맞춘다 — 화면은 지금 모습을 유지한다.

**Tech Stack:** Flutter 3.44.8 (fvm) · Riverpod 3 · dio 5.11 · flutter_secure_storage 10.3.1

**설계 문서:** `docs/specs/2026-08-08-onboarding-flow-design.md` — 결정의 근거는 전부 여기 있다.

**선행 PR:** PR #15 (`feat/auto-sign-in`)가 머지되어 있어야 한다. 이 계획은 거기서 만든 `TokenStore.markOnboarded()` · `AuthRepository.refresh()` · `AuthSignedIn(isOnboarded:)`를 쓴다.

**브랜치:** `feat/onboarding-submit` (upstream/dev 기준)

---

## Global Constraints

- **모든 flutter/dart 명령은 fvm SDK로 부른다.** `fvm`이 PATH에 없다:
  `& ".fvm\flutter_sdk\bin\flutter.bat" test` · `& ".fvm\flutter_sdk\bin\dart.bat" format lib test`
- 내부 import는 항상 절대경로 `package:runiverse/...`
- 색·치수·문자열은 토큰으로만: `context.appColors` `AppSpacing` `AppTypography` `AppStrings`
- **IP 주소·포트·서버 주소를 주석이나 문서에 적지 않는다.**
- 커밋 메시지는 `<이모지> <Type>: <설명>` — `📍 Feat` `🔨 Fix` `📝 Docs` `🎨 Style` `🤖 Refactor` `✅ Test` `🚚 Chore`
- **AI를 공동 작성자로 넣지 않는다.**
- 각 태스크 끝에 `analyze` 경고 0개를 확인한다
- `StateProvider` / `StateNotifierProvider`를 쓰지 않는다
- **`presentation`은 `data`를 import하지 않는다.** 예외는 구현체를 고르는 provider 파일 하나뿐이다
- **domain은 순수 Dart만.** `flutter/` import 금지
- 한 커밋에 논리적 변경 하나. 각 커밋 시점에 빌드가 되어야 한다

---

## 반드시 먼저 알아야 할 것 셋

**① `testWidgets` 안에서 `pumpWidget` 전에 `await`하면 테스트가 영원히 멈춘다.**
가짜 시간 위에서 도는데 시간을 진행시킬 `pump`가 아직 없기 때문이다. `FakeAuthRepository`는
이래서 기다리지 않는 `issueSession()` · `seedAccount()`를 갖고 있다. **가짜 저장소를 새로
만들 때도 같은 통로를 둔다.**

**② `tokenStoreProvider`를 건드리는 테스트는 반드시 override한다.**
앱은 `SecureTokenStore`를 쓰는데 그것은 플랫폼 채널을 부른다. 순수 `test()`는 그 자리에서
죽고, **`testWidgets()`는 조용히 `null`을 돌려줘 통과한다** — 후자가 더 위험하다.

**③ `flutter test`와 `analyze`가 통과해도 `build apk`에서 죽을 수 있다.**
네이티브 의존성은 Gradle 병합 때만 검사된다. 이 PR은 새 패키지를 넣지 않으므로 위험이 낮지만
Task 7에서 한 번 돌린다.

---

## 서버 계약 (측정 완료)

```
POST /api/v1/users/onboarding      Authorization: Bearer <accessToken> 필요
```

**요청**

| 필드 | 타입 | 서버 검증 |
|---|---|---|
| `nickname` | String | 2~16자 · `^[가-힣a-zA-Z0-9_]+$` |
| `gender` | String | `MALE` / `FEMALE` (대소문자 무시) |
| `birthday` | String | `yyyy-MM-dd` · 미래 불가 |
| `averagePaceSecondsPerKm` | int | **필수** · 120~1800 |
| `weight` | number | 20~300 |
| `height` | number | 20~300 |

**응답** — 201 `{userId, nickname}`

**실패**

| 상태 | code | 앱 |
|---|---|---|
| 400 | `INVALID_REQUEST` · `MALFORMED_REQUEST_BODY` | `OnboardingFailure.validation` — **code가 인증 API와 다르므로 상태 코드로 판단한다** |
| 401 | — | 갱신 1회 후 재시도. 갱신도 실패하면 `sessionExpired` |
| 409 | `ALREADY_ONBOARD` | **성공으로 흡수** |
| 5xx | — | `server` |
| 응답 없음 | — | `network` |

---

## File Structure

```
신규  features/onboarding/domain/gender.dart                  MALE/FEMALE 두 값
      features/onboarding/domain/onboarding_profile.dart      화면이 모은 6개 값
      features/onboarding/domain/onboarding_failure.dart      실패 이유 + 예외
      features/onboarding/domain/onboarding_repository.dart   인터페이스
      features/onboarding/data/onboarding_profile_dto.dart    직렬화 · 720 치환
      features/onboarding/data/http_onboarding_repository.dart 서버 호출
      features/onboarding/data/fake_onboarding_repository.dart 테스트용
      features/onboarding/presentation/onboarding_provider.dart 배선

수정  features/onboarding/domain/nickname_rule.dart           정규식
      features/onboarding/presentation/profile_setup_page.dart 전송 · 실패 UI
      features/auth/presentation/auth_provider.dart           markOnboarded 연결
      core/strings/app_strings.dart                           문구 3개
```

**14파일 + 테스트 4** — 20개 한도 안이다.

---

## Task 1: 닉네임에 서버와 같은 문자 규칙을 넣는다

**Files:**
- Modify: `lib/features/onboarding/domain/nickname_rule.dart`
- Modify: `lib/features/onboarding/presentation/profile_setup_page.dart:116-118, 462-481`
- Modify: `lib/core/strings/app_strings.dart:120 근처`
- Test: `test/nickname_rule_test.dart`

**Interfaces:**
- Produces: `NicknameRule.of(int length, String value)` → `NicknameStatus` (`empty`/`tooShort`/`tooLong`/`invalidChars`/`valid`)

⚠️ **시그니처가 바뀐다.** 지금은 `of(int length)`다. 정규식을 검사하려면 원문이 필요한데,
길이는 여전히 화면이 세야 한다 — 사람이 보는 글자 수는 자소 단위고 그것은 `flutter/widgets`가
재수출하는 확장이라 **domain에서 쓸 수 없다.** 그래서 둘 다 받는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/nickname_rule_test.dart`의 기존 호출을 두 인자로 바꾸고, 아래 두 테스트를 파일 끝에 더한다.

```dart
  test('공백이 들어가면 막힌다', () {
    // 서버 정규식이 공백을 거절한다. 여기서 막지 않으면
    // 사용자는 다 채우고 나서 400을 받는다.
    expect(NicknameRule.of(4, '런서 김'), NicknameStatus.invalidChars);
  });

  test('특수문자와 이모지도 막힌다', () {
    expect(NicknameRule.of(7, 'runner!'), NicknameStatus.invalidChars);
    expect(NicknameRule.of(3, '러너🏃'), NicknameStatus.invalidChars);
  });

  test('한글 영문 숫자 밑줄은 통과한다', () {
    expect(NicknameRule.of(4, '러너42'), NicknameStatus.valid);
    expect(NicknameRule.of(8, 'runner_1'), NicknameStatus.valid);
  });

  test('길이를 먼저 본다', () {
    // 길이가 틀렸으면 문자 규칙보다 길이를 먼저 알린다.
    // 둘 다 틀렸을 때 "2자 이상"이 "쓸 수 없는 문자"보다 고치기 쉽다.
    expect(NicknameRule.of(1, '!'), NicknameStatus.tooShort);
  });
```

기존 테스트의 호출을 이렇게 고친다.

```dart
    expect(NicknameRule.of(0, ''), NicknameStatus.empty);
    expect(NicknameRule.of(0, '').isValid, isFalse);
    expect(NicknameRule.of(1, '가'), NicknameStatus.tooShort);
    expect(NicknameRule.of(NicknameRule.min, '가나'), NicknameStatus.valid);
    expect(NicknameRule.of(NicknameRule.max, '가' * 12), NicknameStatus.valid);
    expect(NicknameRule.of(NicknameRule.max + 1, '가' * 13), NicknameStatus.tooLong);
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/nickname_rule_test.dart
```
기대: 컴파일 실패 — `of`가 인자 하나만 받는다.

- [ ] **Step 3: `nickname_rule.dart`를 고친다**

`NicknameStatus`에 값을 더한다.

```dart
enum NicknameStatus {
  /// 아직 아무것도 입력하지 않았다. 오류가 아니라 시작 상태다.
  empty,

  tooShort,
  tooLong,

  /// 쓸 수 없는 문자가 들어 있다. 서버 정규식과 같은 기준이다.
  invalidChars,

  valid;

  bool get isValid => this == NicknameStatus.valid;
}
```

`NicknameRule`을 고친다.

```dart
abstract final class NicknameRule {
  static const min = 2;
  static const max = 12;

  /// 서버 `OnboardRequest`와 **같은 정규식**이다.
  ///
  /// ⚠️ 백엔드가 이 규칙을 바꾸면 앱이 어긋난다. 증상은 "앱은 통과시켰는데 서버가 400"이다.
  /// 비밀번호에서 이미 겪은 문제라 `docs/implementation-notes.md`에 항목이 있다.
  static final _allowed = RegExp(r'^[가-힣a-zA-Z0-9_]+$');

  /// [length]는 **앞뒤 공백을 제외한 자소 개수**, [value]는 그 원문이다.
  ///
  /// 길이를 화면에서 받는 이유는 자소 단위 계산이 `flutter/widgets`의 확장이고
  /// **domain은 순수 Dart여야** 해서다. 원문은 정규식 검사에만 쓴다.
  static NicknameStatus of(int length, String value) {
    if (length == 0) return NicknameStatus.empty;
    if (length < min) return NicknameStatus.tooShort;
    if (length > max) return NicknameStatus.tooLong;
    // 길이를 먼저 본다. 둘 다 틀렸을 때 길이가 고치기 쉽다.
    if (!_allowed.hasMatch(value)) return NicknameStatus.invalidChars;
    return NicknameStatus.valid;
  }
}
```

- [ ] **Step 4: 문구를 더한다**

`app_strings.dart`의 `profileNicknameTooLong` 아래에 넣는다.

```dart
  /// 서버 정규식(`^[가-힣a-zA-Z0-9_]+$`)에 걸리는 문자를 썼을 때.
  /// 무엇이 되는지를 말한다 — 무엇이 안 되는지를 나열하면 길고 외우기 어렵다.
  static const profileNicknameInvalidChars = '한글, 영문, 숫자, _만 쓸 수 있어요';
```

- [ ] **Step 5: 화면을 맞춘다**

`profile_setup_page.dart`의 `_nicknameStatus` getter를 고친다.

```dart
  NicknameStatus get _nicknameStatus =>
      NicknameRule.of(_nicknameLength, _nickname.text.trim());
```

`_nicknameField()`의 `switch`에 케이스를 더한다.

```dart
            NicknameStatus.invalidChars => (
              AppStrings.profileNicknameInvalidChars,
              AppInputTone.error,
            ),
```

- [ ] **Step 6: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/nickname_rule_test.dart test/profile_setup_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

- [ ] **Step 7: 커밋**

```bash
git add lib/features/onboarding/domain/nickname_rule.dart lib/features/onboarding/presentation/profile_setup_page.dart lib/core/strings/app_strings.dart test/nickname_rule_test.dart
git commit -m "📍 Feat: 닉네임에 서버와 같은 문자 규칙을 적용한다"
```

---

## Task 2: 성별을 문자열에서 enum으로 올린다

**Files:**
- Create: `lib/features/onboarding/domain/gender.dart`
- Modify: `lib/features/onboarding/presentation/profile_setup_page.dart:79, 275-282, 383-398`
- Test: `test/profile_setup_test.dart` (기존이 깨지면 고친다)

**Interfaces:**
- Produces: `enum Gender { male, female }` · `Gender.wireValue` → `'MALE'`/`'FEMALE'` · `Gender.fromLabel(String)`

- [ ] **Step 1: `gender.dart`를 만든다**

```dart
/// 성별 — 서버가 받는 두 값.
///
/// 화면은 한국어로 보여주고 서버는 대문자 영문을 받는다. 그 변환을 화면이
/// 하게 두면 **표시 문구를 고칠 때 전송값까지 같이 깨진다.** 여기서 한 번만 옮긴다.
///
/// 남성·여성 둘뿐인 이유는 칼로리·페이스 계산식이 이분법을 전제해서다.
/// 그 계산이 필요 없는 곳(프로필 공개 정보 등)까지 이 값을 끌어다 쓰면 안 된다.
enum Gender {
  male,
  female;

  /// 서버 `OnboardRequest.gender`가 받는 값.
  String get wireValue => switch (this) {
    Gender.male => 'MALE',
    Gender.female => 'FEMALE',
  };
}
```

⚠️ **한국어 라벨은 여기 두지 않는다.** `AppStrings`가 문구를 갖고, 화면이 둘을 잇는다.
domain이 `AppStrings`를 import하면 domain이 화면 문구에 묶인다.

- [ ] **Step 2: 화면을 바꾼다**

`profile_setup_page.dart`의 필드 선언(79행 근처)을 바꾼다.

```dart
  Gender? _gender;
```

`_answerOf`의 성별 줄을 바꾼다.

```dart
    _stepGender => _gender == Gender.male
        ? AppStrings.profileGenderMale
        : AppStrings.profileGenderFemale,
```

`_currentQuestion()`의 성별 칩을 바꾼다.

```dart
    _stepGender => _Question(
      key: const ValueKey(_stepGender),
      question: AppStrings.profileGenderQuestion,
      why: AppStrings.profileGenderWhy,
      child: _ChipRow(
        options: const [
          AppStrings.profileGenderMale,
          AppStrings.profileGenderFemale,
        ],
        selected: _gender == null
            ? null
            : (_gender == Gender.male
                  ? AppStrings.profileGenderMale
                  : AppStrings.profileGenderFemale),
        onPick: (value) {
          setState(() {
            _gender = value == AppStrings.profileGenderMale
                ? Gender.male
                : Gender.female;
          });
          _advance();
        },
      ),
    ),
```

import를 더한다: `package:runiverse/features/onboarding/domain/gender.dart`

- [ ] **Step 3: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/profile_setup_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개. 화면 동작은 그대로라 기존 테스트가 그대로 통과해야 한다.

- [ ] **Step 4: 커밋**

```bash
git add lib/features/onboarding/domain/gender.dart lib/features/onboarding/presentation/profile_setup_page.dart
git commit -m "🤖 Refactor: 성별을 문자열 대신 enum으로 다룬다"
```

---

## Task 3: 도메인 — 엔티티 · 실패 · 인터페이스

**Files:**
- Create: `lib/features/onboarding/domain/onboarding_profile.dart`
- Create: `lib/features/onboarding/domain/onboarding_failure.dart`
- Create: `lib/features/onboarding/domain/onboarding_repository.dart`

**Interfaces:**
- Consumes: Task 2의 `Gender`
- Produces: `OnboardingProfile({nickname, gender, birthday, paceSecondsPerKm, heightCm, weightKg})` · `OnboardingFailure` · `OnboardingException` · `OnboardingRepository.submit(OnboardingProfile)`

**이 태스크에는 테스트가 없다.** 값 객체와 인터페이스뿐이라 검증할 동작이 없다.
Task 4의 DTO 테스트가 이 타입들을 처음 쓴다.

- [ ] **Step 1: `onboarding_profile.dart`를 만든다**

```dart
import 'package:runiverse/features/onboarding/domain/gender.dart';

/// 프로필 등록(S04)에서 모은 값.
///
/// 순수 Dart다. 화면이 어떻게 모았는지(휠 시트인지 칩인지)를 여기서 알 필요가 없다.
class OnboardingProfile {
  const OnboardingProfile({
    required this.nickname,
    required this.gender,
    required this.birthday,
    required this.paceSecondsPerKm,
    required this.heightCm,
    required this.weightKg,
  });

  final String nickname;
  final Gender gender;
  final DateTime birthday;

  /// 1km당 초. **`null`은 '미측정'이지 '아직 안 물어봄'이 아니다.**
  ///
  /// 서버는 이 값을 필수로 받는다. 그 차이는 DTO에서 메운다 —
  /// 화면과 시그니처 컬러는 `null`을 그대로 본다.
  final int? paceSecondsPerKm;

  final int heightCm;
  final int weightKg;
}
```

- [ ] **Step 2: `onboarding_failure.dart`를 만든다**

```dart
/// 프로필 전송이 실패한 이유.
///
/// `AuthFailure`와 같은 규칙이다 — 서버 `message`를 화면에 그대로 쓰지 않고
/// `code`를 계약으로 본다.
///
/// **`alreadyOnboarded`가 없는 것은 의도다.** 서버가 409로 "이미 했다"고 하면
/// 그것은 도메인상 성공이므로 repository가 흡수한다.
enum OnboardingFailure {
  /// 서버가 형식을 거절했다. 서버 `VALIDATION_FAILED` (400)
  ///
  /// **앱이 먼저 막았어야 할 값이 서버까지 갔다는 뜻이다.**
  validation,

  /// 다시 로그인해야 한다. 갱신까지 실패한 경우다.
  sessionExpired,

  /// 네트워크에 닿지 못했다.
  network,

  /// 서버가 5xx를 돌려줬다.
  server,

  /// 그 밖. 앱이 모르는 `code`가 왔을 때를 포함한다.
  unknown,
}

/// 저장소가 실패를 알리는 방법. 잡는 곳은 화면 하나다.
class OnboardingException implements Exception {
  const OnboardingException(this.failure);

  final OnboardingFailure failure;

  @override
  String toString() => 'OnboardingException($failure)';
}
```

- [ ] **Step 3: `onboarding_repository.dart`를 만든다**

```dart
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';

/// 프로필 등록을 서버에 반영한다.
///
/// 화면은 이 타입에만 기대고, 실제로 누가 답하는지 모른다.
///
/// 실패는 전부 `OnboardingException`으로 던진다. 구현체는 자기 사정
/// (HTTP 상태 코드, 소켓 예외 등)을 밖으로 흘리지 않는다.
abstract interface class OnboardingRepository {
  /// 성공하면 그냥 돌아온다.
  ///
  /// **서버가 409 `ALREADY_ONBOARD`로 답해도 성공으로 친다.** 서버가 이미
  /// 했다고 하면 그게 사실이고 뒤처진 것은 로컬 플래그다. 호출자마다 이 예외를
  /// 성공으로 번역하게 두면 언젠가 한 곳을 빠뜨린다.
  Future<void> submit(OnboardingProfile profile);
}
```

- [ ] **Step 4: analyze**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 경고 0개

- [ ] **Step 5: 커밋**

```bash
git add lib/features/onboarding/domain/
git commit -m "📍 Feat: 프로필 등록 도메인 타입을 정의한다"
```

---

## Task 4: DTO — 여기서만 서버 규격에 맞춘다

**Files:**
- Create: `lib/features/onboarding/data/onboarding_profile_dto.dart`
- Test: `test/onboarding_profile_dto_test.dart`

**Interfaces:**
- Consumes: Task 3의 `OnboardingProfile` · Task 2의 `Gender`
- Produces: `OnboardingProfileDto.from(OnboardingProfile)` · `.toJson()` → `Map<String, dynamic>`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/onboarding_profile_dto_test.dart`를 새로 만든다.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/onboarding/data/onboarding_profile_dto.dart';
import 'package:runiverse/features/onboarding/domain/gender.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';

/// 프로필 직렬화 — 앱의 값이 서버 규격으로 어떻게 옮겨지는가.
///
/// 순수 함수라 위젯 없이 테스트한다. 여기서 지키는 것은
/// **화면은 `null`을 유지하고 전송할 때만 720으로 바뀐다**는 규칙이다.
void main() {
  OnboardingProfile profileWith({int? pace}) => OnboardingProfile(
    nickname: '러너42',
    gender: Gender.male,
    birthday: DateTime(1998, 4, 12),
    paceSecondsPerKm: pace,
    heightCm: 172,
    weightKg: 63,
  );

  test('성별은 대문자 영문으로 나간다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    expect(json['gender'], 'MALE');
  });

  test('생년월일은 yyyy-MM-dd로 나간다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    // 한 자리 월·일에 0을 채우지 않으면 서버가 파싱하지 못한다.
    expect(json['birthday'], '1998-04-12');
  });

  test('페이스를 잰 사람은 그 값이 그대로 나간다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    expect(json['averagePaceSecondsPerKm'], 330);
  });

  test('페이스를 건너뛰면 720으로 바뀌어 나간다', () {
    final json = OnboardingProfileDto.from(profileWith()).toJson();

    // 서버가 이 필드를 필수로 받는다. 화면은 null을 그대로 들고 있고
    // 여기서만 바꾼다 — 서버가 nullable이 되면 이 규칙만 지우면 된다.
    expect(json['averagePaceSecondsPerKm'], 720);
  });

  test('720은 서버가 받는 범위 안이다', () {
    final json = OnboardingProfileDto.from(profileWith()).toJson();
    final pace = json['averagePaceSecondsPerKm'] as int;

    // 서버 검증은 120~1800이다. 치환값이 그 밖으로 나가면 400을 받는다.
    expect(pace, greaterThanOrEqualTo(120));
    expect(pace, lessThanOrEqualTo(1800));
  });

  test('키와 몸무게는 숫자로 나간다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    expect(json['heightCm'], isNull, reason: '서버 필드명은 height다');
    expect(json['height'], 172);
    expect(json['weight'], 63);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/onboarding_profile_dto_test.dart
```
기대: 컴파일 실패 — `OnboardingProfileDto`가 없다.

- [ ] **Step 3: `onboarding_profile_dto.dart`를 만든다**

```dart
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/domain/pace_level.dart';

/// `POST /users/onboarding`이 받는 몸통.
///
/// ## 앱과 서버가 다른 곳을 여기서만 메운다
///
/// 화면과 도메인은 앱의 사정대로 두고, **경계인 여기서만** 서버 규격으로 옮긴다.
/// 그래야 서버가 규격을 바꿔도 고칠 곳이 한 군데다.
class OnboardingProfileDto {
  const OnboardingProfileDto({
    required this.nickname,
    required this.gender,
    required this.birthday,
    required this.averagePaceSecondsPerKm,
    required this.height,
    required this.weight,
  });

  /// 서버가 평균 페이스를 **필수**로 받아서, 재본 적 없는 사람에게 쓸 값.
  ///
  /// 앱 휠의 최대치(12분/km)다. 서버 허용 범위(120~1800초) 안에 있다.
  ///
  /// ⚠️ **서버가 nullable로 바뀌면 이 상수와 아래 `??`를 지운다.** 그때까지
  /// 서버가 아는 값(720)과 앱이 보여주는 색(미정 코럴)이 다르다.
  static const unmeasuredPace = PaceRule.maxMinutes * 60; // 720

  final String nickname;
  final String gender;
  final String birthday;
  final int averagePaceSecondsPerKm;
  final int height;
  final int weight;

  factory OnboardingProfileDto.from(OnboardingProfile profile) =>
      OnboardingProfileDto(
        nickname: profile.nickname,
        gender: profile.gender.wireValue,
        birthday: _formatDate(profile.birthday),
        averagePaceSecondsPerKm: profile.paceSecondsPerKm ?? unmeasuredPace,
        height: profile.heightCm,
        weight: profile.weightKg,
      );

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'gender': gender,
    'birthday': birthday,
    'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
    'height': height,
    'weight': weight,
  };

  /// 서버 `LocalDate`가 받는 `yyyy-MM-dd`.
  ///
  /// 한 자리 월·일에 0을 채우지 않으면 파싱에 실패한다.
  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
```

- [ ] **Step 4: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/onboarding_profile_dto_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

- [ ] **Step 5: 커밋**

```bash
git add lib/features/onboarding/data/onboarding_profile_dto.dart test/onboarding_profile_dto_test.dart
git commit -m "📍 Feat: 프로필을 서버 규격으로 옮기는 DTO를 만든다"
```

---

## Task 5: 서버 호출 구현

**Files:**
- Create: `lib/features/onboarding/data/http_onboarding_repository.dart`
- Create: `lib/features/onboarding/data/fake_onboarding_repository.dart`

**Interfaces:**
- Consumes: Task 3의 `OnboardingRepository` · Task 4의 `OnboardingProfileDto` · `TokenStore` · `AuthRepository`
- Produces: `HttpOnboardingRepository(Dio, TokenStore, AuthRepository)` · `FakeOnboardingRepository({Duration latency})`

**이 태스크에는 자동 테스트가 없다.** 실제 HTTP를 호출하는 코드라 위젯 테스트에서
확인할 수 없다. `FakeOnboardingRepository`가 Task 6의 화면 테스트를 받쳐준다.
서버 호출 자체는 Task 7 에뮬레이터 확인이 유일한 검증이다.

- [ ] **Step 1: `http_onboarding_repository.dart`를 만든다**

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/onboarding/data/onboarding_profile_dto.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_repository.dart';

/// 진짜 서버를 부르는 [OnboardingRepository].
///
/// ## 인터셉터를 쓰지 않는다
///
/// `Authorization` 헤더가 필요한 요청은 지금 이것 하나뿐이다. 인터셉터를 만들면
/// 요청마다 저장소를 읽거나 토큰 캐시를 따로 관리해야 하는데, 대상이 하나인
/// 상태에서는 **관리할 것만 늘어난다.** 인증 요청이 늘어나는 시점에 올린다.
///
/// ## 왜 `AuthRepository`를 받는가
///
/// access 토큰은 30분이라 프로필을 천천히 채우는 동안 만료될 수 있다. 그때
/// 401을 그대로 돌려주면 **다섯 개를 다 입력한 사람의 값이 날아간다.**
/// 여기서 갱신 한 번을 하고 다시 보낸다.
class HttpOnboardingRepository implements OnboardingRepository {
  HttpOnboardingRepository(this._dio, this._store, this._auth);

  final Dio _dio;
  final TokenStore _store;
  final AuthRepository _auth;

  static const _path = '/api/v1/users/onboarding';

  @override
  Future<void> submit(OnboardingProfile profile) async {
    final body = OnboardingProfileDto.from(profile).toJson();

    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      // 토큰 없이 부르면 서버가 401을 준다. 그 전에 멈춘다 —
      // 원인이 "로그인이 안 되어 있다"인데 서버 응답을 뒤지게 된다.
      throw const OnboardingException(OnboardingFailure.sessionExpired);
    }

    try {
      await _post(body, accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw OnboardingException(_failureOf(error));
      }
      // access가 만료됐다. 갱신하고 한 번만 다시 보낸다.
      await _post(body, await _refreshed(stored.refreshToken));
    }
  }

  Future<void> _post(Map<String, dynamic> body, String accessToken) => _dio
      .post<Object?>(
        _path,
        data: body,
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          // 409는 성공으로 흡수하므로 dio가 예외로 만들지 않게 한다.
          // 그러지 않으면 이 흐름이 catch 안에서 다시 갈라진다.
          validateStatus: (status) =>
              status != null && (status < 400 || status == 409),
        ),
      )
      .then((_) {});

  /// 새 access 토큰을 받아 저장하고 돌려준다.
  ///
  /// 갱신에 실패하면 되살릴 방법이 없다 — 다시 로그인해야 한다.
  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const OnboardingException(OnboardingFailure.sessionExpired);
    }
    try {
      final tokens = await _auth.refresh(refreshToken);
      // ⚠️ 회전된 refreshToken도 반드시 덮어쓴다. 안 하면 다음 갱신이 죽는다.
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.accessToken;
    } on AuthException catch (error) {
      throw OnboardingException(
        error.failure == AuthFailure.network
            ? OnboardingFailure.network
            : OnboardingFailure.sessionExpired,
      );
    }
  }

  /// 서버가 준 `code`를 앱의 실패 이유로 옮긴다.
  ///
  /// **상태 코드를 1차 근거로 삼는다.** `code` 노출 정책이 바뀌어도 동작한다.
  OnboardingFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return OnboardingFailure.network;
    }

    final response = error.response;
    final status = response?.statusCode ?? 0;
    if (status >= 500) return OnboardingFailure.server;

    final body = response?.data;
    if (status == 400) {
      // 사유는 `message`에만 있는데 그것을 갈라 읽으면 서버가 문구를 고칠 때
      // 조용히 깨진다. 화면에는 앱 문구를 쓰고, 여기서는 단서만 남긴다.
      if (kDebugMode) {
        debugPrint('[api] 온보딩 거절: ${body is Map ? body['message'] : ''}');
      }
      return OnboardingFailure.validation;
    }
    return OnboardingFailure.unknown;
  }
}
```

⚠️ **`validateStatus`로 409를 통과시키는 것이 이 파일의 핵심 선택이다.** 예외로 받아
`catch` 안에서 다시 가르면, 401 재시도 흐름과 409 흡수 흐름이 한 `catch`에 섞인다.

- [ ] **Step 2: `fake_onboarding_repository.dart`를 만든다**

```dart
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_repository.dart';

/// 서버 없이 화면을 돌려보기 위한 가짜 저장소.
///
/// 테스트가 쓴다. `HttpOnboardingRepository`는 실제 HTTP를 부르므로
/// 위젯 테스트에서 쓸 수 없다.
class FakeOnboardingRepository implements OnboardingRepository {
  FakeOnboardingRepository({
    this.latency = const Duration(milliseconds: 600),
    this.failWith,
  });

  /// 응답이 즉시 오면 로딩 표시가 화면에 뜨는지 확인할 수 없다.
  /// 테스트에서는 [Duration.zero]를 넣어 기다리지 않는다.
  final Duration latency;

  /// 실패를 흉내 낼 때 넣는다. `null`이면 성공한다.
  final OnboardingFailure? failWith;

  /// 전송된 프로필. 무엇이 넘어갔는지 테스트가 확인한다.
  OnboardingProfile? submitted;

  @override
  Future<void> submit(OnboardingProfile profile) async {
    await Future<void>.delayed(latency);
    if (failWith != null) throw OnboardingException(failWith!);
    submitted = profile;
  }
}
```

- [ ] **Step 3: analyze**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 경고 0개

- [ ] **Step 4: 커밋**

```bash
git add lib/features/onboarding/data/
git commit -m "📍 Feat: 프로필을 서버로 보내는 구현을 붙인다"
```

---

## Task 6: 화면을 전송에 잇는다

**Files:**
- Create: `lib/features/onboarding/presentation/onboarding_provider.dart`
- Modify: `lib/features/onboarding/presentation/profile_setup_page.dart` (`StatefulWidget` → `ConsumerStatefulWidget`, `_finish()`)
- Modify: `lib/features/auth/presentation/auth_provider.dart` (`markOnboarded` 추가)
- Modify: `lib/core/strings/app_strings.dart` (문구 2개)
- Test: `test/profile_setup_test.dart`

**Interfaces:**
- Consumes: Task 5의 두 repository · `AuthController`
- Produces: `onboardingRepositoryProvider` · `AuthController.markOnboarded()`

**전송 흐름에 위젯 테스트를 쓰지 않는다.**

`ProfileSetupPage`는 생년월일·키·몸무게·페이스를 **휠 시트**로 받는다. 끝까지 채우려면
모달을 열고 휠을 굴려야 하는데, `test/profile_setup_test.dart:14`가 이미 방침을 밝혀 뒀다 —
*"휠 시트는 여기서 다루지 않는다. 시트 안 동작은 별개 위젯의 몫"*. 기존 테스트도
`:101`에서 같은 이유로 성별 단계 앞에서 멈춘다.

그래서 이 태스크의 검증은 셋으로 나눈다.

| 무엇 | 어디 |
|---|---|
| 값이 서버 규격으로 옮겨지는가 | Task 4 `onboarding_profile_dto_test` |
| 완료가 저장소와 상태에 반영되는가 | 아래 Step 1 `auth_controller_test` |
| 전체 흐름이 실제로 도는가 | Task 7 에뮬레이터 |

CLAUDE.md가 정한 테스트 세 가지(순수 계산 · 색 결정론성 · 상태 전이) 중 앞의 둘에 해당한다.

- [ ] **Step 1: `markOnboarded` 테스트를 쓴다**

`test/auth_controller_test.dart`에 더한다.

```dart
  test('온보딩을 마치면 상태와 저장소가 함께 켜진다', () async {
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signUp(email: 'new@example.com', password: 'runi123!');
    // 가입 직후에는 아직 안 마친 상태다.
    expect(
      (container.read(authControllerProvider) as AuthSignedIn).isOnboarded,
      isFalse,
    );

    await controller.markOnboarded();

    // 상태만 켜고 저장소를 두면 앱을 껐다 켤 때 다시 프로필로 간다.
    expect(
      (container.read(authControllerProvider) as AuthSignedIn).isOnboarded,
      isTrue,
    );
    expect(
      (await container.read(tokenStoreProvider).read()).isOnboarded,
      isTrue,
    );
  });
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/auth_controller_test.dart
```
기대: 컴파일 실패 — `markOnboarded`가 없다.

- [ ] **Step 3: `AuthController.markOnboarded()`를 더한다**

`auth_provider.dart`의 `signOut()` 위에 넣는다.

```dart
  /// 프로필 등록을 마쳤다. **저장소와 상태를 함께** 켠다.
  ///
  /// 상태만 켜면 앱을 껐다 켰을 때 저장소가 여전히 `false`라 프로필로 다시 간다.
  /// 저장소만 켜면 지금 화면이 홈으로 넘어가지 않는다.
  Future<void> markOnboarded() async {
    await _store.markOnboarded();
    final current = state;
    if (current is AuthSignedIn) {
      state = AuthSignedIn(current.userId, isOnboarded: true);
    }
  }
```

- [ ] **Step 4: `onboarding_provider.dart`를 만든다**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/data/http_onboarding_repository.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_repository.dart';

/// 누가 프로필 전송에 답할 것인가.
///
/// ⚠️ **이 파일은 `presentation`에 있으면서 `data`를 import한다.** 의존 방향
/// (`presentation → domain ← data`)의 예외인데, 구현체를 고르는 일은 어딘가에서
/// 반드시 해야 하고 그 자리가 여기다 — `auth_provider.dart`와 같은 규칙이다.
/// 화면 파일은 여전히 `data`를 모른다.
final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => HttpOnboardingRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);
```

- [ ] **Step 5: 문구를 더한다**

`app_strings.dart`의 프로필 문구 끝에 넣는다.

```dart
  /// 프로필 전송이 실패했을 때. 입력은 화면에 그대로 남는다.
  static const profileSubmitFailed = '저장하지 못했어요. 다시 시도해주세요';

  /// 세션이 끊겨 다시 로그인해야 할 때.
  static const profileSubmitExpired = '로그인이 만료됐어요. 다시 로그인해주세요';
```

- [ ] **Step 6: 화면을 잇는다**

`profile_setup_page.dart`를 `ConsumerStatefulWidget`으로 바꾼다.

```dart
class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage>
    with SingleTickerProviderStateMixin {
```

전송 상태 필드를 더한다.

```dart
  /// 전송 중. 버튼이 두 번 눌리는 것을 막는다.
  bool _submitting = false;

  /// 전송이 실패한 이유. 성공하면 화면을 떠나므로 `null`로 되돌릴 일이 없다.
  OnboardingFailure? _submitFailure;
```

`_finish()`를 바꾼다.

```dart
  Future<void> _finish() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _submitFailure = null;
    });

    final profile = OnboardingProfile(
      nickname: _nickname.text.trim(),
      gender: _gender!,
      birthday: _birth!,
      paceSecondsPerKm: _paceSeconds,
      heightCm: _height!,
      weightKg: _weight!,
    );

    OnboardingFailure? failure;
    try {
      await ref.read(onboardingRepositoryProvider).submit(profile);
      await ref.read(authControllerProvider.notifier).markOnboarded();
    } on OnboardingException catch (error) {
      failure = error.failure;
    }

    // await 사이에 화면이 사라졌을 수 있다.
    if (!mounted) return;

    if (failure != null) {
      // 입력은 그대로 둔다. 다섯 개를 다시 채우게 하지 않는다.
      setState(() {
        _submitting = false;
        _submitFailure = failure;
      });
      return;
    }

    // ⚠️ 원래는 시그니처 컬러 리빌(S04.5)로 간다. 그 화면이 아직 없어 홈으로 보낸다.
    // 리빌이 생기면 PaceRule.levelOf(_paceSeconds)를 넘긴다.
    context.go(AppRoutes.home);
  }
```

하단 버튼을 바꾼다.

```dart
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_submitFailure != null) ...[
                    Text(
                      _submitFailure == OnboardingFailure.sessionExpired
                          ? AppStrings.profileSubmitExpired
                          : AppStrings.profileSubmitFailed,
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: colors.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space3),
                  ],
                  AppButton(
                    label: AppStrings.profileNext,
                    // 전송 중에는 잠근다. 두 번 누르면 요청이 두 번 나간다.
                    onPressed: (done && !_submitting) ? _finish : null,
                  ),
                ],
              ),
            ),
```

import를 더한다.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/domain/gender.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_provider.dart';
```

`colors.error`는 `app_colors.dart:70`에 있는 토큰이다. **`Color(0x...)`를 직접 쓰지 않는다.**

- [ ] **Step 7: 기존 화면 테스트를 `ProviderScope`로 감싼다**

`test/profile_setup_test.dart`의 `pumpPage`를 바꾼다.

```dart
  Future<void> pumpPage(
    WidgetTester tester, {
    FakeOnboardingRepository? onboarding,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          onboardingRepositoryProvider.overrideWithValue(
            onboarding ?? FakeOnboardingRepository(latency: Duration.zero),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const ProfileSetupPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
```

- [ ] **Step 8: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 전체 PASS · 경고 0개

- [ ] **Step 9: 커밋**

```bash
git add lib/ test/
git commit -m "📍 Feat: 프로필 등록을 마치면 서버에 반영한다"
```

---

## Task 7: 검증과 PR

**Files:** 없음 (확인과 문서)

- [ ] **Step 1: 전체를 돌린다**

```powershell
& ".fvm\flutter_sdk\bin\dart.bat" format lib test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug
```
기대: 전체 PASS · 경고 0개 · 빌드 성공

⚠️ `format`이 **이번에 손대지 않은 파일**을 바꾸면 그 변경은 되돌린다
(`git checkout -- <파일>`). 인접 코드를 건드리지 않는다.

- [ ] **Step 2: 에뮬레이터에서 확인한다**

터널을 열고 에뮬레이터를 띄운 뒤 서버 주소를 주입해 빌드·설치한다.
**에뮬레이터 화면이 얼어붙으면 콜드 부팅한다** (`-no-snapshot-load`) — 앱 문제가 아니다.

| # | 조작 | 기대 | 확인 방법 |
|---|---|---|---|
| 1 | 로그인 → 프로필 등록 화면 | 프로필 화면 | `login ← 200` |
| 2 | 닉네임에 `런서 김` 입력 | **입력 자리에서 막힌다** | "한글, 영문, 숫자, _만 쓸 수 있어요" |
| 3 | 6개를 다 채우고 [다음] | 홈으로 | `→ POST /api/v1/users/onboarding` · `← 201` |
| 4 | **앱 강제 종료 → 재실행** | **홈** (프로필 아님) | `refresh ← 200` |
| 5 | 페이스를 건너뛰고 다른 계정으로 3~4 반복 | 홈 | 서버에 720이 저장된다 |
| 6 | 기내 모드에서 [다음] | "저장하지 못했어요" · 입력 유지 | `connectionError` |

**4번이 이 PR의 핵심 검증이다.** 서버 `isOnboarded`가 실제로 켜졌는지는
재시작해서 홈으로 들어가야만 확인된다.

- [ ] **Step 3: PR을 연다**

```bash
git push -u origin feat/onboarding-submit
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend --base dev \
  --title "📍 Feat: 프로필 등록을 서버에 반영한다"
```

**base가 `dev`인지 확인한다.** GitHub는 `main`을 기본으로 잡는다.

PR 본문은 `.github/pull_request_template.md`의 6개 절을 채운다. 💬 리뷰 포인트에 적는다.

- **페이스를 건너뛰면 720(12분/km)이 서버로 나간다.** 화면과 시그니처 컬러는 `null`(미정 코럴)을 유지한다. **서버가 아는 값과 앱이 보여주는 색이 다르다** — 서버가 색을 계산하게 되면 갈라진다. 백엔드에 nullable을 요청해 둔 상태다
- **닉네임 규칙이 앱과 서버 두 곳에 있다.** 서버가 바꾸면 앱이 어긋난다
- `validateStatus`로 409를 통과시켜 `ALREADY_ONBOARD`를 성공으로 흡수한 선택
- 실패 문구 2개는 디자인 확인이 필요하다

- [ ] **Step 4: 문서를 갱신한다**

`docs/implementation-notes.md` §9-3이 "서버는 온보딩 여부를 모른다"고 적고 있다면
**낡았다** — PR 1에서 `isOnboarded`를 쓰기 시작했고 이 PR이 서버에 반영까지 붙였다.
해당 절을 고치고 별도 커밋(`📝 Docs`)으로 올린다.

---

## 완료 조건

- [ ] `flutter test` 전체 통과
- [ ] `flutter analyze` 경고 0개
- [ ] `flutter build apk --debug` 성공
- [ ] Task 7 Step 2의 에뮬레이터 확인 6개 항목 통과 (특히 4번)
- [ ] PR이 `dev`를 base로 열려 있음

---

## 이 PR이 하지 않는 것

| | 어디서 |
|---|---|
| 시그니처 컬러 리빌 (S04.5) | 그 화면이 생길 때 |
| `signOut`이 `POST /auth/logout`을 부르기 | 로그아웃 UI가 생길 때 |
| 인증 헤더 인터셉터 | 인증이 필요한 요청이 둘 이상 될 때 |
| iOS 재설치 시 Keychain 비우기 | iOS 전환 시 |
| 마케팅 동의 항목 | 백엔드 필드 스펙 확인 후 (별도 작업) |
