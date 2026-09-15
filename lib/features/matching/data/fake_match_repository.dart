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

  /// 18:00~22:00, 30분 간격. 명세가 정한 범위 그대로다.
  ///
  /// [now]의 **날짜만** 쓴다. 시각은 슬롯이 정한다 — 서버가 주는 값의 모양을
  /// 흉내 내야 화면이 진짜 응답에서도 같게 그려진다.
  static List<MatchSlot> defaultSlots({DateTime? now}) {
    final today = now ?? DateTime.now();
    return [
      for (var half = 0; half <= 8; half++)
        () {
          final startAt = DateTime(
            today.year,
            today.month,
            today.day,
            18 + half ~/ 2,
            (half % 2) * 30,
          );
          return MatchSlot(
            raw: _isoOf(startAt),
            startAt: startAt,
            // 몇 자리에만 대기자를 둔다. 전부 0이면 "대기 인원" 표시를
            // 시험할 수 없고, 전부 채우면 빈 슬롯을 시험할 수 없다.
            waitingCount: switch (half) {
              2 => 3,
              3 => 1,
              _ => 0,
            },
            selectable: startAt.isAfter(today),
          );
        }(),
    ];
  }

  /// 서버가 쓰는 표기 — 시간대 없는 한국 시각, 초 단위까지.
  static String _isoOf(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}'
        'T${two(time.hour)}:${two(time.minute)}:00';
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

  @override
  Future<List<MatchSlot>> fetchSlots({TargetDistance? distance}) async {
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
