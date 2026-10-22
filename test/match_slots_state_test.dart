import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
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
  // `submit()`이 방 번호를 안전 저장소에 남긴다. 바인딩이 없으면 채널 접근에서
  // 죽는다.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMatchRepository repo;
  late ProviderContainer container;

  ProviderContainer build({Duration latency = Duration.zero}) {
    repo = FakeMatchRepository(latency: latency);
    return ProviderContainer.test(
      overrides: [
        matchRepositoryProvider.overrideWithValue(repo),
        // 진짜는 플랫폼 채널을 탄다.
        matchRoomStoreProvider.overrideWithValue(InMemoryMatchRoomStore()),
      ],
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
    //
    // ⚠️ **지연을 다르게 줘야 경합이 생긴다.** 같은 값을 주면 타이머가 만든
    // 순서대로 터져 "늦게 온 앞 요청" 자체가 만들어지지 않는다 — 처음에
    // 그렇게 썼다가, 가드를 지워도 통과하는 테스트를 들고 있었다.
    container = build();
    repo.latency = const Duration(milliseconds: 200);
    repo.slotList = [FakeMatchRepository.slotAt('10:00', waiting: 1)];
    final slow = notifier().selectDistance(TargetDistance.km3);

    repo.latency = const Duration(milliseconds: 20);
    repo.slotList = [
      FakeMatchRepository.slotAt('10:00', waiting: 9),
      FakeMatchRepository.slotAt('10:30', waiting: 9),
    ];
    final fast = notifier().selectDistance(TargetDistance.km10);

    await Future.wait([slow, fast]);

    expect(read().distance, TargetDistance.km10);
    expect(read().slots, hasLength(2), reason: '나중 거리의 답이 남는다');
    expect(read().waitingTotal, 18);
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
  group('⚠️ 검토에서 나온 것들', () {
    test('C1 신청 중에 거리를 바꿔도 submitting이 풀리지 않는다', () async {
      // 풀리면 CTA가 다시 열려 **같은 신청이 두 번 나간다.** `submitting`은
      // 바로 그것을 막으려고 있는 값이다.
      container = build();
      await notifier().selectDistance(TargetDistance.km3);
      notifier().selectSlot(read().slots.first);

      // ⚠️ **순서를 못 박는다.** 둘 다 같은 지연을 주면 어느 쪽이 먼저
      // 끝나는지가 진짜 시계에 달려, 테스트가 절반쯤 깨진다. 가짜가 부를 때
      // 지연을 집어 두므로(`fake_match_repository`) 신청은 느리게, 그다음
      // 조회는 즉시로 둘 수 있다.
      repo.latency = const Duration(milliseconds: 500);
      final sending = notifier().submit();
      expect(read().submitting, isTrue);

      // 거리 칩은 어떤 상태에서도 잠기지 않는다 — 신청 중에도 눌린다.
      repo.latency = Duration.zero;
      await notifier().selectDistance(TargetDistance.km10);

      expect(read().submitting, isTrue, reason: '아직 보내는 중이다');
      expect(read().canSubmit, isFalse);
      await sending;
    });

    test('C2 받는 중에는 합계를 믿을 수 없다', () async {
      // 옛 목록을 들고 있으면 새 거리 이름에 **옛 거리 숫자**가 붙는다.
      container = build(latency: const Duration(milliseconds: 50));
      await notifier().selectDistance(TargetDistance.km3);
      expect(read().waitingTotal, 7);

      final pending = notifier().selectDistance(TargetDistance.km10);

      expect(read().loadingSlots, isTrue);
      expect(read().slots, isEmpty, reason: '옛 거리의 목록을 들고 있지 않는다');
      expect(read().waitingTotal, 0);
      await pending;
    });

    test('I1 ⚠️ 같은 거리를 두 번 눌러도 늦게 온 답이 새 답을 덮지 않는다', () async {
      // 가드가 `state.distance`만 보면 같은 거리끼리는 통과한다. `다시 시도`는
      // 실패한 사람이 연타하기 가장 쉬운 버튼이다.
      container = build();
      repo.latency = const Duration(milliseconds: 200);
      repo.slotsFailure = SlotLoadFailure.network;
      final slow = notifier().selectDistance(TargetDistance.km3);

      repo.latency = const Duration(milliseconds: 20);
      repo.slotsFailure = null;
      final fast = notifier().selectDistance(TargetDistance.km3);

      await Future.wait([slow, fast]);

      expect(read().loadFailure, isNull, reason: '늦게 온 실패가 성공을 덮지 않는다');
      expect(read().slots, hasLength(3));
    });

    test('I3 ⚠️ 전부 마감이면 합계를 세지 않는다', () async {
      // "7명이 기다린다"면서 "신청할 수 있는 시간이 없다"고 하면 고장으로 읽힌다.
      repo.slotList = [
        FakeMatchRepository.slotAt('10:00', waiting: 3, selectable: false),
        FakeMatchRepository.slotAt('10:30', waiting: 4, selectable: false),
      ];

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().slotsReady, isFalse);
      expect(read().waitingTotal, 0, reason: '고를 수 없는 자리의 사람은 세지 않는다');
    });

    test('I4 ⚠️ 예상 밖의 예외도 다시 시도할 길을 남긴다', () async {
      // `SlotLoadException`만 잡으면 플랫폼 예외가 `loadingSlots: true`에
      // 영원히 갇히고 `다시 시도` 버튼조차 안 붙는다.
      repo.slotsThrow = StateError('플랫폼 채널이 없다');

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().loadingSlots, isFalse);
      expect(read().loadFailure, SlotLoadFailure.network);
    });

    test('I5 ⚠️ 409 뒤 재조회가 실패 문구를 되살리지 않는다', () async {
      // 되살리면 화면이 스낵바를 한 번 더 띄운다 — 사라졌다 다시 나타난다.
      repo.applyFailure = MatchFailure.slotClosed;
      await notifier().selectDistance(TargetDistance.km3);
      notifier().selectSlot(read().slots.first);

      await notifier().submit();
      expect(read().failure, MatchFailure.slotClosed);
      notifier().clearFailure();

      // 재조회가 끝날 때까지 돌린다.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(read().failure, isNull, reason: '이미 알린 실패를 다시 세우지 않는다');
      expect(repo.slotsCalls, 2, reason: '목록은 다시 받는다');
    });
  });

  group('마감 안내', () {
    test('⚠️ 받아 보니 전부 마감이면 "오늘은 끝났다"로 본다', () async {
      repo.slotList = [
        FakeMatchRepository.slotAt('10:00', selectable: false),
        FakeMatchRepository.slotAt('10:30', selectable: false),
      ];

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().closedForToday, isTrue);
    });

    test('⚠️ 거리를 고르기 전에는 "끝났다"가 아니다', () {
      // 목록이 비어 있는 것과 **고를 것이 없는 것**은 다르다. 섞으면 화면에
      // 들어오자마자 팝업이 뜬다.
      expect(read().closedForToday, isFalse);
    });

    test('⚠️ 조회가 실패한 것도 "끝났다"가 아니다', () async {
      // 못 받은 것을 마감으로 읽으면, 서버가 흔들릴 때마다 사람을 홈으로
      // 쫓아낸다.
      repo.slotsFailure = SlotLoadFailure.network;

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().closedForToday, isFalse);
    });

    test('하나라도 열려 있으면 끝난 것이 아니다', () async {
      repo.slotList = [
        FakeMatchRepository.slotAt('10:00', selectable: false),
        FakeMatchRepository.slotAt('10:30'),
      ];

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().closedForToday, isFalse);
    });

    test('열려 있는 자리만 센다', () async {
      repo.slotList = [
        FakeMatchRepository.slotAt('10:00', selectable: false),
        FakeMatchRepository.slotAt('10:30'),
        FakeMatchRepository.slotAt('11:00'),
      ];

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().openSlots, hasLength(2));
    });
  });

  group('진입 초기화', () {
    test('⚠️ 다시 들어오면 지난번에 고른 것이 남지 않는다', () async {
      // 상태가 화면을 나가도 죽지 않는다. 남겨두면 **지난번에 누른 거리가
      // 기본값처럼** 선택돼 있고, 그 거리의 낡은 숫자까지 그대로 선다.
      await notifier().selectDistance(TargetDistance.km10);
      notifier().selectSlot(read().slots.first);

      notifier().reset();

      expect(read().distance, isNull);
      expect(read().selected, isNull);
      expect(read().slots, isEmpty);
    });

    test('⚠️ 초기화는 서버를 부르지 않는다', () async {
      // 조회가 거리를 필수로 받는데 거리가 아직 없다. 부를 수 있는 가장
      // 이른 시점은 거리를 고른 순간이다.
      notifier().reset();

      expect(repo.slotsCalls, 0);
    });

    test('⚠️ 날아오던 답이 비운 화면에 내려앉지 않는다', () async {
      // 조회가 도는 중에 화면을 나갔다 들어오면, 늦게 온 답이 빈 상태를
      // 덮어 지난번 거리의 목록이 되살아난다.
      container = build(latency: const Duration(milliseconds: 50));
      final pending = notifier().selectDistance(TargetDistance.km10);

      notifier().reset();
      await pending;

      expect(read().slots, isEmpty);
      expect(read().distance, isNull);
    });
  });

  group('마감 안내', () {
    test('⚠️ 받아 보니 전부 마감이면 "오늘은 끝났다"로 본다', () async {
      repo.slotList = [
        FakeMatchRepository.slotAt('10:00', selectable: false),
        FakeMatchRepository.slotAt('10:30', selectable: false),
      ];

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().closedForToday, isTrue);
    });

    test('⚠️ 거리를 고르기 전에는 "끝났다"가 아니다', () {
      // 목록이 비어 있는 것과 **고를 것이 없는 것**은 다르다. 섞으면 화면에
      // 들어오자마자 팝업이 뜬다.
      expect(read().closedForToday, isFalse);
    });

    test('⚠️ 조회가 실패한 것도 "끝났다"가 아니다', () async {
      // 못 받은 것을 마감으로 읽으면, 서버가 흔들릴 때마다 사람을 홈으로
      // 쫓아낸다.
      repo.slotsFailure = SlotLoadFailure.network;

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().closedForToday, isFalse);
    });

    test('하나라도 열려 있으면 끝난 것이 아니다', () async {
      repo.slotList = [
        FakeMatchRepository.slotAt('10:00', selectable: false),
        FakeMatchRepository.slotAt('10:30'),
      ];

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().closedForToday, isFalse);
    });

    test('열려 있는 자리만 센다', () async {
      repo.slotList = [
        FakeMatchRepository.slotAt('10:00', selectable: false),
        FakeMatchRepository.slotAt('10:30'),
        FakeMatchRepository.slotAt('11:00'),
      ];

      await notifier().selectDistance(TargetDistance.km3);

      expect(read().openSlots, hasLength(2));
    });
  });
}
