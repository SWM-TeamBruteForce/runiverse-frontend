import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';

/// 어디에 넣을 것인가.
///
/// ⚠️ **위젯 테스트는 이것을 override해야 한다.** 플랫폼 채널을 부르는데
/// 테스트 환경에는 채널이 없어 `MissingPluginException`이 난다.
/// `InMemoryBodyProfileStore`를 넣으면 된다.
final bodyProfileStoreProvider = Provider<BodyProfileStore>(
  (ref) => SecureBodyProfileStore(),
);

/// 지금 아는 신체 정보.
///
/// ## 왜 `core`에 있나
///
/// **두 feature가 함께 본다.** 프로필 편집이 값을 쓰고 러닝이 칼로리를 내는 데
/// 읽는다. 어느 한쪽 `presentation`에 두면 다른 쪽이 그것을 import해야 하고
/// 그것은 금지된 방향이다(`CLAUDE.md`). `databaseProvider`와 같은 판단이다.
///
/// ## 처음에는 비어 있다
///
/// 저장소를 읽는 것이 비동기라 [build]가 곧바로 값을 줄 수 없다. 빈 값으로
/// 시작하고 읽히는 대로 채운다 — **`AsyncValue`로 만들지 않는다.** 그러면 이걸
/// 읽는 모든 화면이 로딩 분기를 갖게 되는데, 신체 정보를 모른다고 러닝 화면이
/// 로딩으로 남을 이유가 없다.
final bodyProfileProvider = NotifierProvider<BodyProfileController, StoredBody>(
  BodyProfileController.new,
);

class BodyProfileController extends Notifier<StoredBody> {
  BodyProfileStore get _store => ref.read(bodyProfileStoreProvider);

  @override
  StoredBody build() {
    // 기다리지 않는다. 값이 오면 상태가 바뀌고 화면이 다시 그려진다.
    _load();
    return StoredBody.empty;
  }

  Future<void> _load() async {
    try {
      final stored = await _store.read();
      if (!stored.isEmpty) state = stored;
    } on Object catch (error) {
      // ⚠️ **읽기 실패로 죽지 않는다.** 저장소를 못 읽으면 신체 정보를 모르는
      // 것뿐이고, 그때 칼로리가 `--`로 나오는 것이 올바른 동작이다. 여기서
      // 던지면 러닝 화면이 통째로 멈춘다.
      debugPrint('[body] 신체 정보를 읽지 못했다 · $error');
    }
  }

  /// 서버에 보내 성공한 값을 남긴다. **준 것만 덮어쓴다.**
  ///
  /// ⚠️ **서버가 받아준 뒤에 부른다.** 보내기 전에 저장하면 요청이 실패했을 때
  /// 기기와 서버가 갈린다.
  Future<void> remember({
    DateTime? birthday,
    int? heightCm,
    int? weightKg,
  }) async {
    // 화면이 먼저다. 저장에 실패해도 **이번 러닝의 칼로리는 나와야 한다.**
    state = StoredBody(
      birthday: birthday ?? state.birthday,
      heightCm: heightCm ?? state.heightCm,
      weightKg: weightKg ?? state.weightKg,
    );
    await _guard(
      () => _store.save(
        birthday: birthday,
        heightCm: heightCm,
        weightKg: weightKg,
      ),
      '남기지',
    );
  }

  /// 로그아웃·탈퇴. 계정의 정보라 기기에 남기지 않는다.
  Future<void> clear() async {
    state = StoredBody.empty;
    await _guard(_store.clear, '지우지');
  }

  /// 저장소 오류로 흐름을 멈추지 않는다.
  ///
  /// ⚠️ **여기서 던지면 로그아웃이 중단된다.** 토큰은 이미 지워진 뒤라
  /// 어중간한 상태로 남는다. 이 저장소는 캐시라 실패가 흐름을 막을 이유가 없다.
  static Future<void> _guard(
    Future<void> Function() action,
    String what,
  ) async {
    try {
      await action();
    } on Object catch (error) {
      debugPrint('[body] 신체 정보를 $what 못했다 · $error');
    }
  }
}
