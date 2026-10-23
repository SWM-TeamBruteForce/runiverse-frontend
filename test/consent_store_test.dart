import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/secure_token_store.dart';

/// 약관 동의 기록 — **로그아웃해도 남는가.**
///
/// 이 파일이 지키는 규칙은 하나다. `TokenStore.clear()`가 동의 기록을 지우면
/// 로그아웃한 사람에게 약관을 다시 묻게 된다. 같은 사람에게 같은 것을 두 번 묻는 셈이다.
///
/// 그래서 [InMemoryConsentStore]로는 부족하다 — 객체가 달라 애초에 섞이지 않는다.
/// **위험은 둘이 같은 secure storage를 쓴다는 데 있으므로** 그 저장소를 흉내 내
/// [SecureConsentStore]와 [SecureTokenStore]를 나란히 태운다.
void main() {
  group('InMemoryConsentStore', () {
    test('기록 전에는 동의한 적이 없다', () async {
      expect(await InMemoryConsentStore().hasAgreedTerms(), isFalse);
    });

    test('기록하면 동의한 것으로 읽힌다', () async {
      final store = InMemoryConsentStore();

      await store.markTermsAgreed();

      expect(await store.hasAgreedTerms(), isTrue);
    });
  });

  group('같은 저장소를 나눠 쓴다', () {
    test('로그아웃해도 동의 기록은 남는다', () async {
      final storage = _FakeSecureStorage();
      final consent = SecureConsentStore(storage: storage);
      final tokens = SecureTokenStore(storage: storage);
      await consent.markTermsAgreed();
      await tokens.saveSession(
        userId: 'u-1',
        accessToken: 'a-1',
        refreshToken: 'r-1',
        isOnboarded: true,
      );

      await tokens.clear();

      // ⚠️ 여기가 깨지면 `clear()`가 `deleteAll()`로 돌아간 것이다.
      expect(await consent.hasAgreedTerms(), isTrue);
      expect((await tokens.read()).userId, isNull);
    });
  });
}

/// 플랫폼 채널 대신 `Map`에 넣는 [FlutterSecureStorage].
///
/// 테스트 환경에는 채널이 없어 진짜를 부르면 `MissingPluginException`이 난다.
/// 옵션 인자는 전부 무시한다 — 이 테스트가 보는 것은 **어떤 키가 남는가**뿐이다.
class _FakeSecureStorage extends FlutterSecureStorage {
  final _values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _values[key];

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(_values);

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.clear();
  }
}
