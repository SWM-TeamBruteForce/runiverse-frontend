import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:runiverse/features/auth/domain/sign_in_method.dart';

/// 로그인 화면이 기억해 두는 것 — **저장한 아이디**와 **마지막에 성공한 방법**.
///
/// ## 로그아웃해도 남는다
///
/// 토큰과 달리 이 값들은 "다음에 다시 로그인할 때 편하라고" 두는 것이다.
/// 로그아웃할 때 지우면 그 편의가 사라진다. 아이디를 지우고 싶으면 화면에서
/// **아이디 저장을 끄면** 된다 — 그것이 유일한 삭제 경로다.
abstract interface class SignInMemoryStore {
  /// 저장해 둔 이메일. 아이디 저장이 꺼져 있으면 `null`.
  Future<String?> savedEmail();

  /// [email]이 `null`이면 지운다 — 아이디 저장을 껐다는 뜻이다.
  Future<void> rememberEmail(String? email);

  /// 마지막으로 **성공한** 로그인 방법.
  Future<SignInMethod?> lastMethod();

  Future<void> rememberMethod(SignInMethod method);
}

/// 기기에 남기는 구현.
///
/// 이메일은 시크릿이 아니지만 개인정보다. 값 두 개 때문에 `shared_preferences`를
/// 새로 들이지 않고 이미 있는 저장소를 쓴다 — `SecureConsentStore`와 같은 판단이다.
///
/// ⚠️ `auth.*`와 접두사를 나눈다. 로그아웃이 `auth.*`만 지우므로 이 값들은 남는다.
class SecureSignInMemoryStore implements SignInMemoryStore {
  SecureSignInMemoryStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyEmail = 'signIn.savedEmail';
  static const _keyMethod = 'signIn.lastMethod';

  @override
  Future<String?> savedEmail() async {
    final value = await _storage.read(key: _keyEmail);
    // 빈 문자열은 없는 것으로 본다. 저장할 때 걸러도 예전 값이 남아 있을 수 있다.
    return (value == null || value.isEmpty) ? null : value;
  }

  @override
  Future<void> rememberEmail(String? email) async {
    if (email == null || email.isEmpty) {
      await _storage.delete(key: _keyEmail);
      return;
    }
    await _storage.write(key: _keyEmail, value: email);
  }

  @override
  Future<SignInMethod?> lastMethod() async =>
      SignInMethod.fromStorage(await _storage.read(key: _keyMethod));

  @override
  Future<void> rememberMethod(SignInMethod method) =>
      _storage.write(key: _keyMethod, value: method.storageKey);
}

/// 메모리에만 들고 있는 구현. 테스트가 쓴다 —
/// 위젯 테스트는 플랫폼 채널을 부를 수 없다.
class InMemorySignInMemoryStore implements SignInMemoryStore {
  String? _email;
  SignInMethod? _method;

  @override
  Future<String?> savedEmail() async => _email;

  @override
  Future<void> rememberEmail(String? email) async =>
      _email = (email == null || email.isEmpty) ? null : email;

  @override
  Future<SignInMethod?> lastMethod() async => _method;

  @override
  Future<void> rememberMethod(SignInMethod method) async => _method = method;
}
