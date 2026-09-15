import 'dart:async';

import 'package:runiverse/features/matching/domain/match_event.dart';
import 'package:runiverse/features/matching/domain/match_stream.dart';

/// 서버 없이 매칭 흐름을 돌려보기 위한 가짜.
///
/// 이벤트를 손으로 밀어 넣을 수 있어야 한다 — 확정 통지가 도착했을 때 화면이
/// 어떻게 바뀌는지가 이 구간에서 가장 다루기 어려운 자리다.
class FakeMatchStream implements MatchStream {
  FakeMatchStream({this.failure});

  /// 주면 연결하자마자 그 이유로 끊는다.
  MatchStreamFailure? failure;

  StreamController<MatchEvent>? _controller;

  /// 몇 번 붙었는가. **신청 응답을 받은 뒤에만 붙는지** 세는 데 쓴다.
  var connects = 0;

  var closes = 0;

  /// 지금 붙어 있는가.
  bool get isConnected => _controller?.isClosed == false;

  @override
  Stream<MatchEvent> connect() {
    connects++;
    final controller = StreamController<MatchEvent>.broadcast();
    _controller = controller;

    final reason = failure;
    if (reason != null) {
      // 구독자가 붙을 틈을 준다. 곧바로 넣으면 아무도 못 받는다.
      scheduleMicrotask(() {
        if (controller.isClosed) return;
        controller.addError(MatchStreamException(reason));
        controller.close();
      });
    }
    return controller.stream;
  }

  /// 서버가 이벤트를 보낸 것처럼 민다.
  void emit(MatchEvent event) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(event);
  }

  /// 서버가 끊은 것처럼 만든다.
  void breakDown([MatchStreamFailure reason = MatchStreamFailure.network]) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.addError(MatchStreamException(reason));
    controller.close();
  }

  @override
  Future<void> close() async {
    closes++;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) await controller.close();
  }
}
