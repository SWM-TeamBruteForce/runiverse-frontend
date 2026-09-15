import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 매칭 신청·취소와 시간대 조회.
///
/// **방 정보는 여기서 오지 않는다.** 신청이 돌려주는 것은 방 번호뿐이고,
/// 참가자 목록과 모집 마감 시각은 SSE 스트림이 나른다(명세 5-A).
abstract interface class MatchRepository {
  /// 오늘 고를 수 있는 시간대와 각 시간대의 대기 인원.
  ///
  /// [distance]를 주면 그 거리 조건의 대기자만 센다 — 10km를 고른 사람에게
  /// 3km 대기자 수를 보여주면 사회적 증거가 거짓이 된다.
  Future<List<MatchSlot>> fetchSlots({TargetDistance? distance});

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
