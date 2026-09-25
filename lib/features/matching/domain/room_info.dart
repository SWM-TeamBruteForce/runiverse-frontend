import 'package:runiverse/features/session/domain/user_status.dart';

/// 방이 어느 단계인가.
///
/// 화면을 가르는 값이다 — 잘못 읽으면 취소된 방의 대기실에 사람을 묶어두거나,
/// 이미 시작한 러닝을 놓친다.
enum RoomStatus {
  /// 모집 중. 대기 화면에서 인원과 마감 시각을 갱신한다.
  matching,

  /// 확정됐다. 대기방.
  matched,

  /// 이미 시작한 방이다. 재연결 스냅샷으로 온다.
  started,

  finished,

  /// 참가자가 모두 빠졌다. 홈으로.
  cancelled;

  /// 서버 값을 읽는다. **모르는 값이면 `null`이다.**
  ///
  /// ⚠️ 아무 값으로도 뭉개지 않는다. `matching`으로 읽으면 취소된 방의
  /// 대기실에 사람을 묶어두고, `cancelled`로 읽으면 멀쩡한 방에서 쫓아낸다.
  /// 받는 쪽이 이벤트를 버리는 편이 낫다.
  static RoomStatus? of(Object? wire) => switch (wire) {
    'MATCHING' => RoomStatus.matching,
    'MATCHED' => RoomStatus.matched,
    'STARTED' => RoomStatus.started,
    'FINISHED' => RoomStatus.finished,
    'CANCELLED' => RoomStatus.cancelled,
    _ => null,
  };
}

/// 방에 있는 사람 하나.
///
/// ⚠️ **GPS·경로는 여기 없다.** 파티원에게 위치를 드러내지 않는 것이 정책이라
/// 서버도 내려주지 않는다.
class RoomPlayer {
  const RoomPlayer({
    required this.userId,
    required this.nickname,
    required this.isDeleted,
    this.profileImageUrl,
    this.introduction,
    this.averagePaceSecondsPerKm,
  });

  final String userId;
  final String nickname;

  /// 탈퇴한 사람.
  ///
  /// **목록에서 빼지 않는다.** 빼면 인원 수가 방과 어긋난다. 서버가 닉네임과
  /// 사진을 이미 익명 처리해서 준다.
  final bool isDeleted;

  final String? profileImageUrl;
  final String? introduction;
  final int? averagePaceSecondsPerKm;
}

/// 매칭방 전체 정보. **두 SSE 이벤트가 이 구조를 그대로 싣는다.**
///
/// 변경분이 아니라 **항상 전체 상태**다. 받으면 통째로 다시 그리면 된다 —
/// 무슨 일이 있었는지는 [status]와 [players]가 말해준다.
class RoomInfo {
  const RoomInfo({
    required this.runningRoomId,
    required this.status,
    required this.scheduledStartAt,
    required this.players,
    this.closeAt,
    this.targetDistanceMeters,
    this.teamAveragePaceSecondsPerKm,
  });

  final int runningRoomId;
  final RoomStatus status;

  /// 출발 시각. **카운트다운의 기준이다.**
  final DateTime scheduledStartAt;

  /// 모집 마감 시각. `scheduledStartAt`에서 운영 오프셋(현재 10분)을 뺀 값이다.
  ///
  /// ⚠️ **앱이 계산하지 않는다.** 오프셋은 운영값이라 언제든 바뀐다.
  final DateTime? closeAt;

  final int? targetDistanceMeters;
  final int? teamAveragePaceSecondsPerKm;

  final List<RoomPlayer> players;

  /// 상태 조회만으로 세운 방. **스냅샷이 없을 때의 대타다.**
  ///
  /// 확정된 방인데 스트림이 스냅샷을 주지 못하는 경우가 있다 — 옛 방을 대신
  /// 주거나(2026-09-18 실측), 연결이 늦거나. 그때 홈이 아무것도 못 그리면
  /// 사용자는 확정된 러닝에 들어갈 길을 잃는다. 상태 조회는 방 번호와 시작
  /// 시각을 알고 있으므로 그것만으로 카운트다운과 입장 버튼을 세운다.
  ///
  /// ⚠️ **참가자는 비어 있다.** 이름도 인원도 스냅샷에만 있다 — 화면은 이
  /// 목록이 비면 인원 줄을 아예 그리지 않는다. 0명이라고 적으면 거짓이다.
  static RoomInfo? fromStatus(UserStatus? status) => switch (status) {
    UserStatusReady(isSolo: false) => RoomInfo(
      runningRoomId: status.runningRoomId,
      status: RoomStatus.matched,
      scheduledStartAt: status.scheduledStartAt,
      targetDistanceMeters: status.targetDistanceMeters,
      players: const [],
    ),
    _ => null,
  };

  /// 혼자 확정된 방인가. **나가도 제재가 없다.**
  bool get isAlone => players.length <= 1;
}
