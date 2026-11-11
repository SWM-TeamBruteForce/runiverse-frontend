import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/core/storage/location_ask_store.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/presentation/permission_result_names.dart';
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
/// 안드로이드는 [LocationAskStore]로, iOS는 권한 상태로 가른다([askOnce]).
/// 안드로이드는 두 번 거절하면 다시 물을 수 없다. 앱을 켤 때마다 물으면 홈에서
/// 두 번째 거절까지 받아, 러닝 출발 때 물을 기회가 사라진다. 러닝 출발 때의
/// 확인(`RunSessionController.prepare`)은 그대로다 — 이미 허용했으면 창 없이
/// 지나가고, 홈에서 거절한 안드로이드 기기에는 거기서 한 번 더 묻는다.
class HomePermissionAsker {
  HomePermissionAsker(this._ref);

  final Ref _ref;

  /// `Platform.isIOS`가 아니라 [defaultTargetPlatform]을 본다 — 테스트가
  /// `debugDefaultTargetPlatformOverride`로 두 경우를 다 시험한다
  /// (`SignInPage._showApple`과 같은 판단).
  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  /// 아직 안 물은 기기면 위치, 신체 활동 순서로 묻는다.
  ///
  /// 물을 일이 끝났으면 `true`다. **위치 기능이 꺼져 있어 미뤘으면 `false`** —
  /// 부르는 쪽이 앱으로 돌아올 때 다시 부른다.
  Future<bool> askOnce() async {
    try {
      final location = _ref.read(locationRepositoryProvider);
      final access = await location.checkAccess();
      // ⚠️ 위치 기능이 꺼져 있으면 `ensureAccess`가 묻지도 않고 돌아온다.
      // 한 번뿐인 기회를 쓰지 않고 미룬다.
      if (access == LocationAccess.serviceDisabled) return false;

      // ⚠️ **iOS는 저장값을 보지 않는다.** iOS는 거절하면 곧바로
      // `deniedForever`라 `denied`면 아직 안 물은 것이다 — 상태만으로 가른다.
      // 저장값은 Keychain에 남아 **앱을 지워도 살아남는데** 권한은 초기화되어,
      // 다시 깐 기기에서 홈이 한 번도 묻지 않게 된다(`SecureTokenStore` 주석).
      if (_isIos) {
        if (access != LocationAccess.denied) return true;
      } else {
        final store = _ref.read(locationAskStoreProvider);
        if (await store.asked()) return true;
        // ⚠️ **물었다는 것을 먼저 남긴다.** 권한 창이 떠 있는 동안 앱이 꺼지면
        // 남길 기회가 없다. 남기지 못하면 예외로 빠져 묻지 않는다.
        await store.markAsked();
      }

      // `deniedForever`(안드로이드에서 두 번 거절)는 물을 수 없다. 건너뛴다.
      if (access == LocationAccess.denied) {
        // 위치가 실패해도 신체 활동은 묻는다. 이미 물었다고 남겼다.
        try {
          final asked = await location.ensureAccess();
          _log('location', locationResultName(asked));
        } on Object catch (error) {
          debugPrint('[permission] 위치 권한을 묻지 못했다 · $error');
        }
      }
      final activity = await _ref.read(stepRepositoryProvider).ensureAccess();
      _log('activity', permissionResultName(activity));
      return true;
    } on Object catch (error) {
      // 저장값을 못 읽은 경우도 여기로 온다 — **물었다고 본다.**
      debugPrint('[permission] 홈에서 권한을 묻지 못했다 · $error');
      return true;
    }
  }

  /// 물은 결과를 GA 에 남긴다. 러닝 준비도 같은 권한을 남기므로 자리는 `home` 이다.
  void _log(String permission, String result) => unawaited(
    _ref
        .read(analyticsProvider)
        .permissionResult(
          permission: permission,
          result: result,
          askedFrom: 'home',
        ),
  );
}
