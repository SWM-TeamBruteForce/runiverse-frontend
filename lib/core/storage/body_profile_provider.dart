import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/body_profile_remote.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';

/// 어디에 넣을 것인가.
///
/// ⚠️ **위젯 테스트는 이것을 override해야 한다.** 플랫폼 채널을 부르는데
/// 테스트 환경에는 채널이 없어 `MissingPluginException`이 난다.
/// `InMemoryBodyProfileStore`를 넣으면 된다.
final bodyProfileStoreProvider = Provider<BodyProfileStore>(
  (ref) => SecureBodyProfileStore(),
);

/// 서버에서 읽어올 곳. **`null`이면 묻지 않는다.**
///
/// 기본이 `null`인 것은 테스트 때문이다 — 진짜를 넣으면 `dio`가 서버 주소를
/// 찾다 죽는다. `main.dart`가 `profileRepositoryProvider`로 덮는다
/// (`analyticsProvider`와 같은 모양이다).
final bodyProfileRemoteProvider = Provider<BodyProfileRemote?>((ref) => null);

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
    // ⚠️ **버려졌는지 봐야 한다.** 아래 두 단계가 비동기라, 다 오기 전에
    // 이 provider가 치워질 수 있다. 그때 `ref`를 읽거나 `state`를 쓰면
    // Riverpod이 던진다 — 테스트에서는 끝난 테스트가 실패로 바뀌고,
    // 앱에서는 아무 화면도 안 쓰는 값을 세우다 로그가 더럽혀진다.
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    // 기다리지 않는다. 값이 오면 상태가 바뀌고 화면이 다시 그려진다.
    _load();
    return StoredBody.empty;
  }

  var _disposed = false;

  Future<void> _load() async {
    try {
      final stored = await _store.read();
      if (_disposed) return;
      if (!stored.isEmpty) state = stored;
    } on Object catch (error) {
      // ⚠️ **읽기 실패로 죽지 않는다.** 저장소를 못 읽으면 신체 정보를 모르는
      // 것뿐이고, 그때 칼로리가 `--`로 나오는 것이 올바른 동작이다. 여기서
      // 던지면 러닝 화면이 통째로 멈춘다.
      debugPrint('[body] 신체 정보를 읽지 못했다 · $error');
    }
    if (_disposed) return;
    // 기기 값으로 먼저 그린 뒤 서버 값으로 덮는다.
    await refresh();
  }

  /// 서버가 가진 값으로 맞춘다. **읽었으면 참이다.**
  ///
  /// ## 왜 여기서 읽나
  ///
  /// 러닝으로 들어오는 길이 네 갈래다(홈 복구 · 스플래시 복구 · 솔로 준비 ·
  /// 매칭 카운트다운). 화면마다 부르면 **한 군데를 빠뜨리는 순간 그 경로의
  /// 칼로리만 조용히 `--`가 된다** — 실제로 매칭 러닝은 준비 화면을 지나지
  /// 않는다. 값을 가진 쪽이 스스로 채우면 빠뜨릴 자리가 없다.
  ///
  /// ## 서버의 `null`은 덮지 않는다
  ///
  /// 온보딩 전이면 서버도 셋 다 `null`이다. 그걸로 덮으면 **방금 온보딩에서
  /// 입력한 값이 지워진다**(온보딩 저장과 이 호출은 순서가 보장되지 않는다).
  /// [remember]와 같은 규칙이다 — 받은 것만 덮어쓴다.
  ///
  /// ## 겹쳐 부르면 합친다
  ///
  /// ⚠️ 프로필 편집에 들어오는 순간이 그렇다 — **화면이 묻고, 그 화면이
  /// 이 provider를 처음 읽으면서 [build]가 또 묻는다.** 그대로 두면 요청이
  /// 두 번 나간다. 먼저 날아간 것에 함께 매달린다.
  Future<bool> refresh() =>
      _inFlight ??= _read().whenComplete(() => _inFlight = null);

  Future<bool>? _inFlight;

  Future<bool> _read() async {
    // 이미 치워졌다. 읽어도 둘 곳이 없다.
    if (_disposed) return false;

    final remote = ref.read(bodyProfileRemoteProvider);
    // 연결된 곳이 없다. 기기에 있는 것으로 돈다.
    if (remote == null) return false;

    try {
      final body = await remote.fetchBody();
      if (_disposed) return false;
      state = StoredBody(
        birthday: body.birthday ?? state.birthday,
        heightCm: body.heightCm ?? state.heightCm,
        weightKg: body.weightKg ?? state.weightKg,
      );
      // 다음 기동 때 서버를 기다리는 동안 쓸 값이다.
      await _guard(
        () => _store.save(
          birthday: body.birthday,
          heightCm: body.heightCm,
          weightKg: body.weightKg,
        ),
        '남기지',
      );
      return true;
    } on Object catch (error) {
      // ⚠️ **실패를 삼키되 거짓을 돌려준다.** 프로필 편집이 이 값으로
      // *불러오지 못한 것*과 *설정한 적 없는 것*을 가른다 — 못 불러온 것을
      // 안 설정한 것으로 읽으면 기본값 172·63을 서버에 쓰게 된다.
      debugPrint('[body] 서버에서 신체 정보를 읽지 못했다 · $error');
      return false;
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
