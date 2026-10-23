import 'package:runiverse/features/matching/domain/room_info.dart';

/// 매칭 스트림이 올려보내는 것.
///
/// 세 가지뿐이다. 서버가 이벤트를 더 쪼개지 않는 이유는 [MatchRoomUpdated]가
/// 방의 전체 상태를 나르기 때문이다 — 무슨 일이 있었는지는 `status`가 말한다.
sealed class MatchEvent {
  const MatchEvent();
}

/// 매칭이 확정된 **그 순간**.
///
/// ## ⚠️ [MatchRoomUpdated]와 나누는 이유
///
/// `status == matched`는 재연결 스냅샷으로도 온다. 그것만 보고 확정 연출을
/// 띄우면 앱을 껐다 켤 때마다 다시 축하하게 된다. **전이는 이 이벤트가,
/// 그 밖의 모든 갱신은 [MatchRoomUpdated]가 맡는다.**
///
/// 모집 마감 시각에 딱 한 번 온다. 자리가 다 차도 앞당겨 오지 않는다.
class MatchStarted extends MatchEvent {
  const MatchStarted(this.room);

  final RoomInfo room;
}

/// 방 정보가 갱신됐다.
///
/// 모집 중 인원 변동, 방 취소, 그리고 **연결 직후 스냅샷**이 전부 이것이다.
/// 받으면 무조건 [room]으로 화면을 다시 그린다.
class MatchRoomUpdated extends MatchEvent {
  const MatchRoomUpdated(this.room);

  final RoomInfo room;
}

/// 곧 시작한다. 발사 타이머를 걸 시점이다.
///
/// ## ⚠️ 정각이 아니라 미리 온다
///
/// 정각에 신호를 보내면 네트워크 지연만큼 참가자마다 출발이 어긋난다. 서버가
/// 리드타임만큼 앞서 보내고 **클라가 타이머로 정각을 맞춘다.**
class RunningReady extends MatchEvent {
  const RunningReady({
    required this.runningRoomId,
    required this.scheduledStartAt,
    required this.startsInMs,
  });

  final int runningRoomId;
  final DateTime scheduledStartAt;

  /// **이 이벤트를 보낸 시점 기준** 시작까지 남은 밀리초.
  ///
  /// 기기 시계를 믿지 않아도 되도록 시각이 아니라 간격으로 온다. 서버가 음수를
  /// `0`으로 눌러 보내므로 `0`은 "시작 시각이 이미 지났다"는 뜻이다.
  final int startsInMs;

  /// 3-2-1을 몇 초부터 보여줄 것인가. 남은 시간이 짧으면 **연출만 줄인다.**
  ///
  /// ⚠️ **발사 시각은 당기지 않는다.** `RUNNING_START`가 [scheduledStartAt]보다
  /// 이르면 서버가 거절한다.
  Duration get countdown {
    const full = Duration(seconds: 3);
    final remaining = Duration(milliseconds: startsInMs);
    return remaining < full ? remaining : full;
  }

  /// 서버가 이 이벤트를 보낸 시각. 기기 시계를 맞추는 데 쓴다.
  ///
  /// 받은 로컬 시각과 비교하면 오차가 나온다 — 그 보정으로 로컬 타이머를
  /// 쓰면서도 기준은 서버에 맞출 수 있다.
  DateTime get serverNow =>
      scheduledStartAt.subtract(Duration(milliseconds: startsInMs));
}
