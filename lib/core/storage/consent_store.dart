import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 약관에 동의한 적이 있는가를 기억한다.
///
/// ## 왜 `TokenStore`와 나누는가
///
/// **수명이 다르다.** 토큰은 로그아웃하면 지워지지만 약관 동의는 남아야 한다 —
/// 로그아웃했다고 다시 동의를 받으면 같은 사람에게 같은 것을 두 번 묻는 셈이다.
///
/// ## ⚠️ 기기 단위로만 안다
///
/// 서버가 필수 약관 동의를 저장하지 않아 앱이 대신 기록한다. 그래서
/// **앱을 지우면 이미 동의한 사람이 다시 보고**, 같은 기기의 다른 계정은 건너뛴다.
/// 여기 남은 기록은 "이 기기 사용자가 동의했다"는 뜻이지 "이 계정이"가 아니다.
///
/// 서버에 `termsAgreed`가 생기면 판정 근거를 그쪽으로 옮기고 이 저장소는 지운다.
///
/// ## ⚠️ 지우는 쪽은 **탈퇴 하나뿐이다**
///
/// 로그아웃은 지우지 않는다(위 참조). 탈퇴는 다르다 — **계정이 사라졌으므로
/// 동의도 함께 사라진 것**이고, 서버에는 다음 로그인 때 계정이 새로 만들어진다.
/// 남겨 두면 같은 소셜 계정으로 다시 들어온 사람이 **약관을 건너뛰고** 프로필
/// 입력부터 보게 된다. 동의를 받은 적 없는 계정이 생긴다.
///
/// 설정 화면의 철회는 아직 없다. 생기면 같은 메서드를 쓴다.
abstract interface class ConsentStore {
  /// 필수 약관에 동의한 적이 있는가.
  Future<bool> hasAgreedTerms();

  /// 동의를 기록한다.
  Future<void> markTermsAgreed();

  /// 기록을 지운다. **탈퇴할 때만 부른다** — 로그아웃은 부르지 않는다.
  Future<void> forgetTermsAgreement();
}

/// 안드로이드 Keystore · iOS Keychain에 넣는 [ConsentStore].
///
/// 동의 여부는 민감하지 않아 암호화가 필요하지 않다. 그런데도 여기 넣는 이유는
/// **값 하나 때문에 `shared_preferences`를 새로 들이지 않기 위해서다.**
///
/// ⚠️ 같은 저장소를 쓰므로 `SecureTokenStore.clear()`가 `deleteAll()`이면
/// 로그아웃할 때 이것까지 지워진다. 그쪽은 키를 지정해 지운다.
class SecureConsentStore implements ConsentStore {
  SecureConsentStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// `auth.*`와 접두사를 나눈다. 지울 것과 남길 것이 이름으로 갈린다.
  static const _keyTermsAgreed = 'consent.termsAgreed';

  @override
  Future<bool> hasAgreedTerms() async =>
      await _storage.read(key: _keyTermsAgreed) == 'true';

  @override
  Future<void> markTermsAgreed() =>
      _storage.write(key: _keyTermsAgreed, value: 'true');

  // ⚠️ `deleteAll()`을 쓰지 않는다. 같은 저장소에 토큰이 들어 있어
  // 함께 날아간다 — `SecureTokenStore` 가 키를 지정해 지우는 것과 같은 이유다.
  @override
  Future<void> forgetTermsAgreement() => _storage.delete(key: _keyTermsAgreed);
}

/// 메모리에만 들고 있는 구현. 테스트가 쓴다 —
/// 위젯 테스트는 플랫폼 채널을 부를 수 없다.
///
/// 동의한 상태로 시작하려면 [markTermsAgreed]를 미리 부른다. 생성자 인자를 두지
/// 않는 이유는 **동의를 남기는 길이 하나여야** 저장소가 하는 일이 분명해서다.
class InMemoryConsentStore implements ConsentStore {
  bool _agreed = false;

  @override
  Future<bool> hasAgreedTerms() async => _agreed;

  @override
  Future<void> markTermsAgreed() async => _agreed = true;

  @override
  Future<void> forgetTermsAgreement() async => _agreed = false;
}
