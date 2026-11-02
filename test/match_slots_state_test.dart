import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/slot_board.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';

/// 매칭 등록 상태 — **한 번 받아 끝이다**(설계 6·7절).
///
/// ## ⚠️ 2026-10-26부터 거리가 조회를 부르지 않는다
///
/// 전에는 조회가 거리를 필수로 받아서, 거리를 고를 때마다 왕복이 한 번씩
/// 일어났다. 그 왕복을 둘러싼 것들 — 거리를 안 골랐는데 마감 여부를 알아야 해서
/// 아무 거리로 묻던 `probeToday`, 거리를 바꾸는 동안 옛 숫자가 새 이름에 붙지
/// 않게 목록을 비우던 절차 — 이 **전제와 함께 사라졌다.**
///
/// 지금 남은 경합은 하나다. **조회 실패 뒤 `다시 시도`를 연타하는 것.**
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

  /// 가짜의 기본 판을 가진 시각 하나. 10:00은 세 거리 합이 5다.
  SlotTime timeAt(String hhmm) => read().board!.times.firstWhere(
    (t) => t.raw == FakeMatchRepository.slotAt(hhmm).raw,
  );

  group('조회', () {
    test('들어올 때 한 번 부르면 판이 선다', () async {
      await notifier().load();

      expect(repo.slotsCalls, 1);
      expect(read().board?.distances.map((d) => d.meters), [3000, 5000, 10000]);
      expect(read().board?.times, hasLength(3));
    });

    test('⚠️ 거리를 고르는 것으로는 부르지 않는다', () async {
      // 이것이 이번 변경의 핵심이다. 판이 이미 다 와 있다.
      await notifier().load();

      notifier().selectDistance(5000);

      expect(repo.slotsCalls, 1);
      expect(read().meters, 5000);
    });

    test('⚠️ 시간을 고르는 것으로도 부르지 않는다', () async {
      await notifier().load();

      notifier().selectTime(timeAt('10:00'));

      expect(repo.slotsCalls, 1);
    });

    test('⚠️ 거리를 바꿔도 고른 시간이 그대로 남는다', () async {
      // 판이 바뀌지 않으므로 갈아 끼울 일이 없다. 전에는 거리마다 목록이 새로
      // 와서 같은 `raw`를 찾아 교체해야 했다.
      await notifier().load();
      notifier().selectTime(timeAt('11:00'));

      notifier().selectDistance(3000);
      notifier().selectDistance(10000);

      expect(read().time, timeAt('11:00'));
      expect(read().meters, 10000);
    });

    test('⚠️ 거리를 먼저 골라도 된다 — 잠그지 않는다', () async {
      // 한 번에 다 받으므로 순서를 강제할 이유가 없다. 등록 버튼만 둘 다
      // 골라야 열린다.
      await notifier().load();

      notifier().selectDistance(5000);

      expect(read().meters, 5000);
      expect(read().canSubmit, isFalse, reason: '시간을 아직 안 골랐다');
    });
  });

  group('조회 실패', () {
    test('⚠️ 실패하면 판이 비고 이유가 남는다', () async {
      repo.slotsFailure = SlotLoadFailure.network;

      await notifier().load();

      expect(read().board, isNull);
      expect(read().loadingSlots, isFalse);
      expect(read().loadFailure, SlotLoadFailure.network);
      expect(read().slotsReady, isFalse);
    });

    test('⚠️ 다시 받으면 지난 실패가 지워진다', () async {
      repo.slotsFailure = SlotLoadFailure.network;
      await notifier().load();

      repo.slotsFailure = null;
      await notifier().load();

      expect(read().loadFailure, isNull);
      expect(read().slotsReady, isTrue);
    });

    test('⚠️ 예상 밖의 예외도 다시 시도할 길을 남긴다', () async {
      // `SlotLoadException`만 잡으면 플랫폼 예외가 `loadingSlots: true`에
      // 영원히 갇히고 `다시 시도` 버튼조차 안 붙는다.
      repo.slotsThrow = StateError('플랫폼 채널이 없다');

      await notifier().load();

      expect(read().loadingSlots, isFalse);
      expect(read().loadFailure, SlotLoadFailure.network);
    });

    test('⚠️ 늦게 온 실패가 먼저 온 성공을 덮지 않는다', () async {
      // `다시 시도`는 실패한 사람이 연타하기 가장 쉬운 버튼이다. 이것이
      // 이번 변경 뒤에도 남는 유일한 경합이다.
      repo.latency = const Duration(milliseconds: 200);
      repo.slotsFailure = SlotLoadFailure.network;
      final slow = notifier().load();

      repo.latency = const Duration(milliseconds: 20);
      repo.slotsFailure = null;
      final fast = notifier().load();

      await Future.wait([slow, fast]);

      expect(read().loadFailure, isNull);
      expect(read().board?.times, hasLength(3));
    });

    test('⚠️ 받는 중에는 slotsReady가 거짓이다', () async {
      container = build(latency: const Duration(milliseconds: 50));
      final pending = notifier().load();

      expect(read().loadingSlots, isTrue);
      expect(read().slotsReady, isFalse);
      await pending;
      expect(read().slotsReady, isTrue);
    });

    test('⚠️ 조회 직후 화면을 떠나도 죽지 않는다', () async {
      container = build(latency: const Duration(milliseconds: 20));
      final pending = notifier().load();
      container.dispose();

      await expectLater(pending, completes);
    });
  });

  group('마감', () {
    test('⚠️ 전부 마감이면 slotsReady가 거짓이다', () async {
      // 목록은 차 있는데 고를 것이 없다. 선택기를 열어 두면 시트에 `마감`만
      // 늘어서고 등록 버튼은 영영 잠긴 채라 고장난 화면으로 읽힌다.
      repo.board = _closedBoard();

      await notifier().load();

      expect(read().slotsReady, isFalse);
      expect(read().closedForToday, isTrue);
    });

    test('⚠️ 조회 전에는 "끝났다"가 아니다', () {
      // 판이 없는 것과 **고를 것이 없는 것**은 다르다. 섞으면 화면에
      // 들어오자마자 팝업이 뜬다.
      expect(read().closedForToday, isFalse);
    });

    test('⚠️ 조회가 실패한 것도 "끝났다"가 아니다', () async {
      // 못 받은 것을 마감으로 읽으면, 서버가 흔들릴 때마다 사람을 홈으로
      // 쫓아낸다.
      repo.slotsFailure = SlotLoadFailure.network;

      await notifier().load();

      expect(read().closedForToday, isFalse);
    });

    test('하나라도 열려 있으면 끝난 것이 아니다', () async {
      await notifier().load();

      expect(read().closedForToday, isFalse);
      expect(read().openTimes, hasLength(3));
    });

    test('열려 있는 시각만 센다', () async {
      repo.board = SlotBoard([
        DistanceSlots(
          meters: 3000,
          slots: [
            FakeMatchRepository.slotAt('10:00', selectable: false),
            FakeMatchRepository.slotAt('10:30'),
            FakeMatchRepository.slotAt('11:00'),
          ],
        ),
      ]);

      await notifier().load();

      expect(read().openTimes, hasLength(2));
    });
  });

  group('등록 버튼의 숫자', () {
    test('고른 시각 × 고른 거리의 수다', () async {
      // 기본 판에서 10:00 × 3km는 3명, 10:00 × 5km는 2명이다. 시트의 합계
      // 5명과 다른 숫자라는 것이 요점이다.
      await notifier().load();
      notifier().selectTime(timeAt('10:00'));

      notifier().selectDistance(3000);
      expect(read().pickedWaiting, 3);

      notifier().selectDistance(5000);
      expect(read().pickedWaiting, 2);
    });

    test('⚠️ 시트의 합계와 다른 숫자다', () async {
      await notifier().load();
      notifier().selectTime(timeAt('10:00'));
      notifier().selectDistance(3000);

      expect(read().time?.waitingTotal, 5, reason: '세 거리를 더한 수');
      expect(read().pickedWaiting, 3, reason: '고른 조건의 수');
    });

    test('하나만 골랐으면 없다', () async {
      await notifier().load();

      notifier().selectTime(timeAt('10:00'));
      expect(read().pickedWaiting, isNull);

      notifier().selectDistance(3000);
      expect(read().pickedWaiting, isNotNull);
    });

    test('⚠️ 없는 조합은 0이 아니라 없음이다', () async {
      // 0으로 뭉개면 고를 수 없는 자리를 `0명 대기`로 그려, 신청할 수 있는
      // 것처럼 말하게 된다.
      await notifier().load();
      notifier().selectTime(timeAt('10:00'));
      notifier().selectDistance(9999);

      expect(read().pickedWaiting, isNull);
      expect(read().canSubmit, isFalse);
    });
  });

  group('등록할 수 있는가', () {
    test('둘 다 골라야 열린다', () async {
      await notifier().load();
      expect(read().canSubmit, isFalse);

      notifier().selectTime(timeAt('10:00'));
      expect(read().canSubmit, isFalse);

      notifier().selectDistance(3000);
      expect(read().canSubmit, isTrue);
    });

    test('⚠️ 고른 칸이 마감이면 잠긴다', () async {
      // 시간 시트는 **하나라도** 열려 있으면 연다. 그래서 열린 시각을 고른
      // 뒤에도 그 거리만 마감일 수 있다 — 그걸 누르면 409를 맞는다.
      repo.board = SlotBoard([
        DistanceSlots(
          meters: 3000,
          slots: [FakeMatchRepository.slotAt('10:00', selectable: false)],
        ),
        DistanceSlots(
          meters: 5000,
          slots: [FakeMatchRepository.slotAt('10:00')],
        ),
      ]);
      await notifier().load();
      notifier().selectTime(timeAt('10:00'));

      notifier().selectDistance(3000);
      expect(read().canSubmit, isFalse, reason: '3km는 마감이다');

      notifier().selectDistance(5000);
      expect(read().canSubmit, isTrue);
    });
  });

  group('신청', () {
    test('⚠️ 서버가 준 문자열·미터값을 그대로 보낸다', () async {
      await notifier().load();
      notifier().selectTime(timeAt('11:00'));
      notifier().selectDistance(10000);

      final roomId = await notifier().submit();

      expect(roomId, repo.roomId);
      expect(repo.appliedSlotRaw, timeAt('11:00').raw);
      expect(repo.appliedMeters, 10000);
    });

    test('⚠️ 신청 중에 거리를 바꿔도 submitting이 풀리지 않는다', () async {
      // 풀리면 CTA가 다시 열려 **같은 신청이 두 번 나간다.**
      await notifier().load();
      notifier().selectTime(timeAt('10:00'));
      notifier().selectDistance(3000);

      repo.latency = const Duration(milliseconds: 100);
      final sending = notifier().submit();
      expect(read().submitting, isTrue);

      notifier().selectDistance(10000);

      expect(read().submitting, isTrue, reason: '아직 보내는 중이다');
      expect(read().canSubmit, isFalse);
      await sending;
    });

    test('⚠️ 409를 맞으면 판을 다시 받고 선택을 푼다', () async {
      // 서버가 준 `selectable`은 **받은 시점의 사진**이라, 화면을 열어 둔
      // 사이 마감이 지날 수 있다. 한 줄만 잠그는 것보다 다시 받는 쪽이
      // 정확하다 — 그사이 마감된 다른 시각도 함께 온다.
      repo.applyFailure = MatchFailure.slotClosed;
      await notifier().load();
      notifier().selectTime(timeAt('10:00'));
      notifier().selectDistance(3000);

      await notifier().submit();

      expect(read().failure, MatchFailure.slotClosed);
      expect(read().time, isNull, reason: '마감된 시각을 고른 채로 두지 않는다');
      expect(repo.slotsCalls, 2, reason: '판을 다시 받는다');
    });

    test('⚠️ 409 뒤 재조회가 실패 문구를 되살리지 않는다', () async {
      // 되살리면 사라졌던 스낵바가 다시 나타나고 타이머가 처음부터 돈다.
      repo.applyFailure = MatchFailure.slotClosed;
      await notifier().load();
      notifier().selectTime(timeAt('10:00'));
      notifier().selectDistance(3000);

      await notifier().submit();
      notifier().clearFailure();
      await Future<void>.delayed(Duration.zero);

      expect(read().failure, isNull);
    });
  });

  group('진입 초기화', () {
    test('⚠️ 다시 들어오면 지난번에 고른 것이 남지 않는다', () async {
      // 상태가 화면을 나가도 죽지 않는다. 남겨두면 **지난번에 누른 거리가
      // 기본값처럼** 선택돼 있고, 그 거리의 낡은 숫자까지 그대로 선다.
      await notifier().load();
      notifier().selectTime(timeAt('10:00'));
      notifier().selectDistance(10000);

      notifier().reset();

      expect(read().board, isNull);
      expect(read().time, isNull);
      expect(read().meters, isNull);
    });

    test('⚠️ 초기화는 서버를 부르지 않는다', () {
      // 부르는 것은 `load()`다. 둘을 한 함수로 묶으면 화면이 초기화만
      // 하고 싶을 때 왕복이 따라온다.
      notifier().reset();

      expect(repo.slotsCalls, 0);
    });

    test('⚠️ 날아오던 답이 비운 화면에 내려앉지 않는다', () async {
      // 조회가 도는 중에 화면을 나갔다 들어오면, 늦게 온 답이 빈 상태를
      // 덮어 지난번 판이 되살아난다.
      container = build(latency: const Duration(milliseconds: 50));
      final pending = notifier().load();

      notifier().reset();
      await pending;

      expect(read().board, isNull);
      expect(read().loadingSlots, isFalse);
    });
  });
}

/// 전부 마감인 판.
SlotBoard _closedBoard() => SlotBoard([
  DistanceSlots(
    meters: 3000,
    slots: [
      FakeMatchRepository.slotAt('10:00', waiting: 3, selectable: false),
      FakeMatchRepository.slotAt('10:30', waiting: 4, selectable: false),
    ],
  ),
]);
