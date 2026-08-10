# 카카오 로그인 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 로그인 화면의 "카카오로 계속하기"를 실제로 동작하게 만든다. 지금은 "아직 준비 중이에요"만 뜬다.

**Architecture:** 앱은 **인가 코드만 받아 서버에 넘긴다.** 카카오 토큰을 앱이 만지지 않는다 — 토큰 교환도, 프로필 조회도 서버가 한다. 앱이 하는 일은 두 가지뿐이다. ① 카카오 SDK로 인가 코드와 `codeVerifier`를 얻고 ② 그 둘을 서버에 보낸다.

**Tech Stack:** Flutter 3.44.8 (fvm) · Riverpod 3 · go_router 17 · dio · **kakao_flutter_sdk 2.0.0+1** (신규)

**브랜치:** `feat/kakao-login` (upstream/dev 기준, PR #19 머지 후)

---

## Global Constraints

- **모든 flutter/dart 명령은 fvm SDK로 부른다.** `fvm`이 PATH에 없다:
  `& ".fvm\flutter_sdk\bin\flutter.bat" test` · `& ".fvm\flutter_sdk\bin\dart.bat" format lib test`
- 내부 import는 항상 절대경로 `package:runiverse/...`
- 색·치수·문자열은 토큰으로만
- 아이콘은 **Lucide만**
- 커밋 메시지는 `<이모지> <Type>: <설명>`
- **AI를 공동 작성자로 넣지 않는다.**
- 각 태스크 끝에 `analyze` 경고 0개 · 커밋 시점마다 빌드
- ⚠️ **키·시크릿을 소스나 문서에 적지 않는다.** 앱 키는 `--dart-define`으로만 주입한다

---

## 서버 계약 (dev 브랜치 확인)

```
POST /api/v1/auth/oauth/{provider}
{"authorizationCode": "...", "codeVerifier": "..."}
→ 200 {userId, accessToken, refreshToken, isOnboarded}
```

`{provider}`는 `kakao`(대소문자 무관, 서버가 `toUpperCase`). 지원: `KAKAO` · `GOOGLE`.

**서버가 하는 일** (`KakaoOauthClient`)

1. `code` + `code_verifier` + `client_id`(REST API 키) + `redirect_uri`로 카카오와 토큰 교환
2. 카카오 액세스 토큰으로 사용자 정보 조회
3. `(provider, providerId)`로 기존 유저 조회 → 없으면 **가입**
4. 자체 JWT 발급

### 에러 코드

| code | HTTP | 언제 | `AuthFailure` |
|---|---|---|---|
| `UNSUPPORTED_PROVIDER` | 400 | 서버가 그 provider를 모른다 | `unknown` |
| `OAUTH_CODE_EXCHANGE_FAILED` | 400 | 카카오와의 통신·교환 실패 | `oauthFailed` |
| `OAUTH_EMAIL_NOT_PROVIDED` | 403 | 카카오가 이메일을 안 줬다 | `oauthEmailMissing` |
| `EMAIL_ALREADY_EXISTS` | 409 | **같은 이메일의 로컬 계정이 있다** | `emailAlreadyExists` (이미 있음) |

---

## 반드시 먼저 알아야 할 것 다섯

### ① 앱은 카카오 토큰을 받지 않는다

`kakao_flutter_sdk`의 흔한 예제는 `UserApi.instance.loginWithKakaoTalk()`인데, 그것은 **액세스 토큰을 앱이 받는다.** 이 서버와 맞지 않는다.

**써야 하는 것은 `AuthCodeClient`다.**

```dart
Future<String> authorize({required String redirectUri, ..., String? codeVerifier})
// → 인가 코드 문자열
```

`authorize()`는 카카오톡 앱이 있으면 앱으로, 없으면 웹으로 알아서 분기한다.

### ② `redirect_uri` 세 곳이 문자 하나까지 같아야 한다

| 어디 | 값 |
|---|---|
| 서버 `oauth.kakao.redirect-uri` | `kakao{네이티브앱키}://oauth` |
| 앱 `authorize(redirectUri:)` | **`KakaoSdk.redirectUri`를 그대로 쓴다** |
| 카카오 콘솔 Redirect URI | **등록하지 않아도 된다** (아래) |

**콘솔에는 등록하지 않는다.** 네이티브 앱은 커스텀 URL 스킴을 쓰므로, 플랫폼(Android/iOS)만
등록하면 SDK가 처리한다. 콘솔의 Redirect URI 목록은 웹(REST API) 용이다.

**그래도 서버 설정은 필요하다.** 인가 요청에 `redirect_uri`가 실제로 실리기 때문이다 —
`auth_platform_native.dart`의 `_createAuthorizeUrl`에서 확인했다.

```dart
Constants.clientId: KakaoSdk.appKey,        // 네이티브 앱 키
Constants.redirectUri: redirectUri,          // kakao{앱키}://oauth
Constants.codeChallenge: pkce?.codeChallenge,
```

OAuth 2.0은 인가 요청에 `redirect_uri`가 있었으면 토큰 요청에도 **같은 값**을 요구하고,
서버 `KakaoOauthClient`가 그것을 보낸다. 두 값이 다르면 카카오가 거부한다.

⚠️ **확인되지 않은 것 하나** — 인가는 **네이티브 앱 키**로 시작하는데 서버는
**REST API 키**로 토큰을 교환한다. 카카오가 같은 앱의 다른 키를 받아주는지는 코드로 알 수
없다. 거부하면 서버 `client_id`를 네이티브 앱 키로 바꿔야 한다. **Task 7에서 드러난다.**

하나라도 다르면 **서버의 토큰 교환이 카카오에 거부당하고** `OAUTH_CODE_EXCHANGE_FAILED`가 온다. 증상이 앱이 아니라 서버에서 나므로 원인을 찾기 어렵다.

⚠️ 현재 서버 설정은 `http://localhost:5173`(웹 개발용)이다. **앱은 이 주소로 돌아올 수 없다.** 백엔드가 바꿔야 한다.

> **실행 중 확인:** 앱에서는 **다른 값을 쓸 방법이 아예 없다.**
> `auth_platform_native.dart`가 `redirectUri != KakaoSdk.redirectUri`면
> `ClientErrorCause.notSupported`로 거절한다. 그래서 앱은 `AppConfig`에서
> 주소를 조립하지 않고 `KakaoSdk.redirectUri`를 그대로 쓴다 — 오타가 생길 자리가 없다.

### ③ 카카오 SDK를 테스트에서 부를 수 없다

플랫폼 채널을 쓰므로 `flutter test`에서 죽는다. 그래서 **인가 코드를 얻는 일을 인터페이스 뒤에 둔다** — `OauthCodeSource`. 테스트는 가짜를 끼운다.

`AuthRepository`에 넣지 않는 이유는 그것이 **서버를 부르는 저장소**이기 때문이다. 카카오 SDK 호출은 서버와 무관한 별개 관심사다.

### ④ 사용자가 취소하는 것은 실패가 아니다

카카오 화면에서 뒤로 가면 SDK가 예외를 던진다. 이때 **빨간 문구를 띄우면 안 된다** — 사용자는 스스로 그만둔 것이다. `AuthFailure.oauthCancelled`를 두고 화면이 그 경우에만 아무 말도 하지 않는다.

### ⑤ 이메일 동의를 못 받으면 로그인이 항상 실패한다

서버 `toProfile`이 이메일이 없으면 `OauthEmailNotProvidedException`을 던진다. **카카오는 이메일 수집에 비즈니스 앱 전환을 요구한다.** 콘솔에서 동의항목이 켜져 있는지 먼저 확인해야 한다 — 안 켜져 있으면 앱이 아무리 맞아도 403이다.

---

## File Structure

```
신규  features/auth/domain/oauth_provider.dart          provider enum
      features/auth/domain/oauth_authorization.dart     인가 결과(code + verifier)
      features/auth/domain/oauth_code_source.dart       인가 코드를 얻는 인터페이스
      features/auth/domain/code_verifier.dart           PKCE 검증값 생성
      features/auth/data/kakao_code_source.dart         카카오 SDK 구현
      features/auth/data/fake_code_source.dart          테스트용
      test/code_verifier_test.dart
      test/kakao_login_test.dart

수정  pubspec.yaml                                      kakao_flutter_sdk
      android/app/src/main/AndroidManifest.xml          리다이렉트 스킴
      lib/main.dart                                     KakaoSdk.init
      core/config/app_config.dart                       네이티브 앱 키
      features/auth/domain/auth_repository.dart         signInWithOauth
      features/auth/data/http_auth_repository.dart      엔드포인트 + 코드 매핑
      features/auth/data/fake_auth_repository.dart      흉내
      features/auth/domain/auth_failure.dart            사유 3개
      features/auth/presentation/auth_provider.dart     컨트롤러 + provider
      features/auth/presentation/sign_in_page.dart      버튼 연결
      core/strings/app_strings.dart                     문구 3개
      docs/implementation-notes.md                      함정
```

**19파일.** 대부분 작은 파일이라 **PR 하나**로 간다. 500줄을 넘으면 화면 연결을 두 번째 PR로 뺀다.

---

## Task 1: 패키지와 안드로이드 설정

**Files:**
- Modify: `pubspec.yaml` · `android/app/src/main/AndroidManifest.xml` · `lib/main.dart` · `lib/core/config/app_config.dart`

**이 태스크에는 테스트가 없다.** 설정뿐이고, 확인은 `build apk`가 한다.

- [ ] **Step 1: 패키지를 더한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" pub add kakao_flutter_sdk
```

`pubspec.yaml`에 사유를 적는다.

```yaml
  # 인가 코드만 받는 데 쓴다. UserApi로 토큰을 직접 받지 않는다 —
  # 토큰 교환과 프로필 조회는 서버가 한다(계획 문서 ①).
  kakao_flutter_sdk: ^2.0.0
```

- [ ] **Step 2: 앱 키를 주입받을 자리를 만든다**

`app_config.dart`에 더한다. **기본값을 두지 않는다** — 기존 `apiBaseUrl`과 같은 이유다.

```dart
  /// 카카오 네이티브 앱 키.
  ///
  /// 앱 바이너리에 박히는 공개 값이라 시크릿은 아니지만, 주소와 같은 이유로
  /// 소스에 적지 않는다 — 앱이 바뀌면 커밋이 하나씩 생긴다.
  ///
  /// ⚠️ **REST API 키와 다른 값이다.** REST API 키는 서버가 토큰 교환에 쓴다.
  static const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

  static bool get hasKakaoNativeAppKey => kakaoNativeAppKey.isNotEmpty;

  /// 카카오가 인가를 마치고 돌아올 주소.
  ///
  /// ⚠️ **서버 `oauth.kakao.redirect-uri`와 정확히 같아야 한다.** 다르면
  /// 서버의 토큰 교환이 카카오에 거부당한다(계획 문서 ②).
  static String get kakaoRedirectUri => 'kakao$kakaoNativeAppKey://oauth';
```

- [ ] **Step 3: 안드로이드 매니페스트**

`<application>` 안에 넣는다.

```xml
        <!-- 카카오 인가가 끝나면 이 액티비티로 돌아온다.
             scheme의 앱 키는 빌드 때 주입하는 값과 같아야 한다. -->
        <activity
            android:name="com.kakao.sdk.flutter.AuthCodeCustomTabsActivity"
            android:exported="true">
            <intent-filter android:label="flutter_web_auth">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="kakao${KAKAO_NATIVE_APP_KEY}" android:host="oauth" />
            </intent-filter>
        </activity>
```

⚠️ **매니페스트는 `--dart-define`을 읽지 못한다.** Gradle의 `manifestPlaceholders`로 넘겨야 한다.
`android/app/build.gradle.kts`의 `defaultConfig`에 더한다.

```kotlin
        // 매니페스트의 ${KAKAO_NATIVE_APP_KEY}를 채운다.
        // dart-define은 Dart 코드만 보므로 여기서 따로 넘긴다.
        manifestPlaceholders["KAKAO_NATIVE_APP_KEY"] =
            (project.findProperty("KAKAO_NATIVE_APP_KEY") as String?) ?: ""
```

빌드할 때 `-PKAKAO_NATIVE_APP_KEY=...`로 넘긴다.

> **실행 중 정정 셋** — 계획을 세울 때 문서만 보고 쓴 것이 실제와 달랐다.
> **설치된 패키지가 정본이다.**
>
> 1. 클래스명은 `com.kakao.sdk.flutter.auth.AuthCodeHandlerActivity`다
>    (`AuthCodeCustomTabsActivity`가 아니다).
> 2. **액티비티 선언은 SDK가 이미 갖고 있다** (`kakao_flutter_sdk_auth`의
>    `AndroidManifest.xml`). 우리가 더하는 것은 `intent-filter`뿐이고,
>    매니페스트 병합이 같은 액티비티에 붙여준다.
> 3. **`<queries>`(카카오톡 패키지 탐지)도 SDK에 있다.** 따로 넣지 않는다.
>
> 병합 결과는 `build/app/intermediates/merged_manifest/.../AndroidManifest.xml`에서 확인한다.

⚠️ **XML 주석 안에 붙임표 둘(`--`)을 쓰지 않는다.** 파서가 주석의 끝으로 읽어
`ManifestMerger2$MergeFailureException`이 난다. `--dart-define`을 주석에 적다가 실제로 겪었다.

- [ ] **Step 4: SDK를 초기화한다**

`main.dart`의 `runApp` 앞.

```dart
  // 키가 없으면 초기화하지 않는다. 빈 키로 초기화하면 카카오 버튼을 눌렀을 때
  // 원인을 알기 어려운 오류가 난다 — 없는 것이 낫다.
  if (AppConfig.hasKakaoNativeAppKey) {
    KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
  }
```

- [ ] **Step 5: 빌드를 확인한다**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug
```
기대: 경고 0개 · 빌드 성공

⚠️ 네이티브 의존이 늘었다. **`analyze`와 `test`는 이것을 못 잡는다** — Gradle 병합에서만 드러난다
(`implementation-notes.md`에 `flutter_secure_storage` 11.x 사례가 있다).

- [ ] **Step 6: 커밋**

```bash
git add pubspec.yaml pubspec.lock android/ lib/main.dart lib/core/config/app_config.dart
git commit -m "🚚 Chore: 카카오 SDK를 붙이고 앱 키를 주입받는다"
```

---

## Task 2: PKCE 검증값

**Files:**
- Create: `lib/features/auth/domain/code_verifier.dart` · `test/code_verifier_test.dart`

**Interfaces:**
- Produces: `CodeVerifier.generate() → String`

PKCE는 앱이 만든 **비밀값(`code_verifier`)** 과 그 해시(`code_challenge`)를 짝지어, 인가 코드를 가로챈 쪽이 토큰으로 바꾸지 못하게 막는다. **해시 계산은 카카오 SDK가 한다** — 앱은 검증값만 만들면 되고, 그래서 `crypto` 패키지가 필요 없다.

- [ ] **Step 1: 테스트를 쓴다**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/code_verifier.dart';

/// PKCE 검증값 — 순수 계산 로직.
void main() {
  test('RFC 7636이 정한 길이 안에 든다', () {
    // 43자 미만이면 추측 가능해지고, 128자를 넘으면 서버가 거절한다.
    final value = CodeVerifier.generate();
    expect(value.length, greaterThanOrEqualTo(43));
    expect(value.length, lessThanOrEqualTo(128));
  });

  test('허용된 문자만 쓴다', () {
    // unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
    // 다른 문자가 섞이면 URL 인코딩 단계에서 값이 달라진다.
    expect(CodeVerifier.generate(), matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
  });

  test('부를 때마다 다른 값이 나온다', () {
    // 같은 값이 반복되면 PKCE가 막으려던 것을 막지 못한다.
    final values = List.generate(50, (_) => CodeVerifier.generate());
    expect(values.toSet(), hasLength(50));
  });
}
```

- [ ] **Step 2: 구현한다**

```dart
import 'dart:math';

/// PKCE의 `code_verifier`를 만든다 (RFC 7636).
///
/// ## 왜 필요한가
///
/// 앱이 비밀값을 만들어 두고, 인가를 시작할 때는 그 **해시**만 카카오에 보낸다.
/// 나중에 토큰을 받을 때 원본 비밀값을 함께 내야 하므로, 인가 코드만 가로챈
/// 쪽은 토큰으로 바꾸지 못한다.
///
/// **해시(`code_challenge`) 계산은 카카오 SDK가 한다.** 앱은 검증값만 만든다 —
/// 그래서 해시 패키지가 필요 없다.
///
/// ⚠️ **이 값을 서버에도 보낸다.** 서버가 카카오와 토큰을 교환할 때 쓴다.
abstract final class CodeVerifier {
  /// RFC 7636이 정한 범위는 43~128자다. 넉넉한 쪽을 쓴다.
  static const length = 64;

  static const _allowed =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// **`Random.secure()`를 쓴다.** 기본 `Random()`은 예측 가능해서
  /// PKCE가 막으려던 것을 막지 못한다.
  static final _random = Random.secure();

  static String generate() => String.fromCharCodes(
    Iterable.generate(
      length,
      (_) => _allowed.codeUnitAt(_random.nextInt(_allowed.length)),
    ),
  );
}
```

- [ ] **Step 3: 통과 확인 → 커밋**

```powershell
& ".fvm\flutter_sdk\bin\flutter.bat" test test/code_verifier_test.dart
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
```

```bash
git add lib/features/auth/domain/code_verifier.dart test/code_verifier_test.dart
git commit -m "📍 Feat: PKCE 검증값을 만든다"
```

---

## Task 3: 인가 코드를 얻는 자리

**Files:**
- Create: `lib/features/auth/domain/oauth_provider.dart` · `oauth_authorization.dart` · `oauth_code_source.dart`
- Create: `lib/features/auth/data/kakao_code_source.dart` · `lib/features/auth/data/fake_code_source.dart`

**Interfaces:**
- Produces: `OauthCodeSource.authorize(OauthProvider) → OauthAuthorization`

- [ ] **Step 1: 도메인 타입 셋**

```dart
// oauth_provider.dart
/// 어느 소셜로 로그인하는가.
///
/// 문자열을 화면에 흩뿌리지 않는다 — 서버 경로(`/auth/oauth/{provider}`)에
/// 그대로 들어가므로 오타가 나면 `UNSUPPORTED_PROVIDER`가 된다.
enum OauthProvider {
  kakao;

  /// 서버 경로에 쓰는 값. 서버가 대문자로 바꿔 읽으므로 소문자로 보낸다.
  String get path => name;
}
```

```dart
// oauth_authorization.dart
/// 인가를 마치고 얻은 것. **둘을 함께 서버에 보낸다.**
///
/// 따로 들고 다니면 짝이 어긋난 채로 보낼 수 있다 — 그러면 서버의 토큰 교환이
/// 카카오에 거부당하는데, 증상이 앱에서 보이지 않아 원인을 찾기 어렵다.
class OauthAuthorization {
  const OauthAuthorization({
    required this.authorizationCode,
    required this.codeVerifier,
  });

  final String authorizationCode;
  final String codeVerifier;
}
```

```dart
// oauth_code_source.dart
/// 소셜 인가 코드를 얻는 곳 — **인터페이스만 있다.**
///
/// ## 왜 `AuthRepository`에 넣지 않는가
///
/// 그것은 **서버를 부르는** 저장소다. 카카오 SDK 호출은 서버와 무관하고,
/// 플랫폼 채널을 쓰므로 `flutter test`에서 죽는다. 갈아끼울 자리가 필요하다.
abstract interface class OauthCodeSource {
  /// 사용자가 취소하면 `AuthException(AuthFailure.oauthCancelled)`.
  /// **취소는 실패가 아니다** — 화면이 빨간 문구를 띄우지 않게 하려고 나눠 둔다.
  Future<OauthAuthorization> authorize(OauthProvider provider);
}
```

- [ ] **Step 2: 카카오 구현**

```dart
class KakaoCodeSource implements OauthCodeSource {
  const KakaoCodeSource();

  @override
  Future<OauthAuthorization> authorize(OauthProvider provider) async {
    final verifier = CodeVerifier.generate();
    try {
      // 카카오톡 앱이 있으면 앱으로, 없으면 웹으로 SDK가 알아서 분기한다.
      final code = await AuthCodeClient.instance.authorize(
        redirectUri: AppConfig.kakaoRedirectUri,
        codeVerifier: verifier,
      );
      return OauthAuthorization(
        authorizationCode: code,
        codeVerifier: verifier,
      );
    } on PlatformException catch (error) {
      // 사용자가 뒤로 갔다. 실패로 취급하면 스스로 그만둔 사람에게 오류를 띄운다.
      if (error.code == 'CANCELED') {
        throw const AuthException(AuthFailure.oauthCancelled);
      }
      throw const AuthException(AuthFailure.oauthFailed);
    } on Exception {
      throw const AuthException(AuthFailure.oauthFailed);
    }
  }
}
```

⚠️ **취소를 알리는 예외 타입과 `code` 값을 실제로 확인한다.** SDK 버전에 따라
`KakaoAuthException`일 수도 있다. **에뮬레이터에서 실제로 뒤로 눌러보고 맞춘다** —
추측으로 두면 취소할 때마다 빨간 문구가 뜬다.

- [ ] **Step 3: 가짜 구현**

```dart
/// 테스트용. 카카오 SDK는 플랫폼 채널을 쓰므로 `flutter test`에서 부를 수 없다.
class FakeOauthCodeSource implements OauthCodeSource {
  FakeOauthCodeSource({this.failure});

  /// 이 값을 주면 그 이유로 실패한다. 취소·오류 경로를 시험할 때 쓴다.
  final AuthFailure? failure;

  var callCount = 0;

  @override
  Future<OauthAuthorization> authorize(OauthProvider provider) async {
    callCount++;
    final reason = failure;
    if (reason != null) throw AuthException(reason);
    return const OauthAuthorization(
      authorizationCode: 'fake-code',
      codeVerifier: 'fake-verifier',
    );
  }
}
```

- [ ] **Step 4: analyze → 커밋**

```bash
git commit -m "📍 Feat: 소셜 인가 코드를 얻는 자리를 만든다"
```

---

## Task 4: 실패 사유와 문구

**Files:**
- Modify: `lib/features/auth/domain/auth_failure.dart` · `lib/core/strings/app_strings.dart`

- [ ] **Step 1: 사유 셋을 더한다**

```dart
  /// 소셜: 사용자가 인가 화면에서 그만뒀다.
  ///
  /// ⚠️ **화면은 이 경우 아무 문구도 띄우지 않는다.** 스스로 그만둔 사람에게
  /// 오류를 보여주면 무언가 잘못된 것처럼 읽힌다.
  oauthCancelled,

  /// 소셜: 인가나 토큰 교환이 실패했다.
  /// 서버 `OAUTH_CODE_EXCHANGE_FAILED`, 또는 앱 쪽 SDK 오류.
  ///
  /// **`redirect_uri`가 서버와 어긋나면 여기로 온다.** 가장 흔한 원인이다.
  oauthFailed,

  /// 소셜: 카카오가 이메일을 주지 않았다. 서버 `OAUTH_EMAIL_NOT_PROVIDED` (403)
  ///
  /// 동의항목이 꺼져 있거나 사용자가 이메일 제공에 동의하지 않았다.
  /// 서버가 이메일로 계정을 만들기 때문에 없으면 가입할 수 없다.
  oauthEmailMissing,
```

- [ ] **Step 2: 문구 셋** (`oauthCancelled`는 문구가 없다)

```dart
  // ── 소셜 로그인 ──────────────────────────────────────────────

  static const authFailedOauth = '카카오 로그인을 마치지 못했어요. 다시 시도해주세요';

  /// 이메일 동의를 못 받았다. **무엇을 해야 하는지** 말한다.
  static const authFailedOauthEmail = '이메일 제공에 동의해야 로그인할 수 있어요';

  /// 같은 이메일의 계정이 이미 있다. 서버가 자동으로 연동하지 않는다 —
  /// 로그인하려는 사람이 그 계정의 주인인지 확인할 방법이 없기 때문이다.
  static const authFailedOauthEmailTaken = '이미 가입한 이메일이에요. 이메일로 로그인해주세요';
```

- [ ] **Step 3: 두 화면의 `switch`를 채운다**

`sign_in_page` · `sign_up_page` 둘 다 `AuthFailure`를 전부 나열한다. **analyze가 잡아준다.**
가입 화면에서는 소셜 사유가 올 일이 없으므로 `authFailedUnknown`에 묶는다.

- [ ] **Step 4: analyze → 커밋**

---

## Task 5: 저장소와 컨트롤러

**Files:**
- Modify: `auth_repository.dart` · `http_auth_repository.dart` · `fake_auth_repository.dart` · `auth_provider.dart`

- [ ] **Step 1: 인터페이스**

```dart
  /// 인가 코드로 로그인한다. **계정이 없으면 서버가 만든다** — 별도 가입 절차가 없다.
  ///
  /// 실패: `oauthFailed` · `oauthEmailMissing` · `emailAlreadyExists`
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  });
```

- [ ] **Step 2: HTTP 구현**

```dart
  static const _oauthPath = '/api/v1/auth/oauth';

  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_oauthPath/${provider.path}',
        data: {
          'authorizationCode': authorization.authorizationCode,
          'codeVerifier': authorization.codeVerifier,
        },
      );
      // 응답 필드가 로그인과 같다.
      return _sessionOf(response.data);
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }
```

`_failureOf`의 `known` 표에 둘을 더한다.

```dart
      'OAUTH_CODE_EXCHANGE_FAILED' => AuthFailure.oauthFailed,
      'OAUTH_EMAIL_NOT_PROVIDED' => AuthFailure.oauthEmailMissing,
```

- [ ] **Step 3: 가짜 구현**

```dart
  /// 소셜 계정 — 인가 코드 → 이메일. 서버의 `(provider, providerId)` 조회를 흉내 낸다.
  final Map<String, String> _oauthAccounts = {};

  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) async {
    await Future<void>.delayed(latency);

    final email = _oauthAccounts[authorization.authorizationCode] ??
        'kakao-${authorization.authorizationCode}@example.com';

    // 같은 이메일의 로컬 계정이 있으면 서버가 자동 연동하지 않는다.
    if (_accounts.containsKey(email)) {
      throw const AuthException(AuthFailure.emailAlreadyExists);
    }
    return _sessionFor(email);
  }

  /// 인가 코드가 어느 이메일에 대응하는지 심는다. **기다리지 않는다.**
  void seedOauthAccount({required String code, required String email}) {
    _oauthAccounts[code] = _normalize(email);
  }
```

- [ ] **Step 4: 컨트롤러**

`auth_provider.dart`에 provider와 메서드를 더한다.

```dart
/// 인가 코드를 어디서 얻는가. 테스트는 이것을 override한다.
final oauthCodeSourceProvider = Provider<OauthCodeSource>(
  (ref) => const KakaoCodeSource(),
);
```

```dart
  /// 성공하면 `null`.
  ///
  /// **두 단계를 여기서 잇는다** — ① 카카오에서 인가 코드를 받고 ② 서버에 넘긴다.
  /// 화면이 둘을 알 필요가 없고, 어느 쪽이 실패해도 이유 하나로 돌아온다.
  Future<AuthFailure?> signInWithOauth(OauthProvider provider) async {
    final OauthAuthorization authorization;
    try {
      authorization = await ref.read(oauthCodeSourceProvider).authorize(provider);
    } on AuthException catch (error) {
      // 취소도 여기로 온다. 서버를 부르지 않고 그대로 돌려준다.
      return error.failure;
    }

    return _authenticate(
      () => _repository.signInWithOauth(
        provider: provider,
        authorization: authorization,
      ),
    );
  }
```

- [ ] **Step 5: 테스트 → 커밋**

`test/kakao_login_test.dart`에 상태 전이를 쓴다.

| 무엇 | 기대 |
|---|---|
| 인가 성공 → 서버 성공 | `null` · `AuthSignedIn` · 토큰 저장 |
| 사용자가 취소 | `oauthCancelled` · **서버를 부르지 않는다** · 상태 그대로 |
| 인가 실패 | `oauthFailed` · 상태 그대로 |
| 이메일 겹침 | `emailAlreadyExists` |

**"서버를 부르지 않는다"를 반드시 확인한다** — `FakeOauthCodeSource.callCount`와
저장소 호출 여부로 본다. 취소인데 서버를 부르면 쓸모없는 요청이 나간다.

---

## Task 6: 화면 연결

**Files:**
- Modify: `lib/features/auth/presentation/sign_in_page.dart`
- Test: `test/sign_in_page_test.dart`

- [ ] **Step 1: 카카오 버튼을 잇는다**

지금은 `_notReady(context)`로 스낵바만 띄운다. 이것을 바꾼다.

```dart
                    AppButton(
                      label: AppStrings.authKakao,
                      variant: AppButtonVariant.secondary,
                      onPressed: _busy ? null : _signInWithKakao,
                    ),
```

**Apple 버튼은 그대로 둔다.** 서버 `Provider` enum에 `APPLE`이 없다.

```dart
  Future<void> _signInWithKakao() async {
    setState(() {
      _busy = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.kakao);

    if (!mounted) return;

    setState(() {
      _busy = false;
      // 취소는 화면에 남기지 않는다. 스스로 그만둔 사람에게 오류를 띄우지 않는다.
      _failure = failure == AuthFailure.oauthCancelled ? null : failure;
    });

    if (failure == null) {
      // 이메일 로그인과 같은 자리로 보낸다. isOnboarded를 보지 않는다 —
      // 프로필은 홈의 유도 카드에서 만난다(설계 문서 2-9).
      context.go(AppRoutes.home);
    }
  }
```

- [ ] **Step 2: 테스트**

```dart
  testWidgets('카카오로 로그인하면 홈으로 간다', ...);
  testWidgets('취소하면 아무 문구도 뜨지 않는다', ...);   // ⚠️ 핵심
  testWidgets('이메일이 겹치면 이메일로 로그인하라고 알린다', ...);
```

`pumpSignIn`에 `oauthCodeSourceProvider` override를 더한다.
⚠️ **`tokenStoreProvider`도 override한다** — 성공 경로에서만 멈추는 함정이 있다
(`implementation-notes.md` §9-7).

- [ ] **Step 3: 통과 확인 → 커밋**

---

## Task 7: 문서 · 검증 · PR

- [ ] **Step 1: `implementation-notes.md`에 §9-8을 더한다**

담을 것 — `redirect_uri` 세 곳 일치 · 취소는 실패가 아니다 · 앱이 토큰을 만지지 않는다 ·
이메일 동의가 없으면 항상 403 · 매니페스트 placeholder는 `dart-define`이 아니라 Gradle.

- [ ] **Step 2: 전체를 돌린다**

```powershell
& ".fvm\flutter_sdk\bin\dart.bat" format lib test
& ".fvm\flutter_sdk\bin\flutter.bat" analyze
& ".fvm\flutter_sdk\bin\flutter.bat" test
& ".fvm\flutter_sdk\bin\flutter.bat" build apk --debug -PKAKAO_NATIVE_APP_KEY=<주입>
```

⚠️ `format`이 이번에 손대지 않은 파일을 바꾸면 되돌린다. `dio_client.dart`가 매번 걸린다.

- [ ] **Step 3: 에뮬레이터에서 확인한다**

**세 축이 모두 준비돼야 한다** — 콘솔 설정 · 서버 `redirect-uri` · 앱 키.

| # | 조작 | 기대 |
|---|---|---|
| 1 | [카카오로 계속하기] | 카카오 인가 화면이 열린다 |
| 2 | 인가 화면에서 **뒤로** | 로그인 화면 · **아무 문구도 없다** |
| 3 | 동의하고 계속 | **홈** |
| 4 | 앱을 껐다 켜기 | 자동 로그인으로 홈 |
| 5 | 이미 이메일로 가입한 주소의 카카오 계정 | "이미 가입한 이메일이에요…" |

**2번이 핵심이다.** 취소를 오류로 표시하지 않는지 본다.

⚠️ 에뮬레이터에는 카카오톡 앱이 없다. **웹 로그인 경로만 확인된다** —
카카오톡 앱 분기는 실기기에서 봐야 한다.

- [ ] **Step 4: PR을 연다**

```bash
git push -u origin feat/kakao-login
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend --base dev \
  --title "📍 Feat: 카카오로 로그인한다"
```

💬 리뷰 포인트에 적는다.

- **앱이 카카오 토큰을 만지지 않는다** — 인가 코드만 받아 서버에 넘긴다. 흔한 예제(`loginWithKakaoTalk`)와 다른 이유
- **취소를 실패로 표시하지 않는다** — 사유는 나누되 화면은 침묵한다
- **`OauthCodeSource`를 `AuthRepository`와 나눴다** — 하나는 SDK, 하나는 서버다
- **`redirect_uri`가 세 곳에 있다** — 콘솔·서버·앱. 어긋나면 서버에서 증상이 난다
- Apple 버튼은 그대로 뒀다 — 서버 `Provider`에 `APPLE`이 없다
- 문구 3개는 디자인 확인이 필요하다

---

## 완료 조건

- [ ] `flutter test` 전체 통과 · `analyze` 경고 0개
- [ ] `build apk --debug` 성공
- [ ] Task 7 Step 3의 확인 5개 (특히 2번)
- [ ] PR base가 `dev`

---

## 이 계획이 하지 않는 것

| | 왜 |
|---|---|
| Apple 로그인 | 서버 `Provider` enum에 없다 |
| 구글 로그인 | 서버는 되지만 화면 정본에 버튼이 없다 |
| 카카오 계정과 이메일 계정 연동 | 서버가 자동 연동을 거부한다(`EMAIL_ALREADY_EXISTS`). 별도 기능 |
| 카카오 로그아웃·연결 끊기 | 앱이 카카오 토큰을 갖지 않으므로 서버 몫이다 |
| iOS 설정 | 안드로이드 우선 |

---

## 외부에서 준비돼야 하는 것

**이것들이 없으면 코드가 맞아도 로그인은 실패한다.**

| 누구 | 무엇 | 확인 방법 |
|---|---|---|
| 콘솔 | 네이티브 앱 키 | 앱 키 화면 (REST API 키와 다르다) |
| 콘솔 | Android 플랫폼 등록 | 패키지 `com.swmaestro.runiverse` + 키 해시 |
| 콘솔 | 카카오 로그인 활성화 | 기본이 꺼져 있다 |
| 콘솔 | **동의항목 `이메일` ON** | ⚠️ 비즈니스 앱 전환이 필요할 수 있다 |
| 서버 | `oauth.kakao.redirect-uri` | 지금 `http://localhost:5173`이라 앱이 못 받는다 |
| 서버 | Client Secret | 노출됐으므로 재발급 |
