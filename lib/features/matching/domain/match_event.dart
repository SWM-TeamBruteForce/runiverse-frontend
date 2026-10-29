import 'package:runiverse/features/matching/domain/room_info.dart';

/// 매칭 스트림이 올려보내는 것.
///
/// 서버가 이벤트를 많이 쪼개지 않는 이유는 갱신 이벤트가 **방의 전체 상태를
/// 나르기** 때문이다 — 무슨 일이 있었는지는 `status`와 참가자 목록이 말한다.
///
/// ## 방 종류마다 이벤트가 따로 있다
///
/// | | 매칭 방 | 초대 방 |
/// |---|---|---|
/// | 연결 직후 스냅샷 | [MatchRoomUpdated] | [InviteRoomEntrance] |
/// | 갱신 | [MatchRoomUpdated] | [InviteRoomUpdated] |
/// | 확정 연출 | [MatchStarted] | **없다** |
///
/// 둘은 같은 스트림에서 온다. **받는 쪽이 방 종류를 미리 알지 못해도 된다** —
/// 어느 이벤트가 오는지가 그것을 말해 준다.
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

/// 초대 방에 들어왔다. **연결 직후 한 번** 온다.
///
/// 방을 개설한 직후, 초대를 수락한 직후, 그리고 **재연결**마다 온다. 매칭 방의
/// 스냅샷이 [MatchRoomUpdated]인 자리를 초대 방에서는 이것이 맡는다.
///
/// ## ⚠️ 화면은 이벤트 이름이 아니라 `status`로 정한다
///
/// "입장"이라는 이름 때문에 모집 중인 방이라고 단정하면 안 된다. 재연결하면
/// **이미 시작한 방도** 이것으로 온다 — `room.status`가 `started`다.
class InviteRoomEntrance extends MatchEvent {
  const InviteRoomEntrance(this.room, {this.startsInMs});

  final RoomInfo room;

  /// 시작까지 남은 밀리초. **남은 시간 표시에만 쓴다.**
  ///
  /// ⚠️ **발사 타이머의 기준이 아니다.** 출발은 [RunningReady]가 정한다 —
  /// 이 값으로 타이머를 걸면 그 이벤트와 두 벌이 되고, 둘이 어긋나는 날
  /// 참가자마다 출발이 갈린다.
  ///
  /// 못 읽으면 `null`이다. 그때는 `room.scheduledStartAt`으로 그린다.
  final int? startsInMs;
}

/// 초대 방 정보가 갱신됐다.
///
/// 초대 전송·재초대, 수락, 거절, 나가기, 회원 탈퇴 정리, **모집 마감**이
/// 전부 이것이다. 받으면 무조건 [room]으로 다시 그린다.
///
/// ## ⚠️ 모집 마감에 확정 연출이 없다
///
/// 초대 방은 [MatchStarted]를 받지 않는다. 마감은 이 이벤트가 `status: matched`
/// 와 **빈 `invitations`** 로 알리고, 그 뒤 [RunningReady]까지 대기 화면을
/// 유지한다.
///
/// ## 오지 않는 때
///
/// - 409로 막힌 초대 — 아무 일도 일어나지 않았다
/// - 참가자가 0명이 되어 방이 사라질 때 — **받을 사람이 없다**
/// - `started` 전환
class InviteRoomUpdated extends MatchEvent {
  const InviteRoomUpdated(this.room);

  final RoomInfo room;
}

/// 곧 시작한다. 발사 타이머를 걸 시점이다.
///
/// **매칭 방과 초대 방이 같다.** 여기부터 뒤는 갈리지 않는다.
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
