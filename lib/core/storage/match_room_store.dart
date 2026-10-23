import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 신청해 둔 매칭방 번호를 기억한다.
///
/// ## 왜 남기는가
///
/// 연동 가이드가 요구한다 — *"프론트엔드는 `runningRoomId`를 앱 상태와 로컬
/// 저장소에 저장해주세요. 이후 러닝을 시작하고 종료 결과를 조회할 때도 같은
/// ID를 사용합니다."*
///
/// 신청과 러닝과 결과 조회가 **같은 방 번호 하나**로 이어진다. 그 번호를
/// 메모리에만 들고 있으면 앱이 죽는 순간 끊긴다.
///
/// ## `active_run` 테이블과 나누는 이유
///
/// 그쪽은 **달리는 중인 방**이다. 409를 풀 때 그 번호로 `RUNNING_FINISH`를
/// 보내는데, 아직 시작하지도 않은 매칭방 번호가 거기 들어가면 **시작한 적
/// 없는 러닝을 끝내려 든다.** 이름이 같아도 뜻이 다르므로 자리를 나눈다.
///
/// ## ⚠️ 이것만으로 상태를 판단하지 않는다
///
/// 여기 번호가 남아 있어도 서버에서는 이미 끝났을 수 있다 — 다른 기기에서
/// 취소했거나 방이 닫혔을 때다. **무엇이 진행 중인지는 `/users/me/status`가
/// 정하고**, 이 값은 그 답을 보조할 뿐이다.
abstract interface class MatchRoomStore {
  /// 신청해 둔 방 번호. 없으면 `null`.
  Future<int?> read();

  /// 신청이 받아들여졌을 때 남긴다.
  Future<void> save(int runningRoomId);

  /// 취소·종료로 그 방과의 관계가 끝났을 때 지운다.
  Future<void> clear();
}

/// 안드로이드 Keystore · iOS Keychain에 넣는 [MatchRoomStore].
///
/// 방 번호는 민감하지 않지만, 값 하나 때문에 `shared_preferences`를 새로
/// 들이지 않는다 — `SecureConsentStore`와 같은 판단이다.
class SecureMatchRoomStore implements MatchRoomStore {
  SecureMatchRoomStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// `auth.*`와 접두사를 나눈다. 로그아웃이 지울 것과 남길 것이 이름으로 갈린다.
  static const _key = 'match.runningRoomId';

  @override
  Future<int?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : int.tryParse(raw);
  }

  @override
  Future<void> save(int runningRoomId) =>
      _storage.write(key: _key, value: '$runningRoomId');

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// 메모리에만 들고 있는 구현. 테스트가 쓴다 —
/// 위젯 테스트는 플랫폼 채널을 부를 수 없다.
class InMemoryMatchRoomStore implements MatchRoomStore {
  int? _roomId;

  @override
  Future<int?> read() async => _roomId;

  @override
  Future<void> save(int runningRoomId) async => _roomId = runningRoomId;

  @override
  Future<void> clear() async => _roomId = null;
}
