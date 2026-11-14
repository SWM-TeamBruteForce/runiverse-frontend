import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:runiverse/features/session/domain/permission_access.dart';

/// FCM의 알림 권한 상태를 도메인 값으로 옮긴다. [isIos]는 부르는 쪽이 넘긴다 —
/// 테스트가 두 플랫폼을 다 시험한다.
///
/// ⚠️ **iOS는 다시 물을 수 없어도 `denied`로 온다**(패키지 문서). 다시 물을 수
/// 있는 `denied`는 안드로이드 13 이상뿐이다 — 12 이하는 묻는 창이 없고, `denied`는
/// 설정에서 알림을 끈 것이다(`FlutterFirebaseMessagingPlugin.getPermissions`).
/// 12 이하도 `denied`로 둔다 — 기록은 `granted`인지만 본다
/// (`Analytics.permissionResult`).
PermissionAccess toNotificationAccess(
  AuthorizationStatus status, {
  required bool isIos,
}) => switch (status) {
  AuthorizationStatus.authorized ||
  AuthorizationStatus.provisional => PermissionAccess.granted,
  AuthorizationStatus.deniedPermanently => PermissionAccess.deniedForever,
  AuthorizationStatus.denied =>
    isIos ? PermissionAccess.deniedForever : PermissionAccess.denied,
  // 물은 뒤라 오지 않아야 한다. 오면 허용받지 못한 것으로 친다.
  AuthorizationStatus.notDetermined => PermissionAccess.denied,
};
