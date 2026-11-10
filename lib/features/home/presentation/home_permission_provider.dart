import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/location_ask_store.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 홈에서 권한을 물었는지 기억하는 곳.
final locationAskStoreProvider = Provider<LocationAskStore>(
  (ref) => SecureLocationAskStore(),
);

/// 홈에 처음 들어온 기기에 위치·신체 활동 권한을 묻는다.
final homePermissionProvider = Provider<HomePermissionAsker>(
  HomePermissionAsker.new,
);

/// 러닝에 쓰는 권한을 **홈에서 미리** 받는다. 셸이 알림 권한 다음에 부른다.
///
/// ## 왜 홈에서 묻나
///
/// 매칭 러닝은 출발 30초 전 카운트다운에서 권한 창이 처음 뜬다. 30초 안에 창이
/// 둘이고, 거절하면 설정에 다녀올 시간이 없어 좌표 없는 러닝이 된다
/// (`docs/implementation-notes.md` §11-6). 홈 날씨도 위치가 있어야 보인다.
///
/// ## 기기당 한 번이다
///
/// 안드로이드는 두 번 거절하면 다시 물을 수 없다. 앱을 켤 때마다 물으면 홈에서
/// 두 번째 거절까지 받아, 러닝 출발 때 물을 기회가 사라진다. 러닝 출발 때의
/// 확인(`RunSessionController.prepare`)은 그대로다 — 이미 허용했으면 창 없이
/// 지나가고, 홈에서 거절한 안드로이드 기기에는 거기서 한 번 더 묻는다.
class HomePermissionAsker {
  HomePermissionAsker(this._ref);

  final Ref _ref;

  /// 아직 안 물은 기기면 위치, 신체 활동 순서로 묻는다.
  Future<void> askOnce() async {
    try {
      final location = _ref.read(locationRepositoryProvider);
      final access = await location.checkAccess();
      // ⚠️ 위치 기능이 꺼져 있으면 `ensureAccess`가 묻지도 않고 돌아온다.
      // 한 번뿐인 기회를 쓰지 않고 다음에 들어올 때 다시 본다.
      if (access == LocationAccess.serviceDisabled) return;

      final store = _ref.read(locationAskStoreProvider);
      if (await store.asked()) return;
      // ⚠️ **물었다는 것을 먼저 남긴다.** 권한 창이 떠 있는 동안 앱이 꺼지면
      // 남길 기회가 없다. 남기지 못하면 예외로 빠져 묻지 않는다.
      await store.markAsked();

      // `deniedForever`(iOS에서 이미 거절)는 물을 수 없다. 건너뛴다.
      if (access == LocationAccess.denied) await location.ensureAccess();
      await _ref.read(stepRepositoryProvider).ensureAccess();
    } on Object catch (error) {
      // 저장값을 못 읽은 경우도 여기로 온다 — **물었다고 본다.**
      debugPrint('[permission] 홈에서 권한을 묻지 못했다 · $error');
    }
  }
}
