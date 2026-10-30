import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 이 설치본을 가리키는 기기 식별자. 푸시 기기 등록(명세 2-1)의 `deviceId`다.
///
/// ## 로그아웃해도 지우지 않는다
///
/// **기기의 값이지 계정의 값이 아니다.** 서버는 이 값으로 행을 찾아 덮어쓴다 —
/// 같은 폰에서 계정을 바꿔 로그인하면 같은 행의 주인이 바뀐다. 로그아웃 때
/// 지우면 계정을 바꿀 때마다 같은 폰의 행이 하나씩 늘어난다.
abstract interface class DeviceIdStore {
  /// 기기 식별자. 처음 부르면 만들어 저장하고, 그다음부터는 같은 값이다.
  Future<String> read();
}

/// 안드로이드 Keystore · iOS Keychain에 넣는 [DeviceIdStore].
///
/// 민감한 값은 아니다. 여기 넣는 이유는 `SecureConsentStore`와 같다 — 값 하나
/// 때문에 `shared_preferences`를 새로 들이지 않는다.
class SecureDeviceIdStore implements DeviceIdStore {
  SecureDeviceIdStore({FlutterSecureStorage? storage, Random? random})
    : _storage = storage ?? const FlutterSecureStorage(),
      _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _random;

  /// `auth.*`와 접두사를 나눈다. 로그아웃이 키를 지정해 지우므로 함께 날아가지
  /// 않는다(`SecureTokenStore.clear`).
  static const _key = 'device.id';

  /// ⚠️ **처음 읽는 것을 한 번으로 묶는다.** 두 곳이 동시에 부르면 둘 다 "없다"를
  /// 보고 서로 다른 값을 만든다 — 먼저 등록한 값이 덮여 서버에 주인 없는 행이 남는다.
  Future<String>? _loading;

  @override
  Future<String> read() async {
    final loading = _loading ??= _load();
    try {
      return await loading;
    } on Object {
      // ⚠️ **실패는 붙잡아 두지 않는다.** 남겨 두면 저장소가 한 번 삐끗한 것으로
      // 그 실행 내내 같은 실패만 돌려주고, 기기 등록이 다시는 나가지 않는다.
      if (identical(_loading, loading)) _loading = null;
      rethrow;
    }
  }

  Future<String> _load() async {
    final saved = await _storage.read(key: _key);
    if (saved != null) return saved;
    final created = newDeviceId(_random);
    await _storage.write(key: _key, value: created);
    return created;
  }
}

/// UUID v4 꼴의 무작위 값. 서버는 형식을 보지 않지만 명세가 "앱은 UUID를
/// 쓴다"고 적어 두었다.
///
/// ⚠️ **`Random.secure()`를 넘긴다.** 값을 맞힐 수 있으면 안 된다 — 서버는 같은
/// `deviceId`로 등록한 사람에게 행을 넘기므로(명세 2-1), 남의 값을 맞히면 그
/// 폰의 푸시를 끊을 수 있다.
String newDeviceId(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // 버전 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 변형
  final hex = [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
