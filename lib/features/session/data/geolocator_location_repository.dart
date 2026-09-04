import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:runiverse/core/strings/app_strings.dart';
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
  ///
  /// ## 플랫폼마다 설정을 갈라 쓴다
  ///
  /// **Android는 `FusedLocationProviderClient`를 쓴다.** geolocator의 기본값이라
  /// 공통 [LocationSettings]로도 그렇게 동작하지만, 그러면 그 사실이 코드
  /// 어디에도 드러나지 않고 누가 `forceLocationManager`를 켜도 막을 것이 없다.
  /// 명시해 둔다 — LocationManager로 떨어지면 정확도가 눈에 띄게 나빠진다.
  /// 좌표를 얼마나 자주 받나. 서버 명세는 `1~2초 간격`을 요구한다.
  ///
  /// **1초를 쓴다.** Strava·Nike Run Club·Garmin 모두 초당 1회가 기본이다.
  ///
  /// 2초로 늘려봤다가 되돌렸다. 이유는 둘이다.
  ///
  /// **곡선에서 거리가 깎인다.** 점 사이를 직선으로 이으므로 간격이 길수록
  /// 굽은 길에서 실제보다 짧게 나온다. 트랙 곡선이나 공원 산책로에서 두드러진다.
  /// GPS 노이즈는 반대로 거리를 부풀리지만 **그쪽은 칼만 필터가 잡고, 곡선
  /// 손실은 보정할 방법이 없다.**
  ///
  /// **칼만 `Q`가 간격을 모른다.** 간격이 두 배면 그사이 실제로 움직인 거리도
  /// 두 배인데 `Q`는 그대로라, 필터가 자기 예측을 과신해 경로가 안쪽으로
  /// 깎인다 — 거리가 짧아지는 방향으로 오차가 겹친다.
  ///
  /// 저장량은 30분에 약 300KB로 어느 쪽이든 문제가 되지 않고, 배터리는
  /// GPS 칩이 켜져 있는 것 자체가 주 소모원이라 샘플 수의 영향이 작다.
  static const _interval = Duration(seconds: 1);

  static LocationSettings get _settings {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        // ⚠️ `true`로 바꾸면 FusedLocationProviderClient를 쓰지 않는다.
        forceLocationManager: false,
        // ⚠️ **이것이 `null`이 아니어야 화면을 꺼도 좌표가 들어온다.**
        //
        // geolocator가 이 설정을 보고 위치 수집을 포그라운드 서비스로 띄운다.
        // 없으면 화면이 꺼지거나 앱이 뒤로 가는 순간 Android가 갱신을 시간당
        // 몇 번으로 제한하고, 그 구간이 좌표 공백이 된다 — 서버는 빈 자리를
        // 직선으로 이어 **거리를 실제보다 짧게 계산한다.**
        //
        // `notificationIcon`은 생략한다. 기본값이 `mipmap/ic_launcher`다.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: AppStrings.runNotificationTitle,
          notificationText: AppStrings.runNotificationText,
          notificationChannelName: AppStrings.runNotificationChannel,
          // 화면이 꺼진 동안 CPU를 깨워 둔다. 화면을 켜 두는 wakelock_plus와
          // 다른 것이다 — 그쪽은 화면, 이쪽은 CPU다.
          enableWakeLock: true,
          // 사용자가 쓸어서 지우지 못하게 한다. 지워도 서비스는 살아 있어
          // "껐는데 계속 도는" 것처럼 보이는 편이 더 나쁘다.
          setOngoing: true,
        ),
        // 서버 명세가 정한 "1~2초 간격" 중 빠른 쪽이다. 10초 배치에 10점씩 든다.
        intervalDuration: _interval,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        // 러닝 중임을 알리면 iOS가 그에 맞게 필터링을 조정한다.
        activityType: ActivityType.fitness,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

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

  /// ⚠️ **[ensureAccess]가 통과시켜도 이 스트림은 실패할 수 있다.**
  ///
  /// `isLocationServiceEnabled()`가 `true`라고 답한 직후에도
  /// `LocationServiceDisabledException`이 뜬다 — 안드로이드에서 실제 판정은
  /// `FusedLocationProviderClient`의 설정 검사가 하고, 그 검사는 GPS 말고
  /// network provider까지 본다. 두 답이 어긋나는 순간이 있다.
  ///
  /// 패키지 예외를 그대로 흘리지 않고 [LocationUnavailable]로 바꾼다.
  @override
  Stream<GeoPoint> watchPosition() =>
      Geolocator.getPositionStream(locationSettings: _settings)
          .handleError((Object error) {
            throw LocationUnavailable(
              error is LocationServiceDisabledException
                  ? LocationAccess.serviceDisabled
                  : LocationAccess.denied,
            );
          })
          .map(_toPoint);

  @override
  Future<void> openSettings() async {
    await Geolocator.openLocationSettings();
  }

  static GeoPoint _toPoint(Position position) => GeoPoint(
    latitude: position.latitude,
    longitude: position.longitude,
    // ⚠️ **UTC로 온다.** 서버는 오프셋 없는 KST를 받으므로 보내는 쪽에서
    // `.toLocal()`을 반드시 거쳐야 한다. 빠뜨리면 9시간 어긋난 기록이 쌓이는데
    // 에러가 나지 않아 한참 뒤에 발견된다.
    recordedAt: position.timestamp,
    accuracy: position.accuracy,
    // 칼만 필터의 프로세스 노이즈를 정하는 값이다. 센서가 못 구하면 음수가 온다.
    speed: position.speed,
    // 못 구하면 `null`로 든다. 안드로이드는 값이 없을 때 0을 주기도 해서
    // 0과 "정말 해수면"을 구분할 수 없지만, 서버도 이 값을 참고용으로만 쓴다.
    altitude: position.altitude,
    // ⚠️ 방향을 못 구하면 음수나 0이 온다. 음수는 "모른다"로 옮긴다 —
    // 0을 그대로 두면 "정북"이라는 뜻이 되어 거짓이 된다.
    heading: position.heading < 0 ? null : position.heading,
  );
}
