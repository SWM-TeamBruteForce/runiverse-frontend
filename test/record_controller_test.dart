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
}
