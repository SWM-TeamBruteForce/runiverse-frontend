import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';

/// `RUNNING_STARTED`가 싣고 오는 **러닝 현재 상태 전부.**
///
/// ## ⚠️ ack의 `data`를 비우는 규칙의 유일한 예외다
///
/// 다른 ack는 몸통이 비어 있다. 이것만 스냅샷을 싣는데, 이유가 분명하다 —
/// **최초 진입과 재연결에 같은 ack를 쓰기** 때문이다. 앱을 껐다 켜면 명단도
/// 거리도 콤보도 전부 없는 채로 다시 붙는데, 그것을 한 번에 되살릴 곳이
/// 여기뿐이다.
///
/// ## 이름과 사진의 유일한 출처다
///
/// `RUNNING_PROGRESS_UPDATED`·`RUNNING_COMBO_UPDATED`는 사람을 `userId`로만
/// 가리킨다. 10초마다 인원수만큼 나가는 메시지에 presigned URL을 실으면
/// payload가 커져서다. 그래서 표시 정보는 이 스냅샷에서 받아 `userId`로 맞춘다.
class RunSnapshot {
  const RunSnapshot({
    required this.runningRoomId,
    required this.players,
    required this.combos,
    this.startedAt,
    this.targetDistanceMeters,
  });

  final int runningRoomId;

  /// 방의 시작 시각. **참가자가 실제로 달리기 시작한 시각이 아니다** —
  /// 그것을 쓰면 같은 방에서도 사람마다 경과 시간이 달라진다.
  ///
  /// 오프셋 없는 한국 시각이라 [KstTime]으로 읽는다.
  final DateTime? startedAt;

  /// 목표 거리. 목표가 없는 솔로 방은 `null`이다.
  final int? targetDistanceMeters;

  /// 방에 남아 있는 참가자 전원. **본인도 들어 있다.**
  ///
  /// ⚠️ 이탈·완주한 사람은 빠지고, **연결만 끊긴 사람은 남는다.**
  final List<RunPlayer> players;

  /// 받는 사람이 낀 콤보 전부. **시작 직후에는 비어 있다** — 아직 아무와도
  /// 이어지지 않았으니 당연하다. 빈 것과 못 읽은 것은 다르다.
  final RunCombo combos;

  /// 명단으로 옮긴다. 이름과 사진이 여기서 나온다.
  List<PartyMember> get roster => [
    for (final player in players)
      PartyMember(
        userId: player.userId,
        nickname: player.nickname,
        profileImageUrl: player.profileImageUrl,
      ),
  ];

  /// 파티원의 진행으로 옮긴다. **[myUserId]는 뺀다** — 내 줄의 거리는 앱이
  /// 잰 값으로 채운다(명세: 화면 표시는 로컬 계산값 우선).
  List<RunProgress> progressOf(String myUserId) => [
    for (final player in players)
      if (player.userId != myUserId)
        RunProgress(
          userId: player.userId,
          distanceMeters: player.distanceMeters,
          targetDistanceMeters: targetDistanceMeters,
          currentPaceSecondsPerKm: player.currentPaceSecondsPerKm,
          paused: player.paused,
        ),
  ];

  /// 스냅샷이 아는 **내 누적 거리.** 명단에 내가 없으면 `null`.
  ///
  /// ⚠️ 이 값은 **복구용이다.** 앱이 이미 재고 있으면 그쪽이 우선이다 — 서버
  /// 누적과 앱 누적은 미세하게 다른데, 화면의 숫자가 왔다 갔다 하면 안 된다.
  int? myDistanceOf(String myUserId) {
    for (final player in players) {
      if (player.userId == myUserId) return player.distanceMeters;
    }
    return null;
  }

  /// 몸통에서 읽는다. **읽을 수 없으면 `null`이다.**
  ///
  /// ⚠️ 던지지 않는다. 스냅샷을 못 읽었다고 러닝을 끊을 수는 없다 — 이름이
  /// 없는 채로 수치만 그리는 편이 낫다.
  static RunSnapshot? of(Map<String, dynamic> data) {
    final roomId = data['runningRoomId'];
    if (roomId is! int) return null;

    final players = data['players'];
    return RunSnapshot(
      runningRoomId: roomId,
      startedAt: KstTime.parse(data['startedAt']),
      targetDistanceMeters: data['targetDistanceMeters'] is int
          ? data['targetDistanceMeters'] as int
          : null,
      players: [
        if (players is List)
          for (final player in players) ?RunPlayer.of(player),
      ],
      // ⚠️ 없거나 못 읽으면 **빈 콤보**다. `null`로 두면 화면이 "모른다"와
      // "아직 없다"를 구분하지 못하는데, 시작 직후는 늘 후자다.
      combos: RunCombo.of({'peers': data['comboPeers']}) ?? const RunCombo([]),
    );
  }
}

/// 스냅샷 속 참가자 한 명. **본인일 수도 있다.**
class RunPlayer {
  const RunPlayer({
    required this.userId,
    required this.nickname,
    required this.distanceMeters,
    this.profileImageUrl,
    this.currentPaceSecondsPerKm,
    this.paused = false,
  });

  final String userId;

  /// 탈퇴한 사람은 서버가 `탈퇴한 사용자`로 준다. 앱이 따로 만들지 않는다.
  final String nickname;

  /// ⚠️ **TTL이 있는 presigned URL이다.** 다음 실행까지 들고 있으면 만료된다.
  final String? profileImageUrl;

  /// 서버가 받은 좌표로 누적한 거리.
  final int distanceMeters;

  final int? currentPaceSecondsPerKm;
  final bool paused;

  static RunPlayer? of(Object? wire) {
    if (wire is! Map) return null;
    final userId = wire['userId'];
    final distance = wire['distanceMeters'];
    if (userId is! String || distance is! int) return null;

    return RunPlayer(
      userId: userId,
      // 이름이 비어 오면 화면이 알아서 대체 문구를 쓴다. 여기서 지어내지 않는다.
      nickname: wire['nickname'] is String ? wire['nickname'] as String : '',
      profileImageUrl: wire['profileImageUrl'] is String
          ? wire['profileImageUrl'] as String
          : null,
      distanceMeters: distance,
      currentPaceSecondsPerKm: wire['currentPaceSecondsPerKm'] is int
          ? wire['currentPaceSecondsPerKm'] as int
          : null,
      paused: wire['paused'] == true,
    );
  }
}
