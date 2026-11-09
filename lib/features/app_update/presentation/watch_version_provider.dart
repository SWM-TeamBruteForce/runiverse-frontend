import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/watch_version_store.dart';
import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';

/// 워치 최소 버전을 어디에 남길 것인가.
///
/// ⚠️ **위젯 테스트는 이것을 override한다.** 플랫폼 채널을 부른다.
/// `InMemoryWatchVersionStore` 를 넣으면 된다.
final watchVersionStoreProvider = Provider<WatchVersionStore>(
  (ref) => SecureWatchVersionStore(),
);

final watchVersionProvider =
    NotifierProvider<WatchVersionController, AppVersion?>(
      WatchVersionController.new,
    );

/// 서버가 정한 워치 앱 최소 버전. **아직 모르면 `null` 이다.**
///
/// ## 정본은 서버다
///
/// `app_versions` 테이블의 `WATCH_*` 행이다. 폰 앱 코드에 상수로 두지 않는다 —
/// 숫자가 두 곳이 되고, 서버에서 내려 풀어 줄 수 없다.
///
/// 폰 버전을 확인할 때(스플래시·복귀) 같이 받아 기기에 남긴다. 워치 연동은
/// [minimum] 으로 읽어 `WATCH_SYNC` 를 판정한다.
class WatchVersionController extends Notifier<AppVersion?> {
  @override
  AppVersion? build() => null;

  /// 남겨 둔 값 읽기. 한 번만 읽고, 읽는 중에 온 SYNC 도 같은 읽기를 기다린다 —
  /// 따로 `null` 을 돌려주면 저장값이 있는데도 "기준 모름"으로 답을 미룬다.
  Future<AppVersion?>? _loading;

  /// 받는 중인 요청. 워치가 3초마다 SYNC 를 보내도 요청은 하나만 나간다.
  Future<void>? _inflight;

  /// 판정 기준. 메모리에 없으면 남겨 둔 값을 한 번 읽는다. 끝내 모르면 `null`.
  Future<AppVersion?> minimum() {
    final known = state;
    if (known != null) return Future.value(known);
    return _loading ??= _load();
  }

  Future<AppVersion?> _load() async {
    AppVersion? stored;
    try {
      stored = await ref.read(watchVersionStoreProvider).minimum();
    } on Object catch (error) {
      debugPrint('[version] 남겨 둔 워치 기준을 못 읽었다 · ${error.runtimeType}');
    }
    // 기다리는 사이 provider 가 버려졌으면 state 를 건드리지 않는다.
    if (!ref.mounted) return null;
    // 읽는 사이 서버 값을 받았으면 그쪽이 새것이다.
    return state ??= stored;
  }

  /// 서버에서 받아 남긴다.
  ///
  /// ⚠️ **실패해도 갖고 있던 값을 지우지 않는다.** 폰이 서버에 못 닿는다고 워치
  /// 판정까지 잃으면, 워치가 기준을 받을 때까지 연결되지 않는다.
  Future<void> refresh() {
    final running = _inflight;
    if (running != null) return running;

    final started = _refresh();
    _inflight = started;
    started.whenComplete(() {
      if (identical(_inflight, started)) _inflight = null;
    });
    return started;
  }

  Future<void> _refresh() async {
    final AppVersion minimum;
    try {
      minimum =
          (await ref.read(appVersionRepositoryProvider).fetchWatch()).minimum;
    } on Object catch (error) {
      debugPrint('[version] 워치 기준을 못 받았다 · ${error.runtimeType}');
      return;
    }
    if (!ref.mounted) return;
    state = minimum;
    try {
      await ref.read(watchVersionStoreProvider).rememberMinimum(minimum);
    } on Object catch (error) {
      // 이번 실행 동안은 메모리 값으로 판정한다. 다음 실행에서 다시 받는다.
      debugPrint('[version] 워치 기준을 남기지 못했다 · ${error.runtimeType}');
    }
  }
}
