import 'package:permission_handler/permission_handler.dart';
import 'package:runiverse/features/session/domain/permission_access.dart';

/// `permission_handler`의 결과를 도메인 값으로 옮긴다. 걸음·알림이 함께 쓴다.
PermissionAccess toPermissionAccess(PermissionStatus status) =>
    switch (status) {
      // iOS의 부분 허용·임시 허용도 쓸 수는 있다.
      PermissionStatus.granted ||
      PermissionStatus.limited ||
      PermissionStatus.provisional => PermissionAccess.granted,
      PermissionStatus.permanentlyDenied => PermissionAccess.deniedForever,
      // 보호자 통제 등으로 막혀 있다. 앱에서 풀 수 없지만 사용자가 거절한 것은 아니다.
      PermissionStatus.denied ||
      PermissionStatus.restricted => PermissionAccess.denied,
    };
