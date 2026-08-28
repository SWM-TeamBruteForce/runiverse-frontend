import 'package:runiverse/features/session/domain/track_point.dart';

/// 서버로 보낼 좌표를 잠시 맡아 둔다.
///
/// **기록 저장소가 아니다.** 러닝 기록의 원본은 서버이고, 여기 남는 것은
/// 아직 서버가 받았는지 모르는 좌표뿐이다. 다 보내고 `RUNNING_FINISHED` ack를
/// 받으면 [clear]로 지운다.
///
/// ## 왜 메모리로는 안 되나
///
/// 앱이 죽었다 살아나도 트랙이 남아야 재전송이 된다. 러닝 중에 앱이 백그라운드로
/// 밀려 OS에 회수되는 일은 드물지 않다.
abstract interface class TrackRepository {
  /// 좌표 하나를 쌓는다.
  ///
  /// **같은 `sequence`를 두 번 넣어도 죽지 않는다** — DB가 덮어쓴다.
  /// 재시도 경로에서 중복 저장이 생겨도 안전해야 한다.
  Future<void> add(int runningRoomId, TrackPoint point);

  /// [afterSequence]보다 큰 좌표를 순서대로 읽는다.
  ///
  /// [limit]을 두는 이유는 **재전송 때문**이다. 30분 러닝이면 1,800점이라
  /// 한 프레임에 다 실으면 200KB가 넘는다. 나눠 보내도 서버가 `sequence`로
  /// 거르므로 안전하다.
  Future<List<TrackPoint>> after(
    int runningRoomId, {
    int afterSequence = 0,
    int limit = 100,
  });

  /// 그 러닝의 좌표를 전부 지운다. `RUNNING_FINISHED` ack 뒤에 부른다.
  ///
  /// ⚠️ **남겨두면 기록이 두 벌이 된다.** 서버가 원본이라는 원칙이 깨진다.
  Future<void> clear(int runningRoomId);

  /// 그 러닝에 쌓인 좌표 수. 비어 있으면 0.
  Future<int> count(int runningRoomId);

  /// 지금 진행 중인 러닝의 방 번호. 없으면 `null`.
  ///
  /// 앱이 죽었다 살아났을 때 **끝내지 못한 방이 있는지** 알아내는 유일한
  /// 경로다. 서버에는 되찾을 API가 없다 — `POST /solo`의 409에는 번호가 없고
  /// `GET /users/me/running-match`는 매칭 조회라 `STARTED`를 표현하지 못한다
  /// (`AppDatabase.activeRun` 참조).
  Future<int?> activeRoom();

  /// 방을 연 직후 번호를 남긴다.
  ///
  /// ⚠️ **좌표가 하나도 없어도 남긴다.** 방만 만들고 죽는 경우가 가장 풀기
  /// 어렵다 — 트랙이 비어 있어 거기서도 번호를 되찾을 수 없다.
  Future<void> markActiveRoom(int runningRoomId);

  /// `RUNNING_FINISHED` ack 뒤에 지운다.
  ///
  /// ⚠️ **좌표와 같은 순간에 지운다.** 한쪽만 지워지면 다음 러닝에서 이미
  /// 끝난 방을 다시 끝내려 하거나, 끝내야 할 방을 잊는다.
  Future<void> clearActiveRoom();
}
