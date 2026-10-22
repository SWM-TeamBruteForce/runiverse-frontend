import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 매칭 신청·취소.
///
/// **방 정보는 여기서 오지 않는다.** 신청이 돌려주는 것은 방 번호뿐이고,
/// 참가자 목록과 모집 마감 시각은 SSE 스트림이 나른다(명세 5-A).
abstract interface class MatchRepository {
  /// 오늘 고를 수 있는 시간대와 그 거리의 대기 인원을 받는다(명세 No 16).
  ///
  /// ⚠️ **거리가 없으면 부를 수 없다.** 서버가 필수로 받고 준 거리만 집계한다.
  /// 거리 없이 전체를 세는 길은 없다.
  ///
  /// ⚠️ 실패는 [SlotLoadException]이다. 신청·취소의 [MatchException]과 섞지
  /// 않는다 — 담기는 자리도 화면에서 하는 일도 다르다.
  Future<List<MatchSlot>> slots({required TargetDistance distance});

  /// 매칭을 신청하고 배정된 방 번호를 받는다.
  ///
  /// [slotRaw]는 [MatchSlot.raw] 그대로다 — 앱이 시각을 조립하지 않는다.
  Future<int> apply({
    required String slotRaw,
    required TargetDistance distance,
  });

  /// 활성 신청 하나를 취소한다. 대기 취소와 방 나가기를 겸한다.
  ///
  /// ⚠️ **러닝이 시작된 뒤에는 쓸 수 없다.** 여기서 끊으면 GPS 트랙과 기록이
  /// 저장되지 않는다 — 종료는 WebSocket이 맡는다.
  Future<void> cancel();
}
