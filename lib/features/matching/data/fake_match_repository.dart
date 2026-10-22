import 'package:runiverse/core/utils/kst_time.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/match_repository.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';
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
    List<MatchSlot>? slotList,
  }) : slotList = slotList ?? defaultSlots();

  /// 기본 시간대 셋.
  ///
  /// ## ⚠️ 18:00~22:00을 쓰지 않는다
  ///
  /// 운영값을 가짜에 박으면 이번에 없앤 하드코딩이 테스트 쪽으로 옮겨갈 뿐이다.
  /// **일부러 다른 시각**을 써서, 앱 어딘가가 운영값을 전제하면 테스트가
  /// 깨지게 한다.
  ///
  /// 대기 인원에 **0이 하나 섞여 있다** — "0이면 안 그린다"를 따로 꾸미지 않고
  /// 바로 확인할 수 있다. 합계는 7이다.
  static List<MatchSlot> defaultSlots() => [
    slotAt('10:00', waiting: 3),
    slotAt('10:30', waiting: 0),
    slotAt('11:00', waiting: 4),
  ];

  /// `10:00` 같은 벽시계 시각으로 슬롯 하나를 만든다. **오늘 날짜**를 쓴다.
  static MatchSlot slotAt(
    String hhmm, {
    int waiting = 0,
    bool selectable = true,
  }) {
    final now = KstTime.nowWall();
    final parts = hhmm.split(':');
    final wall = DateTime.utc(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    return MatchSlot(
      raw: KstTime.format(wall),
      startAt: KstTime.toLocal(wall),
      waitingCount: waiting,
      selectable: selectable,
    );
  }

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

  /// 조회가 돌려줄 목록. 테스트가 갈아끼운다.
  List<MatchSlot> slotList;

  /// 조회를 실패시킨다.
  SlotLoadFailure? slotsFailure;

  var slotsCalls = 0;

  /// 마지막으로 조회한 거리. **거리별로 다시 받는지** 확인하는 데 쓴다.
  TargetDistance? slotsDistance;

  @override
  Future<List<MatchSlot>> slots({required TargetDistance distance}) async {
    slotsCalls++;
    slotsDistance = distance;
    await Future<void>.delayed(latency);
    final failure = slotsFailure;
    if (failure != null) throw SlotLoadException(failure);
    return slotList;
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
