import 'dart:async';

import 'package:runiverse/features/notification/domain/app_notification.dart';
import 'package:runiverse/features/notification/domain/app_stream.dart';

/// 테스트가 알림을 직접 밀어 넣는 [AppStream].
///
/// 버퍼·병합 규칙은 **목록 응답과 이벤트의 도착 순서**가 전부라, 그 순서를
/// 손으로 정할 수 있어야 검증된다. 진짜 서버로는 그 순서를 만들 수 없다.
class FakeAppStream implements AppStream {
  StreamController<AppNotification>? _controller;

  /// 몇 번 붙었는가. **다시 붙는 규칙을 세는 자리다.**
  var connects = 0;

  var closes = 0;

  /// 다음 [connect]가 곧바로 낼 오류. 한 번 쓰면 비워진다.
  Object? failure;

  @override
  Stream<AppNotification> connect() {
    connects++;
    final controller = StreamController<AppNotification>();
    _controller = controller;

    final error = failure;
    if (error != null) {
      failure = null;
      controller.addError(error);
      unawaited(controller.close());
    }
    return controller.stream;
  }

  /// 알림 하나가 도착했다.
  void emit(AppNotification notification) => _controller?.add(notification);

  /// 연결이 끊겼다.
  void breakConnection([
    Object error = const AppStreamException(AppStreamFailure.network),
  ]) {
    _controller?.addError(error);
    unawaited(_controller?.close());
  }

  @override
  Future<void> close() async {
    closes++;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) await controller.close();
  }
}
