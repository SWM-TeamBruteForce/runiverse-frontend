import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/version/installed_app_version.dart';
import 'package:runiverse/features/app_update/domain/app_update_status.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';

/// 업데이트가 필요한가. **아직 못 물어봤으면 [unknown]이다.**
///
/// ⚠️ **"모른다"와 "괜찮다"를 섞지 않는다.** 섞으면 서버에 못 닿은 구버전 앱이
/// 판정 없이 그대로 들어간다. 스플래시가 [unknown]인 동안 기다린다.
sealed class AppUpdateState {
  const AppUpdateState();
}

/// 아직 묻지 않았거나 묻는 중이다.
class AppUpdateUnknown extends AppUpdateState {
  const AppUpdateUnknown();
}

/// 물어봤고 답을 받았다.
class AppUpdateChecked extends AppUpdateState {
  const AppUpdateChecked(this.status);

  final AppUpdateStatus status;
}

/// 물어봤는데 못 받았다. **판정이 없는 것이지 괜찮은 것이 아니다.**
class AppUpdateUnreachable extends AppUpdateState {
  const AppUpdateUnreachable();
}

final appUpdateProvider = NotifierProvider<AppUpdateController, AppUpdateState>(
  AppUpdateController.new,
);

/// 서버 기준을 받아 지금 앱으로 써도 되는지 정한다.
///
/// ## 두 곳이 부른다
///
/// 스플래시가 **토큰 복원보다 먼저** 한 번(명세), 그리고 앱이 포그라운드로
/// 돌아올 때마다 한 번. 최소 버전은 서버에서 언제든 올라갈 수 있어서, 켜 둔
/// 앱이 계속 쓸 수 있다고 믿으면 안 된다.
class AppUpdateController extends Notifier<AppUpdateState> {
  @override
  AppUpdateState build() => const AppUpdateUnknown();

  /// 묻는 중인가. 겹쳐 부르면 같은 요청이 여러 번 나간다 — 스플래시와
  /// 포그라운드 복귀가 거의 동시에 올 수 있다.
  Future<void>? _inflight;

  /// 서버에 묻고 판정한다.
  ///
  /// ⚠️ **실패를 "괜찮다"로 바꾸지 않는다.** [AppUpdateUnreachable]로 남겨
  /// 부르는 쪽이 다시 시도하게 한다.
  Future<void> check() {
    final running = _inflight;
    if (running != null) return running;

    final started = _check();
    _inflight = started;
    started.whenComplete(() {
      if (identical(_inflight, started)) _inflight = null;
    });
    return started;
  }

  Future<void> _check() async {
    try {
      final policy = await ref.read(appVersionRepositoryProvider).fetch();
      final status = policy.statusFor(InstalledAppVersion.current);
      debugPrint('[version] 판정 · ${status.name}');
      state = AppUpdateChecked(status);
    } on Object catch (error) {
      debugPrint('[version] 판정하지 못했다 · ${error.runtimeType}');
      // ⚠️ **이미 받아 둔 판정을 지우지 않는다.** 복귀할 때 한 번 실패했다고
      // 막아 둔 화면을 풀면, 업데이트하지 않은 사람이 그대로 들어간다.
      // 명세도 "포그라운드 복귀 때 실패하면 쓰던 화면을 그대로 둔다"고 적었다.
      if (state is AppUpdateUnknown) state = const AppUpdateUnreachable();
    }
  }

  /// 다시 묻는다. 재시도 버튼과 포그라운드 복귀가 쓴다.
  ///
  /// ⚠️ **막혀 있을 때도 다시 묻는다.** 최소 버전이 내려가면 풀어 줘야 한다
  /// (명세: "화면이 떠 있는 동안에도 … 다시 확인해, 최소 버전이 내려가 있으면
  /// 풀어 준다").
  Future<void> recheck() {
    if (state is AppUpdateUnreachable) state = const AppUpdateUnknown();
    return check();
  }
}
