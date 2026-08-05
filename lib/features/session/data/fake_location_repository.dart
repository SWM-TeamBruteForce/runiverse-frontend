import 'dart:async';

import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';

/// 좌표를 손으로 먹이는 구현 — 테스트와 에뮬레이터용.
///
/// 인증에서 서버 없이 `FakeAuthRepository`로 흐름을 완성한 것과 같은 방식이다.
/// 실기기 없이 거리·페이스·상태 전이를 전부 확인할 수 있다.
///
/// ⚠️ **프로덕션에 끼우지 않는다.** 갈아 끼우는 자리는 `run_session_provider.dart` 한 줄이다.
class FakeLocationRepository implements LocationRepository {
  FakeLocationRepository({this.access = LocationAccess.granted});

  /// [ensureAccess]가 돌려줄 값. 거절 흐름을 확인할 때 바꾼다.
  final LocationAccess access;

  final _controller = StreamController<GeoPoint>.broadcast();

  /// 설정 화면을 열라고 요청받은 횟수. 테스트가 확인한다.
  int openSettingsCount = 0;

  @override
  Future<LocationAccess> ensureAccess() async => access;

  @override
  Stream<GeoPoint> watchPosition() => _controller.stream;

  @override
  Future<void> openSettings() async => openSettingsCount++;

  /// 좌표 하나를 흘려보낸다.
  void emit(GeoPoint point) => _controller.add(point);

  /// 좌표 여러 개를 순서대로 흘려보낸다.
  void emitAll(Iterable<GeoPoint> points) => points.forEach(emit);

  /// 더 이상 좌표를 보내지 않는다.
  Future<void> dispose() => _controller.close();
}
