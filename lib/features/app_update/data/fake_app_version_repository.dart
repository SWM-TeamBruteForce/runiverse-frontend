import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/features/app_update/domain/app_update_status.dart';
import 'package:runiverse/features/app_update/domain/app_version_repository.dart';

/// 버전 기준을 손으로 먹이는 구현 — 테스트용.
///
/// ⚠️ **프로덕션에 끼우지 않는다.** 갈아 끼우는 자리는 provider 한 줄이다.
class FakeAppVersionRepository implements AppVersionRepository {
  FakeAppVersionRepository({
    AppVersion? minimum,
    AppVersion? latest,
    this.failure,
    this.latency = Duration.zero,
  }) : minimum = minimum ?? const AppVersion(1, 0, 0),
       latest = latest ?? const AppVersion(1, 0, 0);

  AppVersion minimum;
  AppVersion latest;

  /// 세워두면 [fetch]가 이것을 던진다. 스플래시의 오프라인 경로를 세울 때 쓴다.
  Object? failure;

  final Duration latency;

  /// 몇 번 물었나. **복귀할 때 다시 확인하는지**를 테스트가 이것으로 본다.
  int fetchCount = 0;

  @override
  Future<AppVersionPolicy> fetch() async {
    fetchCount++;
    if (latency != Duration.zero) await Future<void>.delayed(latency);

    final error = failure;
    if (error != null) throw error;

    return AppVersionPolicy(minimum: minimum, latest: latest);
  }

  /// 워치 앱 최소 버전. 워치는 최신 버전을 쓰지 않아 같은 값으로 돌려준다.
  AppVersion watchMinimum = const AppVersion(1, 0, 0);

  /// 세워두면 [fetchWatch] 가 이것을 던진다.
  Object? watchFailure;

  /// 워치 값을 몇 번 물었나.
  int watchFetchCount = 0;

  /// ⚠️ [latency] 를 따르지 않는다. 폰 판정은 이것을 기다리지 않아, 기다리게 하면
  /// 테스트가 끝날 때 타이머가 남는다.
  @override
  Future<AppVersionPolicy> fetchWatch() async {
    watchFetchCount++;
    final error = watchFailure;
    if (error != null) throw error;
    return AppVersionPolicy(minimum: watchMinimum, latest: watchMinimum);
  }
}
