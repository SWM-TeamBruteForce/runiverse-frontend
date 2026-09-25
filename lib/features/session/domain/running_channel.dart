import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/track_point.dart';

/// 러닝 중 서버와 주고받는 것.
///
/// 화면은 이 타입에만 기대고 WebSocket을 모른다.
///
/// ## ⚠️ 일시정지·재개는 아직 없다
///
/// `RUNNING_PAUSE` · `RUNNING_RESUME`은 아직 붙이지 않았다. 서버는 받지만
/// 앱의 일시정지는 지금 화면 상태일 뿐이라 서버에 알릴 것이 없다.
abstract interface class RunningChannel {
  /// 지금 연결 상태.
  Stream<WsConnectionState> get states;

  WsConnectionState get state;

  /// 서버가 거절했을 때. **연결은 유지된다.**
  Stream<WsErrorCode> get errors;

  /// 러닝의 현재 상태 전부. **`RUNNING_START`를 보낼 때마다 한 번씩 온다** —
  /// 최초 진입이든 재연결이든 같다.
  ///
  /// 이름·사진은 여기에만 있다. 진행·콤보 통지는 사람을 `userId`로만 가리킨다.
  Stream<RunSnapshot> get snapshots;

  /// 파티원 한 명의 진행이 바뀔 때마다.
  ///
  /// ⚠️ **갱신된 사람만 온다.** 전원 스냅샷이 아니라서 받는 쪽이 참가자별
  /// 최신값을 들고 이것으로 덮어야 한다. 솔로 러닝에는 오지 않는다.
  Stream<RunProgress> get progress;

  /// 콤보가 바뀔 때마다. **받을 때마다 통째로 갈아끼운다** — 끊긴 상대는
  /// 목록에서 빠지고, 끊김을 알리는 별도 이벤트가 없다.
  Stream<RunCombo> get combos;

  /// 붙고 `RUNNING_START`를 보낸다.
  ///
  /// **최초 진입과 재연결을 구분하지 않는다** — 서버가 같은 메시지로 둘 다
  /// 받고 멱등하게 처리한다. 그래서 재연결 후에도 이걸 다시 보내면 된다.
  ///
  /// 솔로 방은 이 첫 요청이 방을 `MATCHED → STARTED`로 바꾼다.
  Future<void> start(int runningRoomId);

  /// 좌표 묶음을 보낸다. **소켓에 넘겼으면 `true`.**
  ///
  /// ## ⚠️ ack가 없다
  ///
  /// `true`는 "서버가 받았다"가 아니라 **"소켓에 넘겼다"**는 뜻이다. 명세가
  /// 이 메시지에 ack를 두지 않았다. 그래서 재연결하면 겹쳐서 다시 보낸다.
  ///
  /// `false`를 무시하고 커서를 앞으로 옮기면 그 구간이 영영 안 간다.
  bool sendLocations(List<TrackPoint> points);

  /// 러닝을 끝낸다. **`RUNNING_FINISHED` ack를 받으면 `true`.**
  ///
  /// ## ack가 이 메시지에만 있다
  ///
  /// 좌표에는 ack가 없어 "서버가 받았다"를 알 수 없지만, 종료는 확인이 온다.
  /// **그 확인이 로컬 트랙을 지워도 되는지의 유일한 근거다** — 못 받았는데
  /// 지우면 서버에 없는 구간을 다시 보낼 방법이 사라진다.
  ///
  /// [forced]는 **조기 종료 의사**다. 목표를 채우기 전에 그만두는 경우인데,
  /// 솔로 러닝은 목표가 없어 항상 `false`다. 매칭 러닝이 붙을 때 쓴다.
  ///
  /// 멱등이다. 이미 확정된 러닝에 다시 보내도 서버가 기록을 덮어쓰지 않고
  /// ack만 다시 준다.
  Future<bool> finish({bool forced = false});

  /// 스스로 끊는다. 재연결하지 않는다.
  Future<void> close();
}
