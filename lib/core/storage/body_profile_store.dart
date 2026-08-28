import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 기기에 남겨 둔 신체 정보.
///
/// 셋 다 없을 수 있다. **모르는 것을 기본값으로 채우지 않는다** — 63kg으로
/// 때우면 그 사람의 칼로리가 조용히 틀린다.
class StoredBody {
  const StoredBody({this.birthday, this.heightCm, this.weightKg});

  static const empty = StoredBody();

  final DateTime? birthday;
  final int? heightCm;

  /// 칼로리 계산에 쓰는 유일한 값이다. 키는 지금 쓰이지 않는다.
  final int? weightKg;

  bool get isEmpty => birthday == null && heightCm == null && weightKg == null;
}

/// 생년월일·키·몸무게를 기기에 둔다.
///
/// ## ⚠️ 서버에 이것을 주는 조회 API가 없다
///
/// `GET /users/me`는 `userId`·`nickname`·`isOnboarded`뿐이고, `/users/me/profile`은
/// PATCH만 있다. 그래서 **앱이 아는 유일한 경로는 자기가 보낸 값을 기억하는 것**이다.
///
/// | 언제 | 무엇 |
/// |---|---|
/// | 온보딩 완료 | 입력한 값을 그대로 저장 |
/// | 프로필 편집 저장 성공 | 바꾼 값만 덮어쓰기 |
/// | 로그아웃·탈퇴 | 지운다 |
///
/// ⚠️ **다른 기기에서 로그인하면 비어 있다.** 서버가 안 주므로 알 방법이 없고,
/// 그 기기에서는 프로필 편집을 한 번 거쳐야 칼로리가 나온다. `GET /users/me`에
/// `weightKg`·`heightCm`을 실어 달라고 요청해 둔 상태다 — 붙으면 이 저장소는
/// 캐시로만 남는다.
///
/// ## 왜 `TokenStore`에 넣지 않나
///
/// 그쪽은 **인증**이다. 여기 값은 인증과 수명만 같고 성격이 다르다.
/// 한 클래스에 모으면 "토큰을 읽는다"가 신체 정보까지 읽는 일이 된다.
abstract interface class BodyProfileStore {
  Future<StoredBody> read();

  /// **준 값만 덮어쓴다.** `null`은 "안 바꿈"이지 "지움"이 아니다 —
  /// 프로필 편집이 부분 수정이라 안 보낸 필드는 서버에서도 그대로다.
  Future<void> save({DateTime? birthday, int? heightCm, int? weightKg});

  /// 로그아웃·탈퇴. **계정의 정보라 남기면 안 된다.**
  Future<void> clear();
}

/// 안드로이드 Keystore · iOS Keychain에 넣는 [BodyProfileStore].
///
/// 민감도가 토큰만큼은 아니지만 **개인 신체 정보**다. 값 몇 개 때문에 저장소를
/// 새로 들이지 않는다는 [SecureConsentStore]와 같은 판단이기도 하다.
class SecureBodyProfileStore implements BodyProfileStore {
  SecureBodyProfileStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// `auth.*` · `consent.*`와 접두사를 나눈다. 지울 것이 이름으로 갈린다.
  static const _keyBirthday = 'body.birthday';
  static const _keyHeight = 'body.heightCm';
  static const _keyWeight = 'body.weightKg';

  @override
  Future<StoredBody> read() async {
    final values = await Future.wait([
      _storage.read(key: _keyBirthday),
      _storage.read(key: _keyHeight),
      _storage.read(key: _keyWeight),
    ]);

    return StoredBody(
      // 저장한 적 없거나 값이 깨졌으면 `null`이다. 깨진 값으로 죽지 않는다.
      birthday: DateTime.tryParse(values[0] ?? ''),
      heightCm: int.tryParse(values[1] ?? ''),
      weightKg: int.tryParse(values[2] ?? ''),
    );
  }

  @override
  Future<void> save({DateTime? birthday, int? heightCm, int? weightKg}) async {
    await Future.wait([
      if (birthday != null)
        // 날짜만 남긴다. 시각은 이 값에 의미가 없다.
        _storage.write(
          key: _keyBirthday,
          value: birthday.toIso8601String().split('T').first,
        ),
      if (heightCm != null) _storage.write(key: _keyHeight, value: '$heightCm'),
      if (weightKg != null) _storage.write(key: _keyWeight, value: '$weightKg'),
    ]);
  }

  @override
  Future<void> clear() async {
    // ⚠️ `deleteAll()`을 쓰지 않는다. 같은 저장소에 토큰과 약관 동의가 있다.
    await Future.wait([
      _storage.delete(key: _keyBirthday),
      _storage.delete(key: _keyHeight),
      _storage.delete(key: _keyWeight),
    ]);
  }
}

/// 메모리에만 들고 있는 구현. 테스트가 쓴다 —
/// 위젯 테스트는 플랫폼 채널을 부를 수 없다.
class InMemoryBodyProfileStore implements BodyProfileStore {
  StoredBody _body = StoredBody.empty;

  @override
  Future<StoredBody> read() async => _body;

  @override
  Future<void> save({DateTime? birthday, int? heightCm, int? weightKg}) async {
    _body = StoredBody(
      birthday: birthday ?? _body.birthday,
      heightCm: heightCm ?? _body.heightCm,
      weightKg: weightKg ?? _body.weightKg,
    );
  }

  @override
  Future<void> clear() async => _body = StoredBody.empty;
}
