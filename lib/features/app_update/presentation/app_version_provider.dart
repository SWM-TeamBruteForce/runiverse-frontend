import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/app_update/data/http_app_version_repository.dart';
import 'package:runiverse/features/app_update/domain/app_version_repository.dart';
// `dioProvider`가 여기 있다. 다른 feature들도 전부 이 경로로 가져온다
// (`record` · `matching` · `profile` …). provider는 feature를 가로질러도 되는
// 예외이고, 방향은 `app_update → auth` 한쪽뿐이다.
import 'package:runiverse/features/auth/presentation/auth_provider.dart';

/// 서버가 정한 버전 기준을 가져오는 곳.
///
/// ⚠️ **테스트는 이것을 override한다.** 진짜를 두면 dio가 서버 주소를 찾다
/// 죽는다 — 테스트에는 주소가 없다.
final appVersionRepositoryProvider = Provider<AppVersionRepository>(
  (ref) => HttpAppVersionRepository(ref.watch(dioProvider)),
);
