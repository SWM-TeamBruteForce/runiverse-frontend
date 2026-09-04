import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/track_repository.dart';

/// 쌓인 좌표를 10초마다 묶어 서버로 보낸다.
///
/// ## 어디까지 보냈는지는 메모리에만 둔다
///
/// DB에 "보냈음" 컬럼을 두면 **"보냈다고 표시됐는데 서버는 못 받은"** 상태가
/// 남고, 그건 복구할 방법이 없다(설계 문서 6절). 재연결은 `WsClient`가
/// 처리하므로 이 객체가 살아 있는 동안 커서도 살아 있다.
///
/// ## ⚠️ ack가 없다. 그래서 겹쳐서 다시 보낸다
///
/// `RUNNING_LOCATION_UPDATE`에 ack가 없어 **서버가 어디까지 받았는지 모른다.**
/// 명세는 그래서 "첫 `sequence`부터 전체 재전송"을 정했지만, 클라가 아는 것이
/// 하나 있다 — **소켓에 넘긴 시점**이다. WebSocket은 TCP 위에 있어 연결이
/// 살아 있는 동안 넘긴 것은 사실상 도착한다. 유실 위험은 끊기던 순간 날아가던
/// 마지막 한두 배치뿐이다.
///
/// 그래서 전체가 아니라 [_overlap]만큼 물러서서 다시 보낸다. 서버가
/// `sequence`로 중복을 거르므로 겹치는 것은 공짜다.
///
/// ⚠️ **겹침을 줄이면 안 된다.** 좌표가 비면 서버가 그 구간을 직선으로 잇고
/// **거리가 실제보다 짧게 나온다.** 뛴 만큼 기록이 안 나오는 것은 되돌릴 수 없다.
class TrackSender {
  TrackSender(this._repository, this._channel);

  final TrackRepository _repository;
  final RunningChannel _channel;

  /// 얼마나 자주 보내나. 명세가 정한 값이다.
  static const _interval = Duration(seconds: 10);

  /// 재연결할 때 물러설 좌표 수. 1초에 하나씩이므로 30초어치다.
  ///
  /// 30초인 이유는 **끊기던 순간 날아가던 배치를 덮기 위해서**다. 배치가
  /// 10초치이므로 마지막 한두 개를 넉넉히 포함한다.
  static const _overlap = 30;

  /// 한 메시지에 실을 최대 좌표 수.
  ///
  /// 몇 분 끊겼다 붙으면 밀린 것이 수백 점이 된다. 한 프레임에 다 실으면
  /// 메시지가 커지고 서버가 거절한다. 10초에 150점씩 보내는 동안 새로
  /// 쌓이는 것은 10점이라 **밀린 것을 따라잡는다.**
  ///
  /// ## ⚠️ 이 값은 바이트 한도에서 역산한 것이다
  ///
  /// 좌표 하나가 JSON으로 **약 285바이트**이고 서버의 WS 텍스트 메시지 한도가
  /// **64KB**다. 200점이면 **56.9KB**로 여유가 13%뿐이라 150으로 낮췄다
  /// (42.8KB, 여유 35%).
  ///
  /// 예전에 200이었을 때 실제로 close code **1009**(메시지 초과)로 끊겼다.
  /// 끊기면 재연결 → [_rewind] → 같은 배치 재전송 → 다시 1009로 **스스로
  /// 증폭한다.** 얇게 두면 안 되는 이유다.
  ///
  /// ⚠️ **[TrackPoint]에 필드를 더하면 점당 크기가 커진다.**
  /// `track_sender_size_test.dart`가 그 순간 깨지도록 상한을 박아 두었다.
  ///
  /// **테스트가 읽는다.** 그래서 공개다 — [lastSent]와 같은 이유다.
  static const batchLimit = 150;

  /// 서버의 WS 텍스트 메시지 한도. **한 배치가 이보다 작아야 한다.**
  ///
  /// 서버 설정값이라 앱이 알 수 없다. 백엔드와 맞춘 상수이고, 바뀌면 여기와
  /// [batchLimit]을 함께 손봐야 한다.
  static const serverMessageLimitBytes = 64 * 1024;

  int? _roomId;
  Timer? _timer;

  /// 여기까지 소켓에 넘겼다. 0이면 아직 아무것도 안 보냈다.
  var _lastSent = 0;

  /// 지금 보내는 중인가. 틱이 겹쳐 같은 좌표를 두 번 읽지 않게 막는다.
  var _sending = false;

  StreamSubscription<WsConnectionState>? _connections;

  /// 테스트와 진단용. 어디까지 보냈다고 보고 있는가.
  int get lastSent => _lastSent;

  /// 보내기 시작한다. 방 번호를 알게 된 뒤에 부른다.
  void start(int runningRoomId) {
    stop();
    _roomId = runningRoomId;
    _lastSent = 0;
    _timer = Timer.periodic(_interval, (_) => unawaited(flush()));

    // ⚠️ **끊겼다 붙으면 커서를 물러세운다.** 끊기던 순간 날아가던 좌표를
    // 다시 보내기 위해서다. 상태가 `connected`로 돌아올 때만 움직인다.
    _connections = _channel.states.listen((state) {
      if (state == WsConnectionState.reconnecting ||
          state == WsConnectionState.disconnected) {
        _rewind();
      }
    });
  }

  /// 멈춘다. 커서는 그대로 두지 않는다 — 다음 러닝은 다른 방이다.
  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_connections?.cancel());
    _connections = null;
    _roomId = null;
    _lastSent = 0;
    _sending = false;
  }

  /// 지금 쌓인 것을 보낸다. 타이머를 기다리지 않고 부를 수 있다.
  ///
  /// 보낼 것이 없으면 아무것도 하지 않는다. **소켓에 못 넘기면 커서를
  /// 옮기지 않는다** — 그래야 다음 틱에 같은 좌표를 다시 시도한다.
  Future<void> flush() async {
    final roomId = _roomId;
    if (roomId == null || _sending) return;

    _sending = true;
    try {
      final points = await _repository.after(
        roomId,
        afterSequence: _lastSent,
        limit: batchLimit,
      );
      if (points.isEmpty) return;

      if (!_channel.sendLocations(points)) {
        // 끊겨 있다. 커서를 그대로 두면 다음 틱이 같은 구간을 다시 집는다.
        debugPrint('[track] 못 보냈다 · ${points.length}점을 다음에 다시 보낸다');
        return;
      }
      _lastSent = points.last.sequence;
    } on Object catch (error) {
      // 저장소가 실패해도 러닝은 계속된다. 다음 틱에 다시 읽는다.
      debugPrint('[track] 좌표를 읽지 못했다 · $error');
    } finally {
      _sending = false;
    }
  }

  /// 남은 것을 **전부** 보낸다. 러닝을 끝내기 직전에 부른다.
  ///
  /// ## ⚠️ [flush] 한 번으로는 부족하다
  ///
  /// 한 번에 [batchLimit]개까지만 실으므로, 밀린 것이 그보다 많으면 남는다.
  /// 그대로 종료하면 **마지막 구간이 서버에 없는 채로 기록이 확정된다** —
  /// 서버는 그 자리를 직선으로 이어 거리를 짧게 잡는다.
  ///
  /// 더 보낼 것이 없거나 소켓에 못 넘길 때까지 반복한다. 한 번에 150개씩
  /// 줄어들므로 30분 러닝(1,800개)이라도 12번이면 끝난다.
  Future<void> drain() async {
    var previous = -1;
    // 커서가 안 움직이면 멈춘다 — 다 보냈거나, 끊겨서 못 보내는 것이다.
    while (_lastSent != previous) {
      previous = _lastSent;
      await flush();
    }
  }

  /// 커서를 [_overlap]만큼 물린다. 0 아래로는 내려가지 않는다.
  void _rewind() {
    if (_lastSent == 0) return;
    final to = _lastSent - _overlap;
    _lastSent = to < 0 ? 0 : to;
    debugPrint('[track] 끊겼다. $_lastSent부터 다시 보낸다');
  }
}
