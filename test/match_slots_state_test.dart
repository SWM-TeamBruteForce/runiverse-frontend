import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/domain/match_slot.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';

/// 거리를 고르면 그 거리의 슬롯을 받는다(설계 5·6절).
///
/// ## ⚠️ 목록은 거리에 딸려 있다
///
/// 한 번의 응답에 그날의 모든 시각이 들어 있으므로 **시간을 고르는 것으로는
/// 부르지 않는다.** 반대로 거리가 바뀌면 숫자가 통째로 달라져 다시 받아야 한다.
void main() {
  late FakeMatchRepository repo;
  late ProviderContainer container;

  ProviderContainer build({Duration latency = Duration.zero}) {
    repo = FakeMatchRepository(latency: latency);
    return ProviderContainer.test(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
    );
  }

  MatchRegisterState read() => container.read(matchRegisterProvider);
  MatchRegisterController notifier() =>
      container.read(matchRegisterProvider.notifier);

  setUp(() => container = build());

  test('거리를 고르면 그 거리로 한 번 부른다', () async {
    await notifier().selectDistance(TargetDistance.km5);

    expect(repo.slotsCalls, 1);
    expect(repo.slotsDistance, TargetDistance.km5);
    expect(read().slots, hasLength(3));
    expect(read().distance, TargetDistance.km5);
  });

  test('거리를 바꾸면 다시 부른다', () async {
    await notifier().selectDistance(TargetDistance.km3);
    await notifier().selectDistance(TargetDistance.km10);

    expect(repo.slotsCalls, 2);
    expect(repo.slotsDistance, TargetDistance.km10);
  });

  test('⚠️ 같은 거리를 다시 눌러도 부른다 — 실패 복구 길이다', () async {
    // 캐시하면 조회가 실패한 사람에게 `다시 시도` 말고 다른 길이 없다.
    await notifier().selectDistance(TargetDistance.km3);
    await notifier().selectDistance(TargetDistance.km3);

    expect(repo.slotsCalls, 2);
  });

  test('⚠️ 시간을 고르는 것으로는 부르지 않는다', () async {
    await notifier().selectDistance(TargetDistance.km3);
    notifier().selectSlot(read().slots.first);

    expect(repo.slotsCalls, 1);
  });

  test('⚠️ 늦게 온 앞 요청이 나중 거리의 답을 덮지 않는다', () async {
    // 칩은 10km인데 숫자는 3km가 되는 것을 막는다(설계 5절).
    container = build(latency: const Duration(milliseconds: 50));
    repo.slotList = [FakeMatchRepository.slotAt('10:00', waiting: 1)];

    final first = notifier().selectDistance(TargetDistance.km3);
    repo.slotList = [
      FakeMatchRepository.slotAt('10:00', waiting: 9),
      FakeMatchRepository.slotAt('10:30', waiting: 9),
    ];
    final second = notifier().selectDistance(TargetDistance.km10);
    await Future.wait([first, second]);

    expect(read().distance, TargetDistance.km10);
    expect(read().slots, hasLength(2), reason: '나중 거리의 답이 남는다');
  });

  test('⚠️ 거리를 바꾸면 고른 시간이 새 목록의 같은 raw로 교체된다', () async {
    // 옛 객체를 그대로 두면 `waitingCount`가 옛 거리의 값으로 남는다(설계 6절).
    await notifier().selectDistance(TargetDistance.km3);
    notifier().selectSlot(read().slots.first);
    expect(read().selected!.waitingCount, 3);

    final raw = read().selected!.raw;
    repo.slotList = [
      MatchSlot(
        raw: raw,
        startAt: read().selected!.startAt,
        waitingCount: 9,
        selectable: true,
      ),
    ];
    await notifier().selectDistance(TargetDistance.km10);

    expect(read().selected!.raw, raw);
    expect(read().selected!.waitingCount, 9);
  });

  test('새 목록에 없으면 선택이 풀린다', () async {
    await notifier().selectDistance(TargetDistance.km3);
    notifier().selectSlot(read().slots.first);

    repo.slotList = [FakeMatchRepository.slotAt('20:00', waiting: 1)];
    await notifier().selectDistance(TargetDistance.km10);

    expect(read().selected, isNull);
  });

  test('새 목록에서 잠겼으면 선택이 풀린다', () async {
    await notifier().selectDistance(TargetDistance.km3);
    final picked = read().slots.first;
    notifier().selectSlot(picked);

    repo.slotList = [picked.closed()];
    await notifier().selectDistance(TargetDistance.km10);

    expect(read().selected, isNull);
  });

  test('⚠️ 조회가 실패하면 목록이 비고 이유가 남는다', () async {
    repo.slotsFailure = SlotLoadFailure.network;

    await notifier().selectDistance(TargetDistance.km3);

    expect(read().slots, isEmpty);
    expect(read().loadFailure, SlotLoadFailure.network);
    // ⚠️ 신청용 실패와 섞이지 않는다 — 섞이면 화면이 스낵바를 띄우고 바로
    // 지워서, 잠긴 이유가 한 프레임 만에 사라진다.
    expect(read().failure, isNull);
  });

  test('⚠️ 다시 고르면 지난 실패가 지워진다', () async {
    repo.slotsFailure = SlotLoadFailure.network;
    await notifier().selectDistance(TargetDistance.km3);

    repo.slotsFailure = null;
    await notifier().selectDistance(TargetDistance.km3);

    expect(read().loadFailure, isNull);
    expect(read().slots, hasLength(3));
  });

  test('⚠️ 받는 중에는 slotsReady가 거짓이다', () async {
    container = build(latency: const Duration(milliseconds: 50));

    final pending = notifier().selectDistance(TargetDistance.km3);
    expect(read().loadingSlots, isTrue);
    expect(read().slotsReady, isFalse);

    await pending;
    expect(read().loadingSlots, isFalse);
    expect(read().slotsReady, isTrue);
  });

  test('⚠️ 전부 마감이면 slotsReady가 거짓이다', () async {
    // 목록은 비지 않았지만 고를 것이 없다. "비었다"와 같은 화면이어야 한다.
    repo.slotList = [
      FakeMatchRepository.slotAt('10:00', selectable: false),
      FakeMatchRepository.slotAt('10:30', selectable: false),
    ];

    await notifier().selectDistance(TargetDistance.km3);

    expect(read().slots, hasLength(2));
    expect(read().slotsReady, isFalse);
  });

  test('waitingTotal은 모든 시각을 더한다', () async {
    // 가짜의 기본 목록 3 + 0 + 4
    await notifier().selectDistance(TargetDistance.km3);

    expect(read().waitingTotal, 7);
  });

  test('⚠️ 거리를 고른 직후 화면을 떠나도 죽지 않는다', () async {
    container = build(latency: const Duration(milliseconds: 20));

    final pending = notifier().selectDistance(TargetDistance.km3);
    container.dispose();

    await expectLater(pending, completes);
  });
}
