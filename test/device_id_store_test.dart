import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/device_id_store.dart';

/// 푸시 기기 등록의 `deviceId`.
///
/// 값이 바뀌면 서버에 같은 폰의 행이 하나 더 생긴다. 그래서 **한 번 만든 값을
/// 계속 쓰는가**를 본다.
void main() {
  test('UUID v4 꼴이다', () {
    final id = newDeviceId(Random(7));

    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });

  test('한 번 만든 값을 다음 실행에도 쓴다', () async {
    final storage = _FakeSecureStorage();

    final first = await SecureDeviceIdStore(storage: storage).read();
    // 앱을 다시 켰다 — 저장소 객체가 새로 만들어진다.
    final second = await SecureDeviceIdStore(storage: storage).read();

    expect(second, first);
  });

  test('⚠️ 처음에 두 곳이 동시에 읽어도 값은 하나다', () async {
    // 둘 다 "없다"를 보고 따로 만들면 먼저 등록한 값이 덮인다.
    final store = SecureDeviceIdStore(storage: _FakeSecureStorage());

    final both = await Future.wait([store.read(), store.read()]);

    expect(both[1], both[0]);
  });

  test('⚠️ 저장소가 한 번 실패해도 다음에는 다시 읽는다', () async {
    // 실패를 붙잡아 두면 그 실행 내내 기기 등록이 나가지 않는다.
    final storage = _FakeSecureStorage()..failNextRead = true;
    final store = SecureDeviceIdStore(storage: storage);

    await expectLater(store.read(), throwsA(isA<StateError>()));

    expect(await store.read(), isNotEmpty);
  });
}

/// 플랫폼 채널 대신 `Map`에 넣는다. 이 테스트가 부르는 읽기·쓰기만 흉내 낸다.
class _FakeSecureStorage extends FlutterSecureStorage {
  final _values = <String, String>{};

  /// 켜 두면 다음 읽기 한 번이 실패한다(Keystore·Keychain 일시 오류).
  var failNextRead = false;

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
  }) async {
    if (failNextRead) {
      failNextRead = false;
      throw StateError('저장소를 읽지 못했다');
    }
    return _values[key];
  }
}
