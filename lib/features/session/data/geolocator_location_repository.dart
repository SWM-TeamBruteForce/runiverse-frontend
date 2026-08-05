import 'package:geolocator/geolocator.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';

/// 실제 GPS를 읽는 구현.
///
/// **이 파일이 geolocator를 아는 유일한 곳이다.** 패키지 타입(`Position`,
/// `LocationPermission`)이 밖으로 새지 않게 여기서 전부 도메인 타입으로 옮긴다.
class GeolocatorLocationRepository implements LocationRepository {
  const GeolocatorLocationRepository();

  /// `distanceFilter: 0` — 걸러내지 않고 오는 대로 받는다.
  ///
  /// 패키지가 거리로 미리 걸러줄 수도 있지만, 그러면 보정 규칙이 패키지 설정과
  /// 우리 코드 두 곳으로 나뉜다. 받는 것은 다 받고 판단은 한곳에서 한다
  /// (`docs/specs/2026-08-05-solo-run-design.md` 3절).
  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 0,
  );

  @override
  Future<LocationAccess> ensureAccess() async {
    // 권한보다 먼저 본다. 기기의 위치 기능이 꺼져 있으면 권한을 줘도 좌표가 안 나온다.
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // 값을 빠짐없이 적는다. 패키지가 값을 추가하면 여기서 컴파일이 깨지고,
    // 그때 무엇으로 볼지 결정하게 된다. 조용히 넘어가는 것보다 낫다.
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied ||
      LocationPermission.unableToDetermine => LocationAccess.denied,
    };
  }

  @override
  Stream<GeoPoint> watchPosition() =>
      Geolocator.getPositionStream(locationSettings: _settings).map(_toPoint);

  @override
  Future<void> openSettings() async {
    await Geolocator.openLocationSettings();
  }

  static GeoPoint _toPoint(Position position) => GeoPoint(
    latitude: position.latitude,
    longitude: position.longitude,
    recordedAt: position.timestamp,
    accuracy: position.accuracy,
  );
}
