import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/permission_access.dart';

/// 권한 결과를 GA에 싣는 이름. 러닝 준비와 홈이 같이 쓴다.
///
/// 한쪽만 바꾸면 GA에서 같은 결과가 두 이름으로 갈린다.
String locationResultName(LocationAccess access) => switch (access) {
  LocationAccess.granted => 'granted',
  LocationAccess.denied => 'denied',
  LocationAccess.deniedForever => 'denied_forever',
  LocationAccess.serviceDisabled => 'service_disabled',
};

/// 위치 말고 다른 권한의 결과 이름. [locationResultName]과 같은 값을 쓴다.
String permissionResultName(PermissionAccess access) => switch (access) {
  PermissionAccess.granted => 'granted',
  PermissionAccess.denied => 'denied',
  PermissionAccess.deniedForever => 'denied_forever',
};
