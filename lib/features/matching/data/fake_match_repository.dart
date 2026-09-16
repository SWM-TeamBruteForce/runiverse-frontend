import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';

/// 서버 없이 매칭 등록을 돌려보기 위한 가짜.
///
/// **서버가 아직 없다.** 명세는 확정됐지만 11·14번은 배포되지 않아, 화면과
/// 실패 분기는 이것으로 검증하고 구현체만 나중에 갈아끼운다.
class FakeMatchRepository implements MatchRepository {
  FakeMatchRepository({
    List<MatchSlot>? slots,
    this.latency = Duration.zero,
    this.roomId = 125,
    this.applyFailure,
    this.slotsFailure,
    this.cancelFailure,
    this.cooldownUntil,
  }) : slots = slots ?? defaultSlots();

  /// 18:00~22:00, 30분 간격에 대기 인원을 얹는다.
  ///
  /// 목록 자체는 [MatchSlot.todayRange]가 만든다 — 진짜 서버가 없을 때 앱이
  /// 쓰는 것과 같은 값이어야 화면이 실제와 같게 그려진다.
  static List<MatchSlot> defaultSlots({DateTime? now}) {
    final today = now ?? KstTime.nowWall();
    final slots = MatchSlot.todayRange(nowWall: today);
    return [
      for (var i = 0; i < slots.length; i++)
        MatchSlot(
          raw: slots[i].raw,
          startAt: slots[i].startAt,
          // 몇 자리에만 대기자를 둔다. 전부 0이면 "대기 인원" 표시를
          // 시험할 수 없고, 전부 채우면 빈 슬롯을 시험할 수 없다.
          waitingCount: switch (i) {
            2 => 3,
            3 => 1,
            _ => 0,
          },
          selectable: slots[i].selectable,
        ),
    ];
  }

  /// 답할 목록. **`final`이 아니다** — 마감 경합 뒤에 목록을 다시 받는
  /// 흐름을 만들려면 같은 인스턴스가 답을 바꿔야 한다.
  List<MatchSlot> slots;

  final Duration latency;

  /// 신청이 성공했을 때 돌려줄 방 번호.
  int roomId;

  MatchFailure? applyFailure;
  MatchFailure? slotsFailure;
  MatchFailure? cancelFailure;

  /// [MatchFailure.cooldown]으로 실패시킬 때 함께 실을 해제 시각.
  DateTime? cooldownUntil;

  /// 마지막으로 신청한 값. **앱이 서버가 준 문자열을 그대로 돌려보내는지**
  /// 확인하는 데 쓴다 — 이 흐름에서 가장 틀리기 쉬운 자리다.
  String? appliedSlotRaw;
  TargetDistance? appliedDistance;

  var cancelCalls = 0;

  /// 시간대를 몇 번 받아왔는가. **거리를 고칠 때 다시 받는지** 세는 데 쓴다.
  var slotsCalls = 0;

  @override
  Future<List<MatchSlot>> fetchSlots({TargetDistance? distance}) async {
    slotsCalls++;
    await Future<void>.delayed(latency);
    _throwIfSet(slotsFailure);
    return slots;
  }

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
