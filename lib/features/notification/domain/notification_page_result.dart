import 'package:runiverse/features/notification/domain/app_notification.dart';

/// 알림 목록 한 페이지.
class NotificationPageResult {
  const NotificationPageResult({
    required this.items,
    required this.unreadCount,
    this.nextCursor,
  });

  const NotificationPageResult.empty()
    : items = const [],
      unreadCount = 0,
      nextCursor = null;

  final List<AppNotification> items;

  /// 안 읽은 알림 수. **배지의 바닥값이다.**
  ///
  /// ⚠️ 목록보다 클 수 있다 — 서버가 깨진 행과 초대 행 없는 알림을 건너뛰기
  /// 때문이다. 목록 길이로 배지를 세지 않는다.
  ///
  /// 최근 30일(운영값) 안의 알림만 센다.
  final int unreadCount;

  /// 다음 페이지 커서.
  ///
  /// ## ⚠️ `null`일 때만 끝이다
  ///
  /// [items]가 `limit`보다 적거나 **비어 있어도** 다음 페이지가 있을 수 있다 —
  /// 서버가 건너뛴 행만큼 줄어든다. 개수로 판단하면 목록이 중간에 끊긴다.
  final String? nextCursor;
}
