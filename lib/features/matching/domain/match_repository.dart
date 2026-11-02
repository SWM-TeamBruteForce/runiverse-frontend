import 'package:runiverse/features/matching/domain/slot_board.dart';

/// 매칭 신청·취소.
///
/// **방 정보는 여기서 오지 않는다.** 신청이 돌려주는 것은 방 번호뿐이고,
/// 참가자 목록과 모집 마감 시각은 SSE 스트림이 나른다(명세 5-A).
abstract interface class MatchRepository {
  /// 오늘 고를 수 있는 **모든 거리 × 모든 시간대**를 한 번에 받는다(명세 No 16).
  ///
  /// ⚠️ **인자가 없다.** 2026-10-26까지는 거리를 필수로 받아 그 거리의 시간대만
  /// 줬다. 지금은 날짜만 보고 판 전체를 준다 — 그래서 **거리를 고를 때마다 다시
  /// 묻던 왕복이 없다.** 날짜도 보내지 않는다(오늘뿐이다).
  ///
  /// ⚠️ 실패는 [SlotLoadException]이다. 신청·취소의 [MatchException]과 섞지
  /// 않는다 — 담기는 자리도 화면에서 하는 일도 다르다.
  Future<SlotBoard> slots();

  /// 매칭을 신청하고 배정된 방 번호를 받는다.
  ///
  /// [slotRaw]는 `MatchSlot.raw` 그대로다 — 앱이 시각을 조립하지 않는다.
  ///
  /// ⚠️ [meters]는 **응답이 준 미터값 그대로다.** `TargetDistance`를 거치지
  /// 않는다 — 서버가 7km를 추가하면 enum에 없어서 신청할 수 없게 된다.
  Future<int> apply({required String slotRaw, required int meters});

  /// 활성 신청 하나를 취소한다. 대기 취소와 방 나가기를 겸한다.
  ///
  /// ⚠️ **러닝이 시작된 뒤에는 쓸 수 없다.** 여기서 끊으면 GPS 트랙과 기록이
  /// 저장되지 않는다 — 종료는 WebSocket이 맡는다.
  ///
  /// **초대 방 나가기도 이것이다.** 다만 초대 방은 제재가 없어 `cooldownUntil`
  /// 이 생기지 않는다.
  Future<void> cancel();

  /// 초대 방을 연다. 돌려받은 방 번호로 스트림에 붙는다.
  ///
  /// [scheduledStartAt]은 **KST 분 단위 문자열**이고 앱이 만든다 — 매칭과
  /// 갈리는 자리다(저쪽은 서버 문자열을 되돌려 보낸다). 범위는
  /// `InviteLimits.window`가 정한다.
  ///
  /// ⚠️ **쿨다운 중에도 열 수 있다.** 매칭 신청과 다르다.
  ///
  /// 실패는 [InviteException]이다.
  Future<int> createInviteRoom({
    required String scheduledStartAt,
    required int meters,
  });

  /// 친구 한 명을 초대한다.
  ///
  /// ⚠️ **한 번에 한 명이다.** 서버가 `inviteeId` 하나만 받는다 — 여럿을
  /// 고르게 하면 결과를 한 줄씩 보여줄 수 없다.
  ///
  /// ⚠️ **꽉 찬 방에도 보낼 수 있다.** 막히는 것은 상대의 수락이다.
  Future<void> invite({required int roomId, required String inviteeId});

  /// 받은 초대를 수락한다. 돌려받은 방 번호로 스트림에 붙는다.
  ///
  /// ⚠️ **본문이 없다.** 받는 사람은 토큰 주체이고, 같은 방에 초대가 여럿이면
  /// 보낸 사람을 고르지 않는다 — 방 단위로 하나다.
  ///
  /// ⚠️ **수락 뒤에 바로 스트림을 열 수 없다.** `GET /users/me/status`를 다시
  /// 읽어야 `WAITING`·`INVITE`가 되고, 방 화면이 그것을 보고 붙는다.
  Future<int> acceptInvitation(int roomId);

  /// 받은 초대를 거절한다.
  ///
  /// 본문이 없고, 보낸 사람이 여럿이어도 **한 번에 모두** 거절된다.
  /// **마감과 상관없이** 거절할 수 있다.
  Future<void> declineInvitation(int roomId);
}
