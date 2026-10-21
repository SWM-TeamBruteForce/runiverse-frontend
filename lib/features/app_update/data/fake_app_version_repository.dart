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
}
