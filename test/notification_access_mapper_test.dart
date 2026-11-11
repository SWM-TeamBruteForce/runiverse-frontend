import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/notification/data/notification_access_mapper.dart';
import 'package:runiverse/features/session/domain/permission_access.dart';

/// 홈 알림 결과 — **FCM 상태를 GA에 실을 값으로 바르게 옮기는가.**
///
/// iOS는 거절해도 `denied`로 온다. 그대로 옮기면 다시 물을 수 없는 기기가
/// 다시 물을 수 있는 것처럼 남는다.
void main() {
  test('허용과 임시 허용은 granted다', () {
    for (final isIos in [false, true]) {
      for (final status in [
        AuthorizationStatus.authorized,
        AuthorizationStatus.provisional,
      ]) {
        expect(
          toNotificationAccess(status, isIos: isIos),
          PermissionAccess.granted,
          reason: '$status isIos=$isIos',
        );
      }
    }
  });

  test('영구 거절은 deniedForever다', () {
    expect(
      toNotificationAccess(AuthorizationStatus.deniedPermanently, isIos: false),
      PermissionAccess.deniedForever,
    );
  });

  test('⚠️ iOS의 denied는 다시 물을 수 없어 deniedForever다', () {
    expect(
      toNotificationAccess(AuthorizationStatus.denied, isIos: true),
      PermissionAccess.deniedForever,
    );
  });

  test('안드로이드의 denied는 denied다', () {
    expect(
      toNotificationAccess(AuthorizationStatus.denied, isIos: false),
      PermissionAccess.denied,
    );
  });

  test('묻고도 정해지지 않았으면 denied다', () {
    for (final isIos in [false, true]) {
      expect(
        toNotificationAccess(AuthorizationStatus.notDetermined, isIos: isIos),
        PermissionAccess.denied,
        reason: 'isIos=$isIos',
      );
    }
  });
}
