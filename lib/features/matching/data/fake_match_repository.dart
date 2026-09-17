import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 서버 없이 매칭 등록을 돌려보기 위한 가짜.
///
/// 화면과 실패 분기를 이것으로 검증하고 구현체만 나중에 갈아끼운다.
class FakeMatchRepository implements MatchRepository {
  FakeMatchRepository({
    this.latency = Duration.zero,
    this.roomId = 125,
    this.applyFailure,
    this.cancelFailure,
    this.cooldownUntil,
  });

  final Duration latency;

  /// 신청이 성공했을 때 돌려줄 방 번호.
  int roomId;

  MatchFailure? applyFailure;
  MatchFailure? cancelFailure;

  /// [MatchFailure.cooldown]으로 실패시킬 때 함께 실을 해제 시각.
  DateTime? cooldownUntil;

  /// 마지막으로 신청한 값. **앱이 서버가 준 문자열을 그대로 돌려보내는지**
  /// 확인하는 데 쓴다 — 이 흐름에서 가장 틀리기 쉬운 자리다.
  String? appliedSlotRaw;
  TargetDistance? appliedDistance;

  var cancelCalls = 0;

  @override
  Future<int> apply({
    required String slotRaw,
    required TargetDistance distance,
  }) async {
    await Future<void>.delayed(latency);
    // 실패해도 무엇을 보냈는지는 남긴다 — 실패 경로에서도 값을 확인한다.
    appliedSlotRaw = slotRaw;
    appliedDistance = distance;
    _throwIfSet(applyFailure);
    return roomId;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    await Future<void>.delayed(latency);
    _throwIfSet(cancelFailure);
  }

  void _throwIfSet(MatchFailure? failure) {
    if (failure == null) return;
    throw MatchException(
      failure,
      cooldownUntil: failure == MatchFailure.cooldown ? cooldownUntil : null,
    );
  }
}
