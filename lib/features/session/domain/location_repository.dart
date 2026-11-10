import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/permission_access.dart';

/// 위치를 쓸 수 있는가.
///
/// geolocator의 `LocationPermission`을 그대로 쓰지 않는다. 그 타입을 domain에 들이면
/// 패키지 의존이 순수 계층으로 새고, 화면이 패키지 열거형을 `switch`하게 된다.
enum LocationAccess {
  /// 쓸 수 있다.
  granted,

  /// 허용하지 않았다. 다시 물을 수 있다. [LocationRepository.checkAccess]는
  /// 아직 묻지 않은 경우도 이 값이다.
  denied,

  /// 다시 묻지 않기로 했다. **앱에서 물을 방법이 없다** — 설정으로 보내야 한다.
  deniedForever,

  /// 권한과 별개로 기기의 위치 기능이 꺼져 있다.
  ///
  /// 권한을 아무리 줘도 좌표가 안 나오므로 안내 문구가 달라야 한다.
  serviceDisabled;

  bool get isGranted => this == LocationAccess.granted;
}

/// 위치 스트림이 도중에 끊긴 이유.
///
/// [LocationRepository.watchPosition]이 실패할 때 흘리는 **유일한 예외 타입**이다.
/// 패키지 예외를 그대로 흘리면 화면이 geolocator 타입을 `is`로 검사하게 되고,
/// 그 순간 패키지 의존이 presentation까지 샌다.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.reason);

  /// 왜 못 쓰는가. 화면은 이 값으로 안내 문구를 고른다.
  final LocationAccess reason;

  @override
  String toString() => 'LocationUnavailable(${reason.name})';
}

/// 위치를 가져오는 곳.
///
/// 구현은 둘이다 — 실제 GPS를 읽는 것과, 테스트에서 좌표를 손으로 먹이는 것.
/// 화면과 컨트롤러는 어느 쪽인지 모른다.
abstract interface class LocationRepository {
  /// 권한을 확인하고, 필요하면 사용자에게 묻는다.
  ///
  /// 이미 허용돼 있으면 묻지 않고 바로 [LocationAccess.granted]를 돌려준다.
  Future<LocationAccess> ensureAccess();

  /// 권한을 **묻지 않고** 지금 상태만 읽는다. 홈 날씨가 쓴다.
  ///
  /// ⚠️ **안드로이드는 "아직 안 물었음"과 "거절함"을 가르지 못한다.** 둘 다
  /// [LocationAccess.denied]다 — geolocator가 거절 이력을 보지 않는다
  /// (`PermissionManager.checkPermissionStatus`). iOS는 거절하면 곧바로
  /// [LocationAccess.deniedForever]라 `denied`면 아직 안 물은 것이다.
  Future<LocationAccess> checkAccess();

  /// 대강의 현재 위치. 권한을 묻지 않고, 못 구하면 `null`이다. 홈 날씨가 쓴다.
  ///
  /// 기기가 기억하는 마지막 위치를 먼저 쓴다 — GPS를 새로 켜지 않는다. 그 값이
  /// 없거나 오래됐으면 낮은 정확도로 한 번 새로 잡는다. 어제 서울에서 잡힌
  /// 위치로 오늘 부산의 날씨를 보여 주면 안 된다.
  Future<GeoPoint?> approximatePosition();

  /// 러닝 중 알림을 띄울 권한을 묻는다. 위치를 허용받은 뒤에 부른다.
  ///
  /// ⚠️ **Android 13부터 알림 권한이 있어야 러닝 알림이 보인다.** 선언만으로는
  /// 서랍에 안 뜬다. 거절해도 기록은 그대로 돈다.
  ///
  /// 묻지 않는 플랫폼(iOS)은 `null` 이다.
  Future<PermissionAccess?> ensureRunNotification();

  /// 위치 스트림을 연다.
  ///
  /// ⚠️ **구독을 끊는 것은 부르는 쪽 책임이다.** 안 끊으면 러닝이 끝나도
  /// GPS가 계속 돌아 배터리를 먹는다. `ref.onDispose`에서 취소한다
  /// (`docs/implementation-notes.md` §5-3).
  ///
  /// ⚠️ **[ensureAccess]를 통과해도 이 스트림은 실패할 수 있다.** 실패는
  /// [LocationUnavailable]로 흘린다 — `onError`를 달지 않으면 예외가 Zone으로
  /// 새고 화면이 멈춘 채로 남는다.
  Stream<GeoPoint> watchPosition();

  /// 기기의 위치 설정 화면을 연다. 사용자가 직접 켜야 할 때 쓴다.
  Future<void> openSettings();
}
