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
  Future<void> cancel();
}
