import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
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
}
