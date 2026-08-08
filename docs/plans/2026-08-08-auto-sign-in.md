# 자동 로그인 (PR 1) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱을 껐다 켜도 로그인이 유지되고, 스플래시가 저장된 토큰 상태에 따라 네 갈래로 갈라진다.

**Architecture:** 토큰을 `flutter_secure_storage`에 넣고, 스플래시에서 `POST /api/v1/auth/refresh`를 한 번 쳐서 갈림길을 정한다. 판정에 실패하면(네트워크·5xx) 스플래시에 머물며 재시도한다. `AuthState`를 세 갈래로 넓혀 "처음 켠 사람"과 "만료된 사람"을 구분한다.

**Tech Stack:** Flutter 3.44.8 (fvm) · Riverpod 3 · dio 5.11 · flutter_secure_storage

**설계 문서:** `docs/specs/2026-08-08-onboarding-flow-design.md` — 결정의 근거는 전부 여기 있다. 이 계획은 그것을 어떻게 만드는지만 적는다.

**브랜치:** `feat/auto-sign-in` (upstream/dev 기준, PR #13 머지 반영됨)

---

## Global Constraints

- **모든 flutter/dart 명령은 fvm SDK로 부른다.** `fvm`이 PATH에 없으므로 PowerShell에서 이렇게 쓴다:
  `& ".fvm\flutter_sdk\bin\flutter.bat" test`
- 내부 import는 항상 절대경로 `package:runiverse/...`
- 색·치수·문자열은 토큰으로만: `context.appColors` `AppSpacing` `AppTypography` `AppStrings`
- **IP 주소·포트·서버 주소를 주석이나 문서에 적지 않는다.**
- 커밋 메시지는 `<이모지> <Type>: <설명>` — `📍 Feat` `🔨 Fix` `📝 Docs` `🤖 Refactor` `✅ Test` `🚚 Chore`
- **AI를 공동 작성자로 넣지 않는다.** `Co-Authored-By` 트레일러도 `🤖 Generated with` 푸터도 붙이지 않는다
- 각 태스크 끝에 `& ".fvm\flutter_sdk\bin\flutter.bat" analyze` 경고 0개를 확인한다
- `StateProvider` / `StateNotifierProvider`를 쓰지 않는다 (Riverpod 3에서 레거시)
- 한 커밋에 논리적 변경 하나. 각 커밋 시점에 빌드가 되어야 한다

---

## 반드시 먼저 알아야 할 함정

**`SecureTokenStore`는 위젯 테스트에서 죽는다.** `flutter_secure_storage`는 플랫폼 채널을 부르는데 테스트 환경에는 채널이 없다.

`tokenStoreProvider`를 읽는 것은 `AuthController`뿐이고, `AuthController`가 만들어지는 시점은 **스플래시가 `restore()`를 부를 때**다. 따라서 **스플래시를 지나는 위젯 테스트는 전부 `tokenStoreProvider`를 override해야 한다.** Task 8이 이것을 처리한다.

Riverpod의 provider는 lazy라서, 스플래시를 건너뛰는 테스트(`home_page_test.dart` 등)는 영향을 받지 않는다.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `core/storage/token_store.dart` (수정) | `StoredAuth` 값 객체 + 인터페이스 6개 + `InMemoryTokenStore` |
| `core/storage/secure_token_store.dart` (신규) | `flutter_secure_storage` 구현. 플랫폼 옵션이 여기 모인다 |
| `features/auth/domain/auth_tokens.dart` (신규) | 갱신 결과. `userId`가 없는 것이 `AuthSession`과의 차이다 |
| `features/auth/domain/auth_session.dart` (수정) | `isOnboarded` 추가 |
| `features/auth/domain/auth_failure.dart` (수정) | `sessionExpired` · `validation` 추가 |
| `features/auth/domain/auth_repository.dart` (수정) | `refresh` 추가 |
| `features/auth/data/http_auth_repository.dart` (수정) | `refresh` 구현 · `isOnboarded` 읽기 · 새 code 매핑 |
| `features/auth/data/fake_auth_repository.dart` (수정) | `refresh` 구현 |
| `features/auth/presentation/auth_state.dart` (수정) | `AuthSignedOut(returning)` · `AuthSignedIn(userId, isOnboarded)` |
| `features/auth/presentation/auth_provider.dart` (수정) | `SecureTokenStore` 연결 · `restore()` 갈림길 |
| `features/onboarding/presentation/splash_page.dart` (수정) | 3분기 `switch` · 재시도 UI |
| `core/strings/app_strings.dart` (수정) | 재시도 문구 2개 |

---

## Task 1: TokenStore를 `StoredAuth` 한 번 읽기로 바꾼다

**Files:**
- Modify: `lib/core/storage/token_store.dart` (전면 개편)
- Modify: `lib/features/auth/presentation/auth_provider.dart:100-104` (`_authenticate`의 `save` 호출)
- Modify: `test/auth_controller_test.dart:64-67, 142` (읽기 API가 바뀐다)
- Test: `test/token_store_test.dart` (신규)

**Interfaces:**
- Produces: `StoredAuth({String? userId, String? accessToken, String? refreshToken, bool isOnboarded})` · `TokenStore.read()` `saveSession()` `saveTokens()` `markOnboarded()` `clearTokens()` `clear()` · `InMemoryTokenStore`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/token_store_test.dart`를 새로 만든다.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';

/// 토큰 저장소 — 무엇을 지우면 무엇이 남는가.
///
/// 이 파일이 지키는 것은 **`clearTokens()`가 `userId`를 남긴다**는 규칙이다.
/// 그것이 깨지면 만료된 사용자가 온보딩 소개를 다시 보게 된다.
void main() {
  Future<void> signIn(TokenStore store) => store.saveSession(
    userId: 'u-1',
    accessToken: 'a-1',
    refreshToken: 'r-1',
    isOnboarded: true,
  );

  test('아무것도 저장하지 않으면 전부 비어 있다', () async {
    final store = InMemoryTokenStore();

    final stored = await store.read();

    expect(stored.userId, isNull);
    expect(stored.accessToken, isNull);
    expect(stored.refreshToken, isNull);
    // 모르는 상태는 '안 했다'로 본다. 프로필을 한 번 더 묻는 쪽이
    // 프로필 없는 사용자를 홈에 들이는 것보다 안전하다.
    expect(stored.isOnboarded, isFalse);
  });

  test('세션을 저장하면 네 값이 함께 읽힌다', () async {
    final store = InMemoryTokenStore();

    await signIn(store);
    final stored = await store.read();

    expect(stored.userId, 'u-1');
    expect(stored.accessToken, 'a-1');
    expect(stored.refreshToken, 'r-1');
    expect(stored.isOnboarded, isTrue);
  });

  test('갱신은 토큰 둘만 덮어쓴다', () async {
    final store = InMemoryTokenStore();
    await signIn(store);

    await store.saveTokens(accessToken: 'a-2', refreshToken: 'r-2');
    final stored = await store.read();

    // 회전된 refreshToken을 덮어쓰지 않으면 다음 갱신이 401로 죽는다.
    expect(stored.accessToken, 'a-2');
    expect(stored.refreshToken, 'r-2');
    expect(stored.userId, 'u-1');
    expect(stored.isOnboarded, isTrue);
  });

  test('온보딩 완료는 플래그만 켠다', () async {
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: false,
    );

    await store.markOnboarded();
    final stored = await store.read();

    expect(stored.isOnboarded, isTrue);
    expect(stored.accessToken, 'a-1');
  });

  test('clearTokens는 토큰만 지우고 userId를 남긴다', () async {
    final store = InMemoryTokenStore();
    await signIn(store);

    await store.clearTokens();
    final stored = await store.read();

    // 이 둘이 남아야 "이 기기는 로그인한 적이 있다"를 알 수 있고,
    // 그래야 만료된 사용자를 온보딩 소개가 아닌 로그인 화면으로 보낸다.
    expect(stored.userId, 'u-1');
    expect(stored.isOnboarded, isTrue);
    expect(stored.accessToken, isNull);
    expect(stored.refreshToken, isNull);
  });

  test('clear는 전부 지운다', () async {
    final store = InMemoryTokenStore();
    await signIn(store);

    await store.clear();
    final stored = await store.read();

    expect(stored.userId, isNull);
    expect(stored.isOnboarded, isFalse);
  });

  test('빈 문자열은 null로 읽힌다', () async {
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: '',
      accessToken: '',
      refreshToken: '',
      isOnboarded: false,
    );

    final stored = await store.read();

    // 빈 refreshToken을 서버에 보내면 400 VALIDATION_FAILED가 온다.
    // 보내기 전에 여기서 걸러야 원인이 가까운 곳에 남는다.
    expect(stored.userId, isNull);
    expect(stored.refreshToken, isNull);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/token_store_test.dart
```
기대: 컴파일 실패. `StoredAuth`와 `read`/`saveSession` 등이 없다.

- [ ] **Step 3: `token_store.dart`를 다시 쓴다**

파일 전체를 아래로 교체한다.

```dart
/// 저장소에서 한 번에 읽어 온 값.
///
/// 읽기를 하나로 합친 이유는 [TokenStore]의 실제 구현이 플랫폼 채널을 건너가기
/// 때문이다. 값마다 따로 읽으면 **스플래시에서만 왕복이 네 번** 생기고,
/// 나눠 읽는 사이에 값이 어긋날 수 있다.
class StoredAuth {
  const StoredAuth({
    this.userId,
    this.accessToken,
    this.refreshToken,
    this.isOnboarded = false,
  });

  /// 저장된 것이 없으면 `null`. **로그인한 적이 있는지의 판단 기준이다.**
  final String? userId;

  final String? accessToken;
  final String? refreshToken;

  /// 프로필 등록을 마쳤는가. **모르면 `false`다** — 한 번 더 묻는 쪽이
  /// 프로필 없는 사용자를 홈에 들이는 것보다 안전하다.
  final bool isOnboarded;
}

/// 로그인 토큰을 어디에 넣어둘 것인가.
///
/// ## 왜 `AuthSession`을 받지 않는가
///
/// `AuthSession`은 `features/auth/domain`에 있다. `core`가 그것을 import하면
/// **`core → features` 방향이 생겨 의존 방향이 뒤집힌다.** 그래서 문자열만 주고받는다.
///
/// ## 왜 전부 `Future`인가
///
/// [InMemoryTokenStore]는 기다릴 것이 없다. 그런데 실제 구현
/// (`flutter_secure_storage` — 안드로이드 Keystore / iOS Keychain)은 플랫폼 채널을
/// 건너가므로 반드시 비동기다. 지금부터 비동기로 맞춰둔다.
///
/// ## 지우는 메서드가 둘인 이유
///
/// [clearTokens]는 토큰만, [clear]는 전부 지운다.
/// 토큰이 만료됐을 때 `userId`까지 지우면 다음 실행에 **온보딩 소개를 다시 보게 된다** —
/// 그 사람은 처음 온 것이 아니라 다시 로그인하면 되는 사람이다.
abstract interface class TokenStore {
  /// 왕복 한 번으로 네 값을 다 읽는다. 빈 문자열은 `null`로 걸러 내보낸다.
  Future<StoredAuth> read();

  /// 로그인 · 가입 성공.
  Future<void> saveSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
    required bool isOnboarded,
  });

  /// 갱신 성공. **토큰 둘만** 덮어쓴다.
  ///
  /// 서버가 리프레시 토큰을 회전시키므로 새 값을 반드시 저장해야 한다.
  /// 덮어쓰지 않으면 다음 갱신이 401로 죽는다 — 유효기간이 남아 있어도.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });

  /// 프로필 등록을 마쳤다.
  Future<void> markOnboarded();

  /// 토큰이 만료됐다. `userId`와 `isOnboarded`는 남긴다.
  Future<void> clearTokens();

  /// 로그아웃. 전부 비운다.
  Future<void> clear();
}

/// 메모리에만 들고 있는 구현.
///
/// **앱을 끄면 사라진다.** 앱에서는 `SecureTokenStore`를 쓰고, 이것은 테스트가 쓴다 —
/// 위젯 테스트는 플랫폼 채널을 부를 수 없다.
class InMemoryTokenStore implements TokenStore {
  String? _userId;
  String? _accessToken;
  String? _refreshToken;
  bool _isOnboarded = false;

  @override
  Future<StoredAuth> read() async => StoredAuth(
    userId: _blankToNull(_userId),
    accessToken: _blankToNull(_accessToken),
    refreshToken: _blankToNull(_refreshToken),
    isOnboarded: _isOnboarded,
  );

  @override
  Future<void> saveSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
    required bool isOnboarded,
  }) async {
    _userId = userId;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _isOnboarded = isOnboarded;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> markOnboarded() async => _isOnboarded = true;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<void> clear() async {
    _userId = null;
    _accessToken = null;
    _refreshToken = null;
    _isOnboarded = false;
  }
}

/// 빈 문자열을 `null`로 바꾼다.
///
/// 빈 `refreshToken`을 서버에 보내면 400 `VALIDATION_FAILED`가 온다.
/// 보내기 전에 걸러야 원인이 가까운 곳에 남는다.
String? _blankToNull(String? value) =>
    (value == null || value.isEmpty) ? null : value;
```

- [ ] **Step 4: `auth_provider.dart`의 저장 호출을 고친다**

`_authenticate` 안의 `_store.save(...)`를 바꾼다. `session.isOnboarded`는 Task 3에서 생기므로 **지금은 `false`를 넣고 Task 3에서 되돌아온다.**

```dart
      await _store.saveSession(
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        // ⚠️ Task 3에서 session.isOnboarded로 바꾼다. 지금은 AuthSession에 자리가 없다.
        isOnboarded: false,
      );
```

`restore()`도 `readUserId()`를 부르므로 컴파일이 깨진다. 임시로 `read()`를 쓰게 고친다 (Task 6에서 전면 재작성한다).

```dart
  Future<void> restore() async {
    final stored = await _store.read();
    state = stored.userId == null
        ? const AuthSignedOut()
        : AuthSignedIn(stored.userId!);
  }
```

- [ ] **Step 5: 기존 테스트의 읽기 호출을 고친다**

`test/auth_controller_test.dart:64-67`을 바꾼다.

```dart
    final stored = await container.read(tokenStoreProvider).read();
    expect(stored.userId, isNotNull);
    expect(stored.accessToken, isNotNull);
    expect(stored.refreshToken, isNotNull);
```

`test/auth_controller_test.dart:142`를 바꾼다.

```dart
    expect((await container.read(tokenStoreProvider).read()).userId, isNull);
```

- [ ] **Step 6: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/token_store_test.dart test/auth_controller_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: 테스트 전부 PASS · analyze 경고 0개

- [ ] **Step 7: 커밋**

```bash
git add lib/core/storage/token_store.dart lib/features/auth/presentation/auth_provider.dart test/token_store_test.dart test/auth_controller_test.dart
git commit -m "🤖 Refactor: 토큰 저장소를 한 번 읽기로 바꾸고 부분 삭제를 나눈다"
```

---

## Task 2: `SecureTokenStore` — 실제 저장소

**Files:**
- Create: `lib/core/storage/secure_token_store.dart`
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/features/auth/presentation/auth_provider.dart:14`

**Interfaces:**
- Consumes: Task 1의 `TokenStore` · `StoredAuth`
- Produces: `SecureTokenStore()`

**이 태스크에는 자동 테스트가 없다.** 플랫폼 채널을 부르므로 위젯 테스트에서 돌릴 수 없다. 에뮬레이터에서 눈으로 확인한다.

- [ ] **Step 1: 패키지를 추가한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" pub add flutter_secure_storage:^10.3.1
```

⚠️ **버전을 고정한다.** 최신인 11.0.0은 `compileSdk 37`을 요구하는데 AGP가 찾는
`android-37`이 SDK에 없다 (설치된 것은 `android-37.0`뿐이라 인식되지 않는다).
**`flutter test`와 `analyze`는 통과하고 `flutter build apk`에서만 드러난다** —
이 태스크에서 반드시 빌드까지 돌려야 하는 이유다.

- [ ] **Step 2: `secure_token_store.dart`를 만든다**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:runiverse/core/storage/token_store.dart';

/// 안드로이드 Keystore · iOS Keychain에 넣는 [TokenStore].
///
/// ## 왜 평문 저장소를 쓰지 않는가
///
/// `refreshToken`은 **60일**짜리다. 유출되면 두 달 동안 계정을 계속 쓸 수 있다.
/// `shared_preferences`는 안드로이드에서 평문 XML이라 루팅 기기나 ADB 백업으로
/// 그대로 읽힌다.
///
/// ## 네 값을 한곳에 둔다
///
/// `isOnboarded`는 민감하지 않지만 여기 같이 넣는다. 저장소를 나누면
/// **토큰은 지웠는데 플래그가 남는 상태**가 생긴다. 한곳에 있으면 지우기가 한 번이다.
///
/// ## ⚠️ iOS에서 앱을 지워도 Keychain은 남는다
///
/// 재설치한 기기에서 이전 사용자의 토큰이 살아난다. 막으려면 "첫 실행이면 한 번
/// 비우기"가 필요하고, 그러려면 **앱과 함께 지워지는 저장소가 하나 더** 있어야 한다.
/// 안드로이드만 돌리는 지금은 미룬다 — iOS 전환 시 할 일이다.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // 안드로이드 옵션은 지정하지 않는다. 10.3.1부터 기본이
            // Keystore 기반 cipher다 — 예전 `encryptedSharedPreferences` 플래그는
            // deprecated이고 **넘겨도 무시된다**(Jetpack Security가 폐기됐다).
            //
            // iOS는 기본값이 기기 밖으로 백업되므로 바꾼다.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _keyUserId = 'auth.userId';
  static const _keyAccessToken = 'auth.accessToken';
  static const _keyRefreshToken = 'auth.refreshToken';
  static const _keyIsOnboarded = 'auth.isOnboarded';

  @override
  Future<StoredAuth> read() async {
    // readAll은 왕복 한 번이다. 값마다 read를 부르면 네 번 건너간다.
    final all = await _storage.readAll();
    return StoredAuth(
      userId: _blankToNull(all[_keyUserId]),
      accessToken: _blankToNull(all[_keyAccessToken]),
      refreshToken: _blankToNull(all[_keyRefreshToken]),
      isOnboarded: all[_keyIsOnboarded] == 'true',
    );
  }

  @override
  Future<void> saveSession({
    required String userId,
    required String accessToken,
    required String refreshToken,
    required bool isOnboarded,
  }) async {
    await _storage.write(key: _keyUserId, value: userId);
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyIsOnboarded, value: '$isOnboarded');
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  @override
  Future<void> markOnboarded() =>
      _storage.write(key: _keyIsOnboarded, value: 'true');

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }

  @override
  Future<void> clear() => _storage.deleteAll();
}

String? _blankToNull(String? value) =>
    (value == null || value.isEmpty) ? null : value;
```

- [ ] **Step 3: 안드로이드 백업을 끈다**

`android/app/src/main/AndroidManifest.xml`의 `<application` 여는 태그에 속성을 더한다.

```xml
    <application
        android:label="runiverse"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false">
```

이유를 바로 위에 주석으로 남긴다.

```xml
    <!-- 토큰이 클라우드 백업으로 나가지 않게 막는다. Keystore 키는 백업되지
         않아 복호화는 어차피 안 되지만, 암호문을 올릴 이유가 없다.
         백업할 데이터가 생기면 dataExtractionRules로 토큰만 제외하도록 나눈다. -->
```

- [ ] **Step 4: provider를 갈아끼운다**

`lib/features/auth/presentation/auth_provider.dart:14`

```dart
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
```

import를 추가한다: `package:runiverse/core/storage/secure_token_store.dart`

- [ ] **Step 5: analyze와 전체 테스트를 돌린다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test
```

⚠️ **테스트 네 파일이 여기서 깨진다.** Task 8로 미루지 말고 지금 고친다 — 커밋 시점마다 초록불을 유지하는 편이 낫다.

| 파일 | 증상 |
|---|---|
| `auth_controller_test.dart` | 순수 `test()`라 `ServicesBinding`이 없다 → "Binding has not yet been initialized" |
| `onboarding_flow_test.dart` | 스플래시가 갈림길을 정하지 못하고 멈춘다 |
| `sign_in_page_test.dart` · `sign_up_page_test.dart` | 로그인·가입이 토큰을 저장하려다 죽는다 |

각 파일의 `overrides:` 맨 앞에 한 줄을 넣고 `token_store.dart`를 import한다.

```dart
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
```

⚠️ **`testWidgets()`는 조용히 통과할 수도 있다.** 바인딩이 있으면 등록되지 않은 채널이 `null`을 돌려주기 때문이다. **저장이 안 되는데 초록불이 뜨는 상태**라 더 위험하다. 저장소를 건드리는 테스트는 예외 없이 override한다.

- [ ] **Step 6: 커밋**

```bash
git add pubspec.yaml pubspec.lock lib/core/storage/secure_token_store.dart lib/features/auth/presentation/auth_provider.dart android/app/src/main/AndroidManifest.xml
git commit -m "📍 Feat: 토큰을 Keystore·Keychain에 저장한다"
```

---

## Task 3: `AuthSession`이 `isOnboarded`를 들고 온다

**Files:**
- Modify: `lib/features/auth/domain/auth_session.dart`
- Modify: `lib/features/auth/data/http_auth_repository.dart:83-99`
- Modify: `lib/features/auth/data/fake_auth_repository.dart:75-79`
- Modify: `lib/features/auth/presentation/auth_provider.dart` (Task 1 Step 4의 `false`를 되돌린다)

**Interfaces:**
- Produces: `AuthSession({required String userId, required String accessToken, required String refreshToken, required bool isOnboarded})`

- [ ] **Step 1: `AuthSession`에 필드를 더한다**

```dart
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.isOnboarded,
  });

  final String userId;
  final String accessToken;
  final String refreshToken;

  /// 프로필 등록(S04)을 마쳤는가. 서버 로그인 응답이 알려준다.
  ///
  /// **갱신 응답(`POST /auth/refresh`)에는 이 값이 없다.** 그래서 로그인할 때
  /// 받은 값을 저장해 두고, 자동 로그인 경로에서는 저장된 값을 읽는다.
  final bool isOnboarded;
}
```

- [ ] **Step 2: `HttpAuthRepository._sessionOf`가 값을 읽게 한다**

83~99행을 바꾼다.

```dart
  AuthSession _sessionOf(Map<String, dynamic>? body) {
    final userId = body?['userId'];
    final accessToken = body?['accessToken'];
    final refreshToken = body?['refreshToken'];

    if (userId is! String || accessToken is! String || refreshToken is! String) {
      throw const AuthException(AuthFailure.unknown);
    }

    return AuthSession(
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      // 값이 없거나 타입이 다르면 false로 본다. 온보딩을 한 번 더 묻는 쪽이
      // 프로필 없는 사용자를 홈에 들이는 것보다 낫다.
      isOnboarded: body?['isOnboarded'] == true,
    );
  }
```

- [ ] **Step 3: `FakeAuthRepository`를 맞춘다**

75~79행을 바꾼다.

```dart
  /// 같은 이메일이면 항상 같은 `userId`가 나오게 이메일에서 만든다.
  /// 매번 새 번호를 매기면 로그인할 때마다 다른 사람이 된다.
  ///
  /// [isOnboarded]는 `_onboarded` 집합이 정한다 — 가입한 계정은 아직 안 한 것으로,
  /// 씨앗 계정은 이미 마친 것으로 둔다. 그래야 두 갈래를 서버 없이 시험할 수 있다.
  AuthSession _sessionFor(String email) => AuthSession(
    userId: 'fake-${email.hashCode.toRadixString(16)}',
    accessToken: 'fake-access-$email',
    refreshToken: 'fake-refresh-$email',
    isOnboarded: _onboarded.contains(email),
  );
```

클래스 필드에 집합을 더한다 (`_accounts` 선언 아래).

```dart
  /// 온보딩을 마친 계정. 씨앗 계정은 마친 것으로 시작한다 —
  /// 그래야 "기존 사용자가 로그인하면 홈으로" 경로를 시험할 수 있다.
  final Set<String> _onboarded = {seedEmail};
```

- [ ] **Step 4: `auth_provider.dart`의 임시값을 되돌린다**

Task 1 Step 4에서 `false`로 박아둔 자리를 고친다.

```dart
        isOnboarded: session.isOnboarded,
```

- [ ] **Step 5: 테스트를 더한다**

`test/auth_controller_test.dart` 끝에 추가한다.

```dart
  test('씨앗 계정으로 로그인하면 온보딩을 마친 상태로 저장된다', () async {
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signIn(
          email: FakeAuthRepository.seedEmail,
          password: FakeAuthRepository.seedPassword,
        );

    expect((await container.read(tokenStoreProvider).read()).isOnboarded, isTrue);
  });

  test('새로 가입하면 온보딩을 마치지 않은 상태로 저장된다', () async {
    final container = makeContainer();

    await container
        .read(authControllerProvider.notifier)
        .signUp(email: 'new@example.com', password: 'runi123!');

    // 이 값이 false여야 스플래시가 프로필 등록으로 보낸다.
    expect(
      (await container.read(tokenStoreProvider).read()).isOnboarded,
      isFalse,
    );
  });
```

⚠️ 이 테스트는 `tokenStoreProvider`를 override해야 한다. `makeContainer()`에 override를 더한다.

```dart
  ProviderContainer makeContainer() => ProviderContainer.test(
    overrides: [
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(latency: Duration.zero),
      ),
    ],
  );
```

import를 더한다: `package:runiverse/core/storage/token_store.dart`

- [ ] **Step 6: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/auth_controller_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

- [ ] **Step 7: 커밋**

```bash
git add lib/features/auth/ test/auth_controller_test.dart
git commit -m "📍 Feat: 로그인 응답의 온보딩 여부를 세션에 담는다"
```

---

## Task 4: 토큰 갱신 — `refresh`

**Files:**
- Create: `lib/features/auth/domain/auth_tokens.dart`
- Modify: `lib/features/auth/domain/auth_failure.dart`
- Modify: `lib/features/auth/domain/auth_repository.dart`
- Modify: `lib/features/auth/data/http_auth_repository.dart`
- Modify: `lib/features/auth/data/fake_auth_repository.dart`
- Test: `test/auth_controller_test.dart`

**Interfaces:**
- Consumes: Task 3의 `AuthSession`
- Produces: `AuthTokens({required String accessToken, required String refreshToken})` · `AuthRepository.refresh(String refreshToken)` · `AuthFailure.sessionExpired` · `AuthFailure.validation`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/auth_controller_test.dart` 끝에 추가한다.

```dart
  test('가짜 저장소는 발급했던 토큰만 갱신해 준다', () async {
    final repository = FakeAuthRepository(latency: Duration.zero);

    final session = await repository.signIn(
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );
    final tokens = await repository.refresh(session.refreshToken);

    // 서버가 회전시키므로 새 값이 와야 한다. 같은 값이 오면
    // "덮어쓰기를 잊어도 동작하는" 가짜가 되어 버그를 숨긴다.
    expect(tokens.accessToken, isNot(session.accessToken));
    expect(tokens.refreshToken, isNot(session.refreshToken));
  });

  test('모르는 리프레시 토큰은 세션 만료다', () async {
    final repository = FakeAuthRepository(latency: Duration.zero);

    expect(
      () => repository.refresh('nonsense'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.sessionExpired,
        ),
      ),
    );
  });
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/auth_controller_test.dart
```
기대: 컴파일 실패. `refresh`와 `sessionExpired`가 없다.

- [ ] **Step 3: `auth_tokens.dart`를 만든다**

```dart
/// 갱신에 성공했을 때 손에 남는 것.
///
/// `AuthSession`과 달리 **`userId`가 없다.** 서버 `ReissueResponse`가 토큰 둘만
/// 돌려주기 때문이다. 누구인지는 저장소에 이미 있으므로 다시 받을 필요가 없다.
///
/// ⚠️ **두 값을 모두 저장해야 한다.** 서버가 리프레시 토큰을 회전시키므로,
/// [refreshToken]을 덮어쓰지 않으면 다음 갱신이 401로 죽는다 — 유효기간이 남아 있어도.
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}
```

- [ ] **Step 4: `AuthFailure`에 둘을 더한다**

`enum AuthFailure`의 `network` 앞에 추가한다.

```dart
  /// 갱신: 리프레시 토큰이 만료됐거나 무효다. 서버 `INVALID_REFRESH_TOKEN` (401)
  ///
  /// [invalidCredentials]와 나눠 둔다. 화면이 다르게 말해야 한다 —
  /// 하나는 "비밀번호를 확인해 주세요"고, 다른 하나는 "다시 로그인해 주세요"다.
  /// **사용자는 아무것도 틀리지 않았다.**
  sessionExpired,

  /// 서버가 형식을 거절했다. 서버 `VALIDATION_FAILED` (400)
  ///
  /// **앱이 먼저 막았어야 할 값이 서버까지 갔다는 뜻이다.** 서버는 사유를
  /// `message`로만 주는데 그것을 갈라 읽으면 문구가 바뀔 때 조용히 깨진다.
  /// 화면에는 앱이 정한 문구 하나를 쓰고, `message`는 디버그 로그로만 남긴다.
  validation,
```

- [ ] **Step 5: `AuthRepository`에 `refresh`를 더한다**

import를 추가한다: `package:runiverse/features/auth/domain/auth_tokens.dart`

```dart
  /// 저장된 리프레시 토큰으로 새 토큰 쌍을 받는다.
  ///
  /// 실패 시 `AuthException(AuthFailure.sessionExpired)` — 다시 로그인해야 한다.
  ///
  /// **돌려받은 두 값을 모두 저장해야 한다.** 서버가 리프레시 토큰을 회전시킨다.
  Future<AuthTokens> refresh(String refreshToken);
```

- [ ] **Step 6: `HttpAuthRepository`에 구현한다**

경로 상수를 더한다.

```dart
  static const _refreshPath = '/api/v1/auth/refresh';
```

`signOut()` 아래에 메서드를 더한다.

```dart
  /// 갱신에만 짧은 시간 제한을 건다.
  ///
  /// 이 호출은 **스플래시가 기다리는 유일한 요청**이다. dio 기본값(10초)을 그대로
  /// 쓰면 연결이 나쁜 곳에서 앱이 10초 멈춘 것처럼 보인다.
  static const _refreshTimeout = Duration(seconds: 5);

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _refreshPath,
        data: {'refreshToken': refreshToken},
        options: Options(
          sendTimeout: _refreshTimeout,
          receiveTimeout: _refreshTimeout,
        ),
      );
      return _tokensOf(response.data);
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }

  /// 200을 받아도 몸통이 기대와 다를 수 있다. 못 읽으면 만들지 않는다.
  AuthTokens _tokensOf(Map<String, dynamic>? body) {
    final accessToken = body?['accessToken'];
    final refreshToken = body?['refreshToken'];

    if (accessToken is! String || refreshToken is! String) {
      throw const AuthException(AuthFailure.unknown);
    }
    return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
  }
```

`_failureOf`의 `switch`에 두 code를 더한다.

```dart
    if (code == 'VALIDATION_FAILED') {
      // 앱이 먼저 막았어야 할 값이 서버까지 갔다. 사유는 message에만 있는데
      // 그것을 갈라 읽으면 서버가 문구를 고칠 때 조용히 깨진다.
      // 화면에는 앱 문구를 쓰고, 여기서는 구멍을 찾을 단서만 남긴다.
      if (kDebugMode) {
        debugPrint('[api] 검증 거절: ${body is Map ? body['message'] : ''}');
      }
      return AuthFailure.validation;
    }

    return switch (code) {
      'INVALID_CREDENTIALS' => AuthFailure.invalidCredentials,
      'EMAIL_ALREADY_EXISTS' => AuthFailure.emailAlreadyExists,
      'INVALID_REFRESH_TOKEN' => AuthFailure.sessionExpired,
      _ => AuthFailure.unknown,
    };
```

import를 추가한다.

```dart
import 'package:flutter/foundation.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
```

⚠️ `message`는 서버가 정한 문구일 뿐 자격증명이 아니다. 그래도 **디버그 빌드에서만** 찍는다 — `kDebugMode` 밖으로 내보내지 않는다.

- [ ] **Step 7: `FakeAuthRepository`에 구현한다**

발급한 리프레시 토큰을 기억했다가 그것만 받아준다. 필드를 더한다.

```dart
  /// 발급해 준 리프레시 토큰. 모르는 값이 오면 만료로 답한다.
  final Set<String> _issuedRefreshTokens = {};

  /// 갱신할 때마다 값을 바꾸기 위한 번호. 회전을 흉내 낸다.
  int _rotation = 0;
```

`_sessionFor`가 발급을 기록하게 한다.

```dart
  AuthSession _sessionFor(String email) {
    final session = AuthSession(
      userId: 'fake-${email.hashCode.toRadixString(16)}',
      accessToken: 'fake-access-$email',
      refreshToken: 'fake-refresh-$email',
      isOnboarded: _onboarded.contains(email),
    );
    _issuedRefreshTokens.add(session.refreshToken);
    return session;
  }
```

`refresh`를 더한다.

```dart
  /// 발급했던 토큰만 받아준다.
  ///
  /// **새 값을 돌려주는 것이 중요하다.** 같은 값을 주면 "저장을 잊어도 동작하는"
  /// 가짜가 되어, 회전을 처리하지 않은 버그를 테스트가 놓친다.
  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    await Future<void>.delayed(latency);

    if (!_issuedRefreshTokens.contains(refreshToken)) {
      throw const AuthException(AuthFailure.sessionExpired);
    }
    _rotation++;
    final rotated = '$refreshToken-r$_rotation';
    // 옛 토큰은 무효가 된다. 서버가 회전 후 무효화한다면 이 동작이 같다.
    _issuedRefreshTokens
      ..remove(refreshToken)
      ..add(rotated);

    return AuthTokens(
      accessToken: 'fake-access-r$_rotation',
      refreshToken: rotated,
    );
  }
```

import를 추가한다: `package:runiverse/features/auth/domain/auth_tokens.dart`

- [ ] **Step 8: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/auth_controller_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

- [ ] **Step 9: 커밋**

```bash
git add lib/features/auth/ test/auth_controller_test.dart
git commit -m "📍 Feat: 리프레시 토큰으로 세션을 갱신한다"
```

---

## Task 5: `AuthState`를 세 갈래로 넓힌다

**Files:**
- Modify: `lib/features/auth/presentation/auth_state.dart`
- Modify: `lib/features/auth/presentation/auth_provider.dart` (컴파일이 깨진 자리)
- Modify: `lib/features/onboarding/presentation/splash_page.dart:86-87` (컴파일만 맞춘다. 분기는 Task 7)

**Interfaces:**
- Produces: `AuthSignedOut({required bool returning})` · `AuthSignedIn(String userId, bool isOnboarded)`

- [ ] **Step 1: `auth_state.dart`를 고친다**

`AuthSignedOut`과 `AuthSignedIn`을 바꾼다.

```dart
/// 로그인되어 있지 않다.
///
/// [returning]이 이 앱을 **처음 켠 사람**과 **로그인했다가 만료된 사람**을 가른다.
/// 이 구분이 없으면 만료된 사용자가 온보딩 소개를 처음부터 다시 보게 된다.
///
/// 별도 상태로 쪼개지 않고 필드로 둔 이유는 **이 값으로 갈리는 곳이 스플래시
/// 한 군데**여서다. `sealed`로 나눠 얻는 `switch` 망라성이 쓰일 자리가 없다.
final class AuthSignedOut extends AuthState {
  const AuthSignedOut({required this.returning});

  /// `true`면 로그인 화면으로, `false`면 온보딩 소개로.
  final bool returning;
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.userId, {required this.isOnboarded});

  final String userId;

  /// 프로필 등록(S04)을 마쳤는가. `false`면 홈이 아니라 프로필로 보낸다.
  final bool isOnboarded;
}
```

- [ ] **Step 2: 컴파일이 깨진 자리를 찾는다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: `auth_provider.dart`와 `splash_page.dart`에서 오류. 각각 고친다.

- [ ] **Step 3: `auth_provider.dart`를 맞춘다**

`restore()` (Task 6에서 다시 쓴다. 지금은 컴파일만 맞춘다):

```dart
  Future<void> restore() async {
    final stored = await _store.read();
    state = stored.userId == null
        ? const AuthSignedOut(returning: false)
        : AuthSignedIn(stored.userId!, isOnboarded: stored.isOnboarded);
  }
```

`signOut()`:

```dart
    await _store.clear();
    // 로그아웃한 사람은 처음 온 사람이 아니다. 소개를 다시 보여주지 않는다.
    state = const AuthSignedOut(returning: true);
```

`_authenticate()`:

```dart
      state = AuthSignedIn(session.userId, isOnboarded: session.isOnboarded);
```

- [ ] **Step 4: `splash_page.dart`를 임시로 맞춘다**

86~87행은 그대로 둬도 컴파일된다(`is AuthSignedIn` 검사뿐). analyze가 통과하면 손대지 않는다. Task 7에서 전면 교체한다.

- [ ] **Step 5: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test test/auth_controller_test.dart
```
기대: 경고 0개 · PASS

- [ ] **Step 6: 커밋**

```bash
git add lib/features/auth/presentation/
git commit -m "🤖 Refactor: 인증 상태가 첫 방문과 재방문을 구분한다"
```

---

## Task 6: `restore()` — 갈림길 로직

**Files:**
- Modify: `lib/features/auth/presentation/auth_provider.dart` (`restore()` 전면 재작성)
- Test: `test/auth_controller_test.dart`

**Interfaces:**
- Consumes: Task 4의 `AuthRepository.refresh` · Task 5의 상태
- Produces: `AuthController.restore()` — 실패하면 상태가 `AuthUnknown`에 머문다

**동작 규칙**

| 저장소 | 갱신 결과 | 상태 |
|---|---|---|
| refreshToken 있음 | 성공 | `AuthSignedIn(userId, isOnboarded)` · 새 토큰 저장 |
| refreshToken 있음 | `sessionExpired` | `AuthSignedOut(returning: true)` · `clearTokens()` |
| refreshToken 있음 | network · server | **`AuthUnknown` 유지** (2회 시도 후) |
| refreshToken 없음 · userId 있음 | — | `AuthSignedOut(returning: true)` |
| 아무것도 없음 | — | `AuthSignedOut(returning: false)` |

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`test/auth_controller_test.dart` 끝에 추가한다.

```dart
  test('저장된 것이 없으면 처음 온 사람으로 본다', () async {
    final container = makeContainer();

    await container.read(authControllerProvider.notifier).restore();

    final state = container.read(authControllerProvider);
    expect(state, isA<AuthSignedOut>());
    // false여야 스플래시가 온보딩 소개로 보낸다.
    expect((state as AuthSignedOut).returning, isFalse);
  });

  test('토큰이 살아 있으면 갱신해서 로그인 상태가 된다', () async {
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signIn(
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );
    final before = await container.read(tokenStoreProvider).read();

    await controller.restore();

    final state = container.read(authControllerProvider);
    expect(state, isA<AuthSignedIn>());
    expect((state as AuthSignedIn).isOnboarded, isTrue);

    // 회전된 토큰을 저장하지 않으면 다음 갱신이 죽는다.
    final after = await container.read(tokenStoreProvider).read();
    expect(after.refreshToken, isNot(before.refreshToken));
  });

  test('온보딩을 안 마쳤으면 그 사실이 상태에 남는다', () async {
    final container = makeContainer();
    final controller = container.read(authControllerProvider.notifier);

    await controller.signUp(email: 'new@example.com', password: 'runi123!');
    await controller.restore();

    final state = container.read(authControllerProvider);
    // 이 값이 false여야 스플래시가 프로필 등록으로 보낸다.
    expect((state as AuthSignedIn).isOnboarded, isFalse);
  });

  test('리프레시 토큰이 만료되면 토큰만 지우고 로그인 화면으로 보낸다', () async {
    final container = makeContainer();
    final store = container.read(tokenStoreProvider);

    // 서버가 모르는 토큰을 넣어 만료 상황을 만든다.
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'stale',
      refreshToken: 'stale',
      isOnboarded: true,
    );
    await container.read(authControllerProvider.notifier).restore();

    final state = container.read(authControllerProvider);
    expect(state, isA<AuthSignedOut>());
    // 처음 온 사람이 아니다. 온보딩 소개를 다시 보여주면 안 된다.
    expect((state as AuthSignedOut).returning, isTrue);

    final stored = await store.read();
    expect(stored.refreshToken, isNull);
    // userId를 지우면 다음 실행에 소개부터 다시 본다.
    expect(stored.userId, 'u-1');
  });

  test('토큰이 없고 userId만 있으면 로그인 화면으로 보낸다', () async {
    final container = makeContainer();
    final store = container.read(tokenStoreProvider);

    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a',
      refreshToken: 'r',
      isOnboarded: true,
    );
    await store.clearTokens();

    await container.read(authControllerProvider.notifier).restore();

    final state = container.read(authControllerProvider);
    expect((state as AuthSignedOut).returning, isTrue);
  });

  test('갱신이 네트워크 오류로 실패하면 아무 쪽으로도 보내지 않는다', () async {
    final container = ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        authRepositoryProvider.overrideWithValue(
          _OfflineAuthRepository(FakeAuthRepository(latency: Duration.zero)),
        ),
      ],
    );
    await container
        .read(tokenStoreProvider)
        .saveSession(
          userId: 'u-1',
          accessToken: 'a',
          refreshToken: 'r',
          isOnboarded: true,
        );

    await container.read(authControllerProvider.notifier).restore();

    // 판정에 실패한 것과 판정에 성공한 것은 다른 상태다.
    // 저장된 값을 믿고 홈에 들여보내지 않는다 — 오프라인은 허용하지 않는다.
    expect(container.read(authControllerProvider), isA<AuthUnknown>());
  });
```

파일 맨 아래에 테스트용 저장소를 더한다.

```dart
/// 갱신만 네트워크 오류로 답하는 저장소. 나머지는 [inner]에 맡긴다.
class _OfflineAuthRepository implements AuthRepository {
  _OfflineAuthRepository(this.inner);

  final AuthRepository inner;

  @override
  Future<AuthTokens> refresh(String refreshToken) =>
      throw const AuthException(AuthFailure.network);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => inner.signIn(email: email, password: password);

  @override
  Future<AuthSession> signUp({
    required String email,
    required String password,
  }) => inner.signUp(email: email, password: password);

  @override
  Future<void> signOut() => inner.signOut();
}
```

import를 더한다.

```dart
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
```

- [ ] **Step 2: 실패를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/auth_controller_test.dart
```
기대: 갱신 관련 테스트가 FAIL. 지금 `restore()`는 저장소만 읽는다.

- [ ] **Step 3: `restore()`를 다시 쓴다**

`auth_provider.dart`의 `restore()`를 교체한다.

```dart
  /// 저장된 토큰으로 세션을 되살린다. 앱이 켜질 때 한 번, 재시도할 때 다시 부른다.
  ///
  /// ## 갈림길
  ///
  /// ```
  /// refreshToken 있음 → 갱신 → 성공 : 로그인 상태 (isOnboarded가 홈/프로필을 가른다)
  ///                            401  : 토큰만 지우고 로그인 화면
  ///                            그 밖 : 판정 불가 — AuthUnknown에 머문다
  /// refreshToken 없음 → userId 있으면 로그인 화면, 없으면 온보딩 소개
  /// ```
  ///
  /// **판정에 실패하면 상태를 바꾸지 않는다.** 저장된 값을 믿고 들여보내면
  /// "네트워크가 끊긴 것"과 "토큰이 살아 있는 것"을 같이 취급하게 된다.
  /// 화면은 상태가 [AuthUnknown]에 머무는 것을 보고 재시도를 띄운다.
  Future<void> restore() async {
    final stored = await _store.read();

    if (stored.refreshToken == null) {
      state = AuthSignedOut(returning: stored.userId != null);
      return;
    }

    final userId = stored.userId;
    if (userId == null) {
      // 토큰은 있는데 누구인지 모른다. 저장소가 어긋난 상태라 되살릴 수 없다.
      // 빈 문자열로 채우면 로그인된 것처럼 보이고 다음 API 호출부터 깨진다.
      await _store.clear();
      state = const AuthSignedOut(returning: false);
      return;
    }

    try {
      final tokens = await _refreshWithRetry(stored.refreshToken!);
      // ⚠️ 회전된 refreshToken을 반드시 덮어쓴다. 안 하면 다음 갱신이 401로 죽는다.
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      state = AuthSignedIn(userId, isOnboarded: stored.isOnboarded);
    } on AuthException catch (error) {
      if (error.failure == AuthFailure.sessionExpired) {
        // userId·isOnboarded는 남긴다. 이 사람은 처음 온 것이 아니다.
        await _store.clearTokens();
        state = const AuthSignedOut(returning: true);
        return;
      }
      // 네트워크·5xx — 판정에 실패했다. 상태를 바꾸지 않는다.
    }
  }

  /// 한 번 더 시도한다. 터널이나 엘리베이터처럼 **순간 끊김**을 흡수한다.
  ///
  /// 무한 재시도는 하지 않는다 — 비행기 모드인 기기에서는 배터리만 쓴다.
  /// 그 뒤로는 사용자가 화면에서 눌러 [restore]를 다시 부른다.
  Future<AuthTokens> _refreshWithRetry(String refreshToken) async {
    try {
      return await _repository.refresh(refreshToken);
    } on AuthException catch (error) {
      // 만료는 다시 시도해도 결과가 같다. 기다릴 이유가 없다.
      if (error.failure == AuthFailure.sessionExpired) rethrow;
      return _repository.refresh(refreshToken);
    }
  }
```

import를 더한다: `package:runiverse/features/auth/domain/auth_tokens.dart`

- [ ] **Step 4: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/auth_controller_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

⚠️ 기존 테스트 `'로그인한 뒤 복원하면 로그인 상태가 유지된다'`도 통과해야 한다. `FakeAuthRepository`가 발급한 토큰을 기억하므로 갱신이 성공한다.

- [ ] **Step 5: 커밋**

```bash
git add lib/features/auth/presentation/auth_provider.dart test/auth_controller_test.dart
git commit -m "📍 Feat: 앱을 켤 때 저장된 토큰으로 세션을 되살린다"
```

---

## Task 7: 스플래시 분기와 재시도 화면

**Files:**
- Modify: `lib/features/onboarding/presentation/splash_page.dart`
- Modify: `lib/core/strings/app_strings.dart`
- Test: `test/onboarding_flow_test.dart`

**Interfaces:**
- Consumes: Task 5의 상태 · Task 6의 `restore()`
- Produces: 없음 (화면)

- [ ] **Step 1: 문구를 더한다**

`app_strings.dart`의 온보딩 문구 근처에 추가한다.

```dart
  /// 스플래시에서 서버에 닿지 못했을 때.
  static const splashOffline = '연결할 수 없어요';
  static const splashOfflineHint = '인터넷 연결을 확인하고 다시 시도해주세요';
  static const splashRetry = '다시 시도';
```

- [ ] **Step 2: `splash_page.dart`의 이동 로직을 바꾼다**

클래스 문서의 `## 자동 로그인` 절과 마지막 경고 문단을 교체한다.

```dart
/// ## 자동 로그인
///
/// 화면이 떠 있는 1.6초 동안 저장된 토큰으로 세션을 되살린다.
/// 다 읽고 나서 갈림길을 정한다.
///
/// ```
/// 토큰이 살아 있다   → 온보딩을 마쳤으면 홈, 아니면 프로필 등록
/// 토큰이 만료됐다    → 로그인 (소개는 건너뛴다. 처음 온 사람이 아니다)
/// 저장된 것이 없다   → 온보딩 소개
/// 판정하지 못했다    → 이 화면에 머물며 재시도
/// ```
///
/// 읽기가 1.6초보다 오래 걸리거나 사용자가 먼저 화면을 누르면 그 순간 기다린다.
/// 확인하지 않은 채로 온보딩에 보내면 로그인한 사람이 다시 로그인하게 된다.
///
/// ## 오프라인은 허용하지 않는다
///
/// 서버에 닿지 못하면 앱에 들어가지 못한다. **판정에 실패한 것과 판정에 성공한 것은
/// 다른 상태다** — 저장된 값을 믿고 들여보내면 둘을 같이 취급하게 된다.
/// 상태가 [AuthUnknown]에 머무는 것이 곧 "아직 못 정했다"이므로 상태를 더 만들지 않는다.
```

상태 필드를 더한다.

```dart
  /// 판정에 실패했다. [_goNext]가 끝났는데도 상태가 정해지지 않은 경우다.
  bool _offline = false;
```

`_goNext()`를 바꾼다.

```dart
  Future<void> _goNext() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();

    await _restored;
    if (!mounted) return;

    switch (ref.read(authControllerProvider)) {
      case AuthSignedIn(:final isOnboarded):
        // 프로필을 채우다 앱을 껐던 사람은 홈이 아니라 그 자리로 돌아간다.
        context.go(isOnboarded ? AppRoutes.home : AppRoutes.profileSetup);
      case AuthSignedOut(:final returning):
        // 로그인했던 적이 있으면 소개를 건너뛴다.
        context.go(returning ? AppRoutes.signIn : AppRoutes.onboardingIntro);
      case AuthUnknown():
        // 서버에 닿지 못했다. 이 화면에 머문다.
        setState(() {
          _offline = true;
          _leaving = false;
        });
    }
  }

  /// 재시도. 화면을 떠나지 않고 [AuthController.restore]를 다시 부른다.
  Future<void> _retry() async {
    setState(() {
      _offline = false;
      _restored = ref.read(authControllerProvider.notifier).restore();
    });
    await _goNext();
  }
```

`_restored`를 `late final`에서 `late`로 바꾼다 — 재시도할 때 다시 대입한다.

```dart
  /// 토큰 확인이 끝났는지. 타이머와 탭 어느 쪽이 먼저 와도 이것을 기다린다.
  /// 재시도하면 새 Future로 갈아 끼운다.
  late Future<void> _restored;
```

- [ ] **Step 3: 재시도 UI를 그린다**

`build`의 `GestureDetector`에서 `onTap`을 오프라인일 때 막고, 워드마크 아래에 안내를 붙인다.

```dart
        onTap: _offline ? null : _goNext,
```

`Column`의 마지막 `Text` 뒤에 추가한다.

```dart
                    if (_offline) ...[
                      const SizedBox(height: AppSpacing.space6),
                      Text(
                        AppStrings.splashOffline,
                        style: AppTypography.body.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        AppStrings.splashOfflineHint,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      AppButton(
                        label: AppStrings.splashRetry,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.md,
                        expand: false,
                        onPressed: _retry,
                      ),
                    ],
```

import를 더한다: `package:runiverse/core/widgets/app_button.dart`

- [ ] **Step 4: 테스트를 더한다**

`test/onboarding_flow_test.dart`의 `pumpApp`을 저장소와 저장소 구현을 받도록 바꾼다.

**`repository`를 받는 것이 중요하다.** `FakeAuthRepository`는 자기가 발급한 리프레시 토큰만 갱신해 준다. 저장소를 채운 인스턴스와 앱이 쓰는 인스턴스가 다르면 **갱신이 만료로 답해서** 테스트가 엉뚱한 화면을 본다.

```dart
  Future<void> pumpApp(
    WidgetTester tester, {
    TokenStore? store,
    FakeAuthRepository? repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // SecureTokenStore는 플랫폼 채널을 부른다. 테스트에는 채널이 없다.
          tokenStoreProvider.overrideWithValue(store ?? InMemoryTokenStore()),
          authRepositoryProvider.overrideWithValue(
            repository ?? FakeAuthRepository(latency: Duration.zero),
          ),
        ],
        child: const RuniverseApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
```

import를 더한다.

```dart
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
```

파일 끝에 갈림길 테스트를 더한다.

```dart
  group('스플래시 갈림길', () {
    /// 이미 로그인해 둔 상태를 만든다.
    ///
    /// **저장소와 저장소 구현을 짝으로 돌려준다.** `FakeAuthRepository`는 자기가
    /// 발급한 토큰만 갱신해 주므로, 같은 인스턴스를 앱에 넣어야 한다.
    Future<(TokenStore, FakeAuthRepository)> signedIn({
      required bool isOnboarded,
    }) async {
      final store = InMemoryTokenStore();
      final repository = FakeAuthRepository(latency: Duration.zero);
      // 씨앗 계정은 온보딩을 마친 것으로, 새로 가입한 계정은 안 마친 것으로 시작한다.
      final session = isOnboarded
          ? await repository.signIn(
              email: FakeAuthRepository.seedEmail,
              password: FakeAuthRepository.seedPassword,
            )
          : await repository.signUp(
              email: 'new@example.com',
              password: 'runi123!',
            );
      await store.saveSession(
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        isOnboarded: session.isOnboarded,
      );
      return (store, repository);
    }

    testWidgets('토큰이 살아 있고 온보딩을 마쳤으면 홈으로 간다', (tester) async {
      final (store, repository) = await signedIn(isOnboarded: true);

      await pumpApp(tester, store: store, repository: repository);
      await tester.tap(find.byType(SplashPage));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('온보딩을 안 마쳤으면 프로필 등록으로 간다', (tester) async {
      final (store, repository) = await signedIn(isOnboarded: false);

      await pumpApp(tester, store: store, repository: repository);
      await tester.tap(find.byType(SplashPage));
      await tester.pumpAndSettle();

      // 프로필을 채우다 앱을 껐던 사람은 그 자리로 돌아간다.
      expect(find.byType(ProfileSetupPage), findsOneWidget);
    });

    testWidgets('토큰이 만료됐으면 소개를 건너뛰고 로그인으로 간다', (tester) async {
      final store = InMemoryTokenStore();
      // 서버가 모르는 토큰이다. 갱신이 만료로 답한다.
      await store.saveSession(
        userId: 'u-1',
        accessToken: 'stale',
        refreshToken: 'stale',
        isOnboarded: true,
      );

      await pumpApp(tester, store: store);
      await tester.tap(find.byType(SplashPage));
      await tester.pumpAndSettle();

      // 이 사람은 처음 온 것이 아니다. 소개를 다시 보여주지 않는다.
      expect(find.byType(SignInPage), findsOneWidget);
      expect(find.byType(OnboardingIntroPage), findsNothing);
    });
  });
```

- [ ] **Step 5: 통과를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/onboarding_flow_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```
기대: PASS · 경고 0개

- [ ] **Step 6: 커밋**

```bash
git add lib/features/onboarding/presentation/splash_page.dart lib/core/strings/app_strings.dart test/onboarding_flow_test.dart
git commit -m "📍 Feat: 스플래시가 저장된 세션에 따라 갈라진다"
```

---

## Task 8: 남은 테스트를 고치고 전체를 통과시킨다

**Files:** 없음 — 테스트 override는 **Task 2에서 이미 처리했다.**

`home_page_test.dart`와 `widget_test.dart`는 `initialLocation`으로 스플래시를 건너뛰고 인증을 수행하지 않는다. Riverpod provider는 lazy라 `tokenStoreProvider`가 아예 만들어지지 않으므로 손댈 것이 없다.

- [ ] **Step 1: 전체를 돌려 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test
```
기대: 전부 통과

- [ ] **Step 2: (Task 2에서 완료)**

- [ ] **Step 3: 전체 통과와 경고 0개를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\dart.exe" format lib test
```
기대: 전체 PASS · 경고 0개

- [ ] **Step 4: 빌드가 되는지 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug
```

**`test`와 `analyze`가 통과해도 여기서 죽을 수 있다.** 네이티브 의존성(패키지가 요구하는
`compileSdk`·`minSdk`)은 Gradle이 병합할 때만 검사되기 때문이다. 서버 없이 확인 가능한
유일한 네이티브 검증이라 반드시 돌린다.

- [ ] **Step 5: 에뮬레이터에서 눈으로 확인한다**

자동 테스트는 `InMemoryTokenStore`를 쓰므로 **`SecureTokenStore`가 실제로 도는지는 여기서만 알 수 있다.**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" run --dart-define=API_BASE_URL=<서버 주소>
```

| 확인할 것 | 기대 |
|---|---|
| 로그인 → 앱 완전 종료 → 재실행 | 스플래시에서 **홈으로 바로** |
| 위 상태에서 다시 종료 → 재실행 | 또 홈으로 (회전된 토큰이 저장됐다는 증거) |
| 기내 모드로 바꾸고 재실행 | "연결할 수 없어요" + [다시 시도] |
| 기내 모드 해제 후 [다시 시도] | 홈으로 |
| 앱 데이터 삭제 후 재실행 | 온보딩 소개 |

⚠️ **두 번째 항목이 회전 처리의 유일한 검증이다.** 한 번만 확인하면 덮어쓰기를 빠뜨려도 통과한다.

- [ ] **Step 5: 커밋**

```bash
git add test/
git commit -m "✅ Test: 위젯 테스트가 메모리 저장소를 쓰게 한다"
```

- [ ] **Step 6: PR을 연다**

```bash
git push -u origin feat/auto-sign-in
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend --base dev --title "📍 Feat: 앱을 다시 켜도 로그인이 유지된다"
```

**base가 `dev`인지 확인한다.** GitHub는 `main`으로 잡아둔다.

PR 본문은 `.github/pull_request_template.md`의 6개 절을 채운다. 💬 리뷰 포인트에 아래를 적는다.

- **이 PR만 머지되면 모두가 프로필 등록 화면으로 간다.** 서버 `isOnboarded`가 계속 false이기 때문이다. PR 2(`feat/onboarding-submit`)가 닫는다
- `AuthSignedOut(returning:)`을 별도 상태로 쪼개지 않고 필드로 둔 판단
- 스플래시 오프라인 문구 3개는 디자인 확인이 필요하다

---

## 완료 조건

- [ ] `& ".fvm\flutter_sdk\bin\flutter.bat" test` 전체 통과
- [ ] `& ".fvm\flutter_sdk\bin\flutter.bat" analyze` 경고 0개
- [ ] Task 8 Step 4의 에뮬레이터 확인 5개 항목 통과
- [ ] PR이 `dev`를 base로 열려 있음

---

## 이 PR이 하지 않는 것

| | 어디서 |
|---|---|
| 프로필을 서버로 보내기 | PR 2 `feat/onboarding-submit` |
| 닉네임 정규식 검증 | PR 2 |
| `signOut`이 `POST /auth/logout`을 부르기 | 로그아웃 UI가 생길 때 |
| iOS 재설치 시 Keychain 비우기 | iOS 전환 시 |
| 인증 헤더 인터셉터 | 인증이 필요한 요청이 둘 이상 될 때 |
