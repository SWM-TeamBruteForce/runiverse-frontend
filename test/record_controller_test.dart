import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 기록 탭의 상태 전이. **달 경계**가 이 화면의 까다로운 지점이다.
void main() {
  // 2026-09-02는 수요일. 이번 주는 8월 31일(월)~9월 6일(일)이라
  // 월요일 하루가 지난달에 걸린다.
  final today = DateTime(2026, 9, 2, 9);

  Future<ProviderContainer> open() async {
    final container = ProviderContainer.test(
      overrides: [
        recordClockProvider.overrideWithValue(() => today),
        runRecordRepositoryProvider.overrideWithValue(
          FakeRunRecordRepository(today: today),
        ),
      ],
    );
    // build가 microtask로 첫 조회를 띄운다. 그것이 끝나기를 기다린다.
    container.read(recordControllerProvider);
    await container.read(recordControllerProvider.notifier).load();
    return container;
  }

  test('처음 열면 이번 달과 오늘이 잡힌다', () async {
    final container = await open();

    final state = container.read(recordControllerProvider) as RecordData;
    expect(state.month, DateTime(2026, 9));
    expect(state.selectedDay, DateTime(2026, 9, 2));
    expect(state.weekDays.first, DateTime(2026, 8, 31), reason: '주는 월요일부터');
  });

  test('같은 달 안에서 고르면 다시 읽지 않는다', () async {
    final container = await open();
    final repository =
        container.read(runRecordRepositoryProvider) as FakeRunRecordRepository;
    final before = repository.calls;

    container
        .read(recordControllerProvider.notifier)
        .select(DateTime(2026, 9, 9));

    final state = container.read(recordControllerProvider) as RecordData;
    expect(state.selectedDay, DateTime(2026, 9, 9));
    expect(state.month, DateTime(2026, 9));
    expect(repository.calls, before, reason: '그 달 기록은 이미 손에 있다');
  });

  test('⚠️ 지난달 날짜를 고르면 캘린더도 그 달로 옮긴다', () async {
    // 주간 막대의 8월 31일을 누른 상황이다. 캘린더가 9월에 머물면 고른 날이
    // 어느 칸에도 표시되지 않아 목록과 캘린더가 서로 다른 말을 한다.
    final container = await open();

    container
        .read(recordControllerProvider.notifier)
        .select(DateTime(2026, 8, 31));
    // 달을 옮기면 새로 읽는다. 끝나기를 기다린다.
    await Future<void>.delayed(Duration.zero);

    final state = container.read(recordControllerProvider) as RecordData;
    expect(state.month, DateTime(2026, 8), reason: '캘린더가 따라오지 않았다');
    expect(
      state.selectedDay,
      DateTime(2026, 8, 31),
      reason: '옮긴 뒤 그 날이 그대로 선택돼 있어야 한다',
    );
  });

  group('⚠️ 한 조회가 31일 상한을 넘지 않는다', () {
    // ⚠️ **이 묶음이 실제 결함을 잡아 만들어졌다.**
    //
    // 서버는 한 번에 **31일 미만**만 준다. 달 하나가 이미 그 상한에 딱 걸리는데
    // 스트립을 덮겠다고 달 양끝에 사흘씩 붙였더니 36일이 됐다 — 기기에서
    // `기록을 불러오지 못했어요` 가 떴다. 가짜 저장소가 상한을 안 봐서
    // **테스트는 1164개가 다 통과했다.**
    //
    // 이제 가짜도 진짜처럼 거절하므로 터지기는 하는데, 터진 자리만 보면
    // 원인이 안 보인다. 여기서 **구간 자체**를 센다.
    for (final month in [DateTime(2026, 10), DateTime(2026, 2)]) {
      test('${month.month}월 — 어느 날을 골라도', () async {
        final container = await open();
        final notifier = container.read(recordControllerProvider.notifier);
        await notifier.load(month: month);

        final last = DateTime(month.year, month.month + 1, 0).day;
        for (final day in [1, 15, last]) {
          notifier.select(DateTime(month.year, month.month, day));
          await Future<void>.delayed(Duration.zero);
        }

        final repository =
            container.read(runRecordRepositoryProvider)
                as FakeRunRecordRepository;
        for (final query in repository.queries) {
          expect(
            query.to.difference(query.from).inDays,
            lessThan(RunRecordRepository.maxRangeDays),
            reason: '${query.from} ~ ${query.to} 가 상한을 넘는다',
          );
        }
      });
    }
  });

  test('달을 옮기면 그 달 1일이 잡힌다', () async {
    final container = await open();

    await container.read(recordControllerProvider.notifier).moveMonth(-1);

    final state = container.read(recordControllerProvider) as RecordData;
    expect(state.month, DateTime(2026, 8));
    expect(state.selectedDay, DateTime(2026, 8), reason: '오늘이 없는 달이다');
  });

  group('주간 스트립은 고른 날을 따라간다', () {
    // ⚠️ **차트와 스트립이 서로 다른 7일을 가리킨다.**
    //
    // 위 주간 차트는 **월~일 고정**이고 아래 스트립은 **오늘 ±3일**이다.
    // 둘 다 오늘만 보고 있어서, 차트에서 다른 날을 눌러도 아래 스트립은
    // 꿈쩍하지 않았다 — 고른 날이 스트립 밖이면 어느 칸도 밝지 않아
    // **두 줄이 서로 다른 말을 한다.**
    //
    // 두 규칙(월~일 / ±3일)은 그대로 두고, 스트립의 **중심만** 옮긴다.
    test('고른 날이 스트립 한가운데에 온다', () async {
      final container = await open();
      container
          .read(recordControllerProvider.notifier)
          .select(DateTime(2026, 9, 10));
      // ⚠️ **기다리지 않는다.** `select` 는 동기다. 여기서 한 틱이라도
      // 주면 `build` 가 띄워 둔 첫 조회가 끝나며 고른 날을 덮어쓴다.
      final state = container.read(recordControllerProvider) as RecordData;
      expect(state.stripDays[3], DateTime(2026, 9, 10), reason: '가운데가 고른 날');
      expect(state.stripDays.first, DateTime(2026, 9, 7));
      expect(state.stripDays.last, DateTime(2026, 9, 13));
    });

    test('⚠️ 차트가 가리키는 주는 그대로다', () async {
      // 스트립만 움직인다. 차트까지 따라가면 `이번 주`라는 뜻이 사라진다.
      final container = await open();
      container
          .read(recordControllerProvider.notifier)
          .select(DateTime(2026, 9, 10));
      // ⚠️ **기다리지 않는다.** `select` 는 동기다. 여기서 한 틱이라도
      // 주면 `build` 가 띄워 둔 첫 조회가 끝나며 고른 날을 덮어쓴다.
      final state = container.read(recordControllerProvider) as RecordData;
      expect(state.weekDays.first, DateTime(2026, 8, 31));
      expect(state.weekDays.last, DateTime(2026, 9, 6));
    });

    test('⚠️ 달 밖으로 넘친 스트립도 받아 온다', () async {
      // 달 1일을 고르면 스트립이 **지난달로 사흘** 넘친다. 월 조회가 그 사흘을
      // 안 덮으므로 따로 받아야 한다.
      final container = await open();
      final notifier = container.read(recordControllerProvider.notifier);
      notifier.select(DateTime(2026, 9, 1));
      await Future<void>.delayed(Duration.zero);

      final repository =
          container.read(runRecordRepositoryProvider)
              as FakeRunRecordRepository;
      expect(
        repository.queries.any((q) => !q.from.isAfter(DateTime(2026, 8, 29))),
        isTrue,
        reason: '8월 29~31일을 받아 온 조회가 없다',
      );
    });

    test('⚠️ 옮긴 스트립의 기록도 들고 있다', () async {
      // 스트립만 옮기고 기록을 안 받아 오면 **뛴 날에 점이 안 찍힌다.**
      // 0 과 모름은 다르다 — 안 뛴 것처럼 보이는 쪽이 더 나쁘다.
      final container = await open();
      final notifier = container.read(recordControllerProvider.notifier);
      // 달 끝으로 간다. 스트립이 다음 달로 3일 넘친다.
      notifier.select(DateTime(2026, 9, 30));

      final state = container.read(recordControllerProvider) as RecordData;
      final repository =
          container.read(runRecordRepositoryProvider)
              as FakeRunRecordRepository;

      // 받아 온 구간 중 하나가 스트립 **전체**를 덮어야 한다.
      expect(
        repository.queries.any(
          (q) =>
              !q.from.isAfter(state.stripDays.first) &&
              !q.to.isBefore(state.stripDays.last),
        ),
        isTrue,
        reason: '${state.stripDays.first}~${state.stripDays.last} 를 덮는 조회가 없다',
      );
    });
  });

  group('⚠️ 앱을 끄지 않고 계정을 바꾸면', () {
    // 이 provider는 로그아웃해도 살아 있다. 처음 한 번만 읽으면 다음 사람에게 앞
    // 사람의 차트·달력·목록이 보이고, 그 기록을 누르면 서버가 403으로 막는다.
    late _AccountRecords records;
    late _Auth auth;

    /// u-1로 로그인해 기록을 한 번 읽어 둔다.
    Future<ProviderContainer> signedIn() async {
      records = _AccountRecords(today);
      final container = ProviderContainer.test(
        overrides: [
          recordClockProvider.overrideWithValue(() => today),
          runRecordRepositoryProvider.overrideWithValue(records),
          authControllerProvider.overrideWith(
            () => _Auth(const AuthSignedIn('u-1', isOnboarded: true)),
          ),
        ],
      );
      auth = container.read(authControllerProvider.notifier) as _Auth;
      container.read(recordControllerProvider);
      await pumpEventQueue();
      return container;
    }

    /// 로그아웃하고 `u-[owner]`로 들어온다.
    void switchTo(int owner) {
      auth.set(const AuthSignedOut(returning: true));
      records.owner = owner;
      auth.set(AuthSignedIn('u-$owner', isOnboarded: true));
    }

    /// 화면에 걸린 기록 번호 — 달력·차트·스트립 전부.
    Set<int> shownIds(ProviderContainer container) {
      final state = container.read(recordControllerProvider) as RecordData;
      return {
        for (final list in state.byDay.values)
          for (final record in list) record.id,
        for (final record in state.allRangeRecords) record.id,
      };
    }

    test('앞 사람 기록을 버리고 새 계정으로 다시 읽는다', () async {
      final container = await signedIn();
      // 기록 탭을 띄워 두었다가, 로그아웃으로 셸이 내려가며 구독이 끊긴다.
      // 구독이 없어도 계정이 바뀐 것은 들어야 한다.
      final tab = container.listen(recordControllerProvider, (_, _) {});
      expect(shownIds(container), {1});
      tab.close();

      final calls = records.calls;
      auth.set(const AuthSignedOut(returning: true));
      await pumpEventQueue();

      expect(
        container.read(recordControllerProvider),
        isA<RecordLoading>(),
        reason: '로그아웃했는데 앞 사람 기록이 남았다',
      );
      expect(records.calls, calls, reason: '로그아웃 상태로는 읽지 않는다');

      records.owner = 2;
      auth.set(const AuthSignedIn('u-2', isOnboarded: true));
      await pumpEventQueue();

      expect(shownIds(container), {2});
    });

    for (final fails in [false, true]) {
      test(
        '⚠️ 바꾸기 전에 떠난 조회가 늦게 ${fails ? '실패해도' : '와도'} 새 계정 기록을 덮지 않는다',
        () async {
          final container = await signedIn();
          // 앞 사람이 지난달로 넘긴 조회가 붙잡혀 있다.
          final held = records.hold = Completer<void>();
          final stale = container
              .read(recordControllerProvider.notifier)
              .moveMonth(-1);
          await pumpEventQueue();
          records.hold = null;

          switchTo(2);
          await pumpEventQueue();
          records.fails = fails;
          held.complete();
          await stale;

          final state = container.read(recordControllerProvider);
          expect(state, isA<RecordData>(), reason: '앞 사람의 실패가 오류 화면을 띄웠다');
          expect(
            (state as RecordData).month,
            DateTime(2026, 9),
            reason: '앞 사람이 넘긴 달로 옮겨 갔다',
          );
          expect(shownIds(container), {2});
        },
      );
    }

    test('⚠️ 바꾸기 전에 떠난 스트립 채우기가 늦게 와도 새 계정 기록에 섞이지 않는다', () async {
      final container = await signedIn();
      final notifier = container.read(recordControllerProvider.notifier);
      // 1일을 고르면 스트립이 지난달로 넘쳐 뒤에서 채운다. 그 조회가 붙잡혀 있다.
      final held = records.hold = Completer<void>();
      notifier.select(DateTime(2026, 9, 1));
      await pumpEventQueue();
      records.hold = null;

      switchTo(2);
      await pumpEventQueue();
      // 새 계정도 같은 날을 고른다 — 스트립이 같아 날짜만으로는 못 거른다.
      notifier.select(DateTime(2026, 9, 1));
      await pumpEventQueue();
      held.complete();
      await pumpEventQueue();

      expect(shownIds(container), {2});
    });

    test('같은 계정으로 다시 들어와도 다시 읽는다', () async {
      final container = await signedIn();
      final calls = records.calls;

      switchTo(1);
      await pumpEventQueue();

      expect(records.calls, calls + 3, reason: '달·주간 차트·스트립');
      expect(shownIds(container), {1});
    });

    test('같은 계정의 프로필만 바뀌면 다시 읽지 않는다', () async {
      // `/me`가 닉네임을 채워 오는 것처럼 같은 사람 안에서 상태만 바뀐다.
      final container = await signedIn();
      final shown = container.read(recordControllerProvider);
      final calls = records.calls;

      auth.set(
        const AuthSignedIn(
          'u-1',
          isOnboarded: true,
          user: CurrentUser(userId: 'u-1', isOnboarded: true, nickname: '애플찬'),
        ),
      );
      await pumpEventQueue();

      expect(records.calls, calls);
      expect(container.read(recordControllerProvider), same(shown));
    });
  });
}

/// 테스트가 로그인 상태를 바꿔 끼우는 컨트롤러.
class _Auth extends AuthController {
  _Auth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  void set(AuthState next) => state = next;
}

/// 계정마다 다른 기록을 주는 저장소. 요청이 떠날 때의 [owner]가 기록 번호가 된다.
class _AccountRecords implements RunRecordRepository {
  _AccountRecords(this._today);

  final DateTime _today;

  /// 지금 로그인한 사람.
  var owner = 1;

  /// 있으면 그때 떠난 요청이 이것을 기다린다.
  Completer<void>? hold;

  /// 붙잡혔던 요청이 풀릴 때 실패로 끝내는가.
  var fails = false;

  var calls = 0;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    final who = owner;
    final gate = hold;
    if (gate != null) {
      await gate.future;
      if (fails) throw const RunRecordException(RunRecordFailure.network);
    }
    return [
      RunRecord(
        id: who,
        runningRoomId: who,
        startedAt: _today,
        distanceMeters: 5020,
        duration: const Duration(minutes: 30),
        averagePace: const Duration(seconds: 358),
        playerCount: 1,
      ),
    ];
  }

  @override
  Future<RunDetail> byRoom(int runningRoomId) async =>
      throw UnimplementedError();
}
