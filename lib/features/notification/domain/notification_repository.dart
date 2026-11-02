import 'package:runiverse/features/notification/domain/notification_page_result.dart';

/// 알림 조회·읽음이 실패하는 이유.
enum NotificationFailure { network, sessionExpired, unknown }

class NotificationException implements Exception {
  const NotificationException(this.failure);

  final NotificationFailure failure;

  @override
  String toString() => 'NotificationException($failure)';
}

/// 알림 목록과 읽음 처리.
abstract interface class NotificationRepository {
  /// 알림 한 페이지. [cursor]가 `null`이면 첫 페이지다.
  ///
  /// ⚠️ **끝은 응답의 `nextCursor`가 정한다.** [limit]보다 적게 와도 다음
  /// 페이지가 있을 수 있다.
  Future<NotificationPageResult> list({String? cursor, int limit});

  /// 전부 읽음으로 바꾼다.
  ///
  /// ⚠️ **항목별 읽음은 없다.** 서버가 지원하지 않는다.
  ///
  /// ⚠️ **반드시 목록 조회 뒤에 부른다.** 먼저 부르면 목록 응답에서 안 읽은
  /// 표시가 사라져 새 알림을 강조할 수 없다.
  ///
  /// 여러 번 불러도 성공한다.
  Future<void> readAll();
}
