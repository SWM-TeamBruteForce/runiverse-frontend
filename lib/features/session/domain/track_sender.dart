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
/// ## ⚠️ ack가 없다. 그래서 끊겼다 붙으면 처음부터 다시 보낸다
///
/// `RUNNING_LOCATION_UPDATE`에 ack가 없어 **서버가 어디까지 받았는지 모른다.**
/// 소켓에 넘겼다는 것도 근거가 못 된다 — 끊기던 순간 날아가던 배치는 그대로
/// 사라진다. 그래서 명세가 **"재연결 시 로컬 트랙 전체를 최초 `sequence`부터
/// 재전송"** 을 정했다(WS 명세 `RUNNING_LOCATION_UPDATE`). 서버가
/// `(방, 사람, sequence)`로 중복을 거르므로 겹치는 것은 공짜다.
///
/// 좌표가 비면 서버가 그 구간을 직선으로 이어 **거리가 실제보다 짧게 나온다.**
/// 뛴 만큼 기록이 안 나오는 것은 되돌릴 수 없다.
///
/// ## ⚠️ 전체를 보내되 한 번에 몰아 보내지 않는다
///
/// 명세가 같은 자리에서 **"한 메시지는 64KB(운영값) 이하여야 하므로 재전송도
/// 한 번에 몰아 보내지 말고 여러 배치로 나눈다"** 고 못 박았다. [batchLimit]과
/// [drainGap]이 그것이다.
///
/// ⚠️ **예전에 전체 재전송이 close code 1009로 끊기고 스스로 증폭했다.**
/// 끊기면 다시 전체를 보내고, 또 끊기는 되풀이였다. 그때 메시지 하나는
/// 한도의 65%였으므로 단일 크기 문제가 아니었다 — 그래서 크기(150점)와
/// **간격(300ms)** 을 둘 다 두고 되돌렸다. 둘 중 하나라도 풀면 그 되풀이가
/// 돌아온다.
class TrackSender {
  TrackSender(this._repository, this._channel);

  final TrackRepository _repository;
  final RunningChannel _channel;

  /// 얼마나 자주 보내나. 명세가 정한 값이다.
  static const _interval = Duration(seconds: 10);

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

  /// 밀린 것을 쏟아낼 때 배치 사이에 두는 간격.
  ///
  /// ## ⚠️ 한 메시지가 작아도 몰아 보내면 끊긴다
  ///
  /// [batchLimit]은 **메시지 하나**의 크기만 정한다. `drain`은 다 보낼 때까지
  /// 반복하므로, 수백 점이 밀려 있으면 41KB짜리 메시지가 **간격 없이 연달아**
  /// 나간다. 414점이면 3개가 한꺼번에, 합쳐서 약 124KB다.
  ///
  /// 실제로 그 상황에서 close code **1009**로 끊겼다. 메시지 하나는 한도의
  /// 65%였으므로 **단일 크기 문제가 아니었다** — 서버가 연달아 받은 것을
  /// 미처 비우지 못한 것으로 본다.
  ///
  /// ⚠️ **서버가 왜 끊는지는 앱이 알 수 없다.** 이 값은 "서버가 한 배치를
  /// 처리할 틈"을 주려는 것이고, 근거는 증상뿐이다. 서버 설정이 확인되면
  /// 그에 맞춰 손봐야 한다.
  static const drainGap = Duration(milliseconds: 300);

  /// 서버의 WS 텍스트 메시지 한도. **한 배치가 이보다 작아야 한다.**
  ///
  /// 서버 설정값이라 앱이 알 수 없다. 백엔드와 맞춘 상수이고, 바뀌면 여기와
  /// [batchLimit]을 함께 손봐야 한다.
  static const serverMessageLimitBytes = 64 * 1024;

  int? _roomId;
  Timer? _timer;

  /// 여기까지 소켓에 넘겼다. 0이면 아직 아무것도 안 보냈다.
  var _lastSent = 0;

  /// **직전 배치를 보내기 전의** 커서. [rewindLast]가 여기로 되돌린다.
  var _sentBefore = 0;

  /// 지금 보내는 중인가. 틱이 겹쳐 같은 좌표를 두 번 읽지 않게 막는다.
  var _sending = false;

  StreamSubscription<WsConnectionState>? _connections;

  /// 테스트와 진단용. 어디까지 보냈다고 보고 있는가.
  int get lastSent => _lastSent;

  /// 보내기 시작한다. 방 번호를 알게 된 뒤에 부른다.
  /// 멈춰 둔 타이머만 다시 세운다. **커서는 그대로 둔다.**
  ///
  /// ⚠️ **[start] 와 다르다.** 그쪽은 재연결용이라 커서를 물러세워 겹쳐 보낸다.
  /// 종료 보류(`RUNNING_GOAL_PENDING`)는 **연결이 살아 있는 채로** 러닝이
  /// 이어지는 것이라, 되감으면 이미 보낸 수백 점을 공짜로 다시 보낸다 —
  /// 큰 배치가 연달아 나가면 1009로 끊긴다(클래스 주석 참조).
  ///
  /// 아직 시작한 적이 없으면 아무것도 하지 않는다.
  ///
  /// ⚠️ **[stop] 뒤에 부르면 아무 일도 일어나지 않는다.** 그쪽이
  /// `_roomId` 를 지우기 때문이다. 잠깐 세웠다 이어 갈 때는 [pauseTimer] 를
  /// 쓴다 — 섞어 쓰면 **좌표가 조용히 안 나간다.**
  void resumeTimer() {
    if (_roomId == null) return;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(flush()));
  }

  /// 타이머만 세운다. **방도 커서도 그대로 둔다** — 곧 [resumeTimer] 로
  /// 이어진다.
  ///
  /// ## ⚠️ [stop] 과 짝이 아니다
  ///
  /// [stop] 은 **해체**다. `_roomId` 와 커서를 지우므로 그 뒤에 [resumeTimer]
  /// 를 불러도 첫 줄에서 돌아선다 — 타이머가 안 서고, **좌표가 영영 안
  /// 나가는데 아무도 모른다.** 일시정지(가이드 2.1)와 종료 보류(3.2)가 둘 다
  /// 그 길이었다.
  void pauseTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void start(int runningRoomId) {
    stop();
    _roomId = runningRoomId;
    _lastSent = 0;
    _sentBefore = 0;
    _timer = Timer.periodic(_interval, (_) => unawaited(flush()));

    // ⚠️ **끊기면 커서를 처음으로 되돌린다**(가이드 2.2). 어디까지 닿았는지
    // 알 길이 없어 전부 다시 보낸다 — 실제로 보내는 것은 다시 붙어
    // `RUNNING_STARTED`를 받은 뒤의 [drain]이다. 순서가 `START` → 좌표다.
    _connections = _channel.states.listen((state) {
      if (state == WsConnectionState.reconnecting ||
          state == WsConnectionState.disconnected) {
        _rewindAll();
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
    _sentBefore = 0;
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
      // ⚠️ **되돌아갈 자리를 남긴다.** 서버가 이 배치를 저장하지 못했다고
      // 답하면([rewindLast]) 여기로 커서를 물려 한 번 더 보낸다.
      _sentBefore = _lastSent;
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

      // ⚠️ **연달아 쏘지 않는다.** 보낸 것이 있으면 한 박자 쉰다 —
      // [drainGap] 참조.
      if (_lastSent != previous) {
        await Future<void>.delayed(drainGap);
      }
    }
  }

  /// 커서를 **직전 배치 앞으로** 물린다. 다음 [flush]·[drain]이 그 배치를
  /// 한 번 더 보낸다.
  ///
  /// ## 왜 전체가 아닌가
  ///
  /// 서버가 저장에 실패했다고 답하는 자리(`RUNNING_TRACK_UNAVAILABLE`)에서
  /// 부른다. 그 답은 **방금 보낸 배치**에 대한 것이라 그만 되돌리면 된다.
  /// [_rewindAll]처럼 처음으로 돌리면, 저장 실패가 10초마다 되풀이되는 동안
  /// 매번 트랙 전체가 다시 나가 **앱이 서버 장애를 키운다** — 전체 재전송이
  /// 1009로 끊기며 스스로 증폭한 적이 있다(클래스 주석).
  ///
  /// ## ⚠️ 보내는 중이면 이번 되돌림은 흘러간다
  ///
  /// [flush]가 끝나며 커서를 앞으로 옮기므로, 겹치면 물려 둔 자리가 덮인다.
  /// 저장 실패는 배치마다 오므로 **다음 오류가 다시 부른다** — 틈을 좁히려고
  /// 잠금을 두기보다 한 박자 늦게 올라가는 쪽을 택했다.
  void rewindLast() {
    // ⚠️ **앞으로 가는 일은 없어야 한다.** [_rewindAll]이 커서를 0으로
    // 돌려놓은 뒤라면 물려 둔 자리가 지금 커서보다 뒤에 있다 — 그대로 쓰면
    // 커서가 **앞으로 뛰어** 아직 안 보낸 좌표를 건너뛴다.
    if (_sentBefore >= _lastSent) return;
    _lastSent = _sentBefore;
    debugPrint('[track] 서버가 저장하지 못했다. 직전 배치를 다시 보낸다');
  }

  /// 커서를 **처음으로** 되돌린다. 다음 [drain]이 로컬 트랙 전체를 다시 보낸다.
  /// ⚠️ **[_sentBefore]는 건드리지 않는다.** 여기서 함께 0으로 돌리면
  /// [rewindLast]의 가드가 닿을 일이 없어져 **죽은 코드가 된다** — 보호가 두
  /// 군데로 갈리면 어느 쪽이 일하는지 테스트로 가릴 수 없다. 뒤에 남은 자리는
  /// 그 가드가 막는다.
  void _rewindAll() {
    if (_lastSent == 0) return;
    _lastSent = 0;
    debugPrint('[track] 끊겼다. 처음부터 다시 보낸다');
  }
}
