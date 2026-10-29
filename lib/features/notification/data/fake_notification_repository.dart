import 'dart:async';

import 'package:runiverse/features/notification/domain/notification_page_result.dart';
import 'package:runiverse/features/notification/domain/notification_repository.dart';

/// 테스트가 응답을 손으로 정하는 [NotificationRepository].
///
/// 버퍼·병합 규칙은 **목록 응답과 이벤트의 도착 순서**가 전부라, 응답을 늦추고
/// 실패시킬 수 있어야 검증된다.
class FakeNotificationRepository implements NotificationRepository {
  /// 커서별로 돌려줄 페이지. `null` 키가 첫 페이지다.
  final Map<String?, NotificationPageResult> pages = {};

  /// 부른 순서. `list`와 `readAll`을 함께 적는다 — **알림함은 그 순서가
  /// 규칙이다**(목록 → 모두 읽음).
  final List<String> callOrder = [];

  /// 요청받은 커서를 순서대로 적는다.
  final List<String?> cursors = [];

  /// 다음 [list]가 던질 오류. 한 번 쓰면 비워진다.
  NotificationFailure? listFailure;

  NotificationFailure? readAllFailure;

  /// 응답을 붙잡아 둔다. 완료는 테스트가 [release]로 푼다.
  var defer = false;
  final List<void Function()> _held = [];

  int get listCalls => callOrder.where((c) => c == 'list').length;
  int get readAllCalls => callOrder.where((c) => c == 'readAll').length;

  @override
  Future<NotificationPageResult> list({String? cursor, int limit = 20}) async {
    callOrder.add('list');
    cursors.add(cursor);

    final failure = listFailure;
    if (failure != null) {
      listFailure = null;
      throw NotificationException(failure);
    }

    final page = pages[cursor] ?? const NotificationPageResult.empty();
    if (!defer) return page;

    // 붙잡아 둔다 — 테스트가 그사이 이벤트를 밀어 넣는다.
    final completer = Completer<NotificationPageResult>();
    _held.add(() => completer.complete(page));
    return completer.future;
  }

  @override
  Future<void> readAll() async {
    callOrder.add('readAll');
    final failure = readAllFailure;
    if (failure != null) {
      readAllFailure = null;
      throw NotificationException(failure);
    }
  }

  /// 붙잡아 둔 응답을 모두 흘려보낸다.
  void release() {
    final held = [..._held];
    _held.clear();
    for (final one in held) {
      one();
    }
  }
}
