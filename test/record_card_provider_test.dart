import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

final _today = DateTime(2026, 11, 16);

class _Auth extends AuthController {
  _Auth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  void set(AuthState next) => state = next;
}

/// 그날 뛴 기록만 돌려주는 작은 저장소. 가짜 저장소는 "오늘" 기준으로 목
/// 데이터를 만들어 어느 날에 기록이 있는지 단정할 수 없다.
class _Records implements RunRecordRepository {
  _Records(this.days);

  /// 기록이 있는 날들.
  final Set<DateTime> days;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final day in days)
      if (!day.isBefore(from) && !day.isAfter(to))
        RunRecord(
          id: day.day,
          runningRoomId: day.day + 900,
          startedAt: DateTime(day.year, day.month, day.day, 8),
          distanceMeters: 5000,
          duration: const Duration(minutes: 30),
          averagePace: const Duration(minutes: 6),
          playerCount: 1,
        ),
  ];

  @override
  Future<Never> byRoom(int runningRoomId) =>
      throw UnimplementedError('이 테스트는 상세를 부르지 않는다');
}

/// 러닝 기록 조회가 늘 실패하는 저장소.
class _FailingRecords implements RunRecordRepository {
  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => throw const RunRecordException(RunRecordFailure.network);

  @override
  Future<Never> byRoom(int runningRoomId) =>
      throw UnimplementedError('이 테스트는 상세를 부르지 않는다');
}

/// 떠난 조회가 끝날 때까지 기다린다. 가짜는 지연이 0이라 한 바퀴면 된다.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeRecordCardRepository fake;
  late ProviderContainer container;
  late _Auth auth;

  ProviderContainer build({
    FakeRecordCardRepository? repository,
    RunRecordRepository? records,
  }) {
    fake = repository ?? FakeRecordCardRepository(today: _today);
    auth = _Auth(const AuthSignedIn('u-1', isOnboarded: true));
    final made = ProviderContainer(
      overrides: [
        recordCardRepositoryProvider.overrideWithValue(fake),
        // ⚠️ 달력이 러닝 기록도 받는다. 실제 구현을 그대로 두면 테스트가
        // dio와 토큰 저장소를 끌어온다.
        runRecordRepositoryProvider.overrideWithValue(
          records ?? _Records(const {}),
        ),
        recordCardClockProvider.overrideWithValue(() => _today),
        authControllerProvider.overrideWith(() => auth),
      ],
    );
    addTearDown(made.dispose);
    // 구독이 있어야 build가 돈다.
    made.listen(recordCardControllerProvider, (_, _) {});
    return made;
  }

  test('처음 열면 최근 세 달을 받는다', () async {
    container = build();
    await _settle();

    expect(fake.queries, hasLength(3));
    final data = container.read(recordCardControllerProvider) as RecordCardData;
    // ⚠️ `visible`이 아니라 `months`를 본다 — 보이는 쪽은 카드가 없는 가장
    // 오래된 달을 잘라 내므로 "무엇을 받아 왔나"를 말해 주지 못한다.
    expect(data.months.map((m) => m.month), [
      DateTime(2026, 9),
      DateTime(2026, 10),
      DateTime(2026, 11),
    ]);
  });

  test('⚠️ 달마다 따로 묻는다 — 한 번에 31일을 넘기면 서버가 400을 준다', () async {
    container = build();
    await _settle();

    for (final query in fake.queries) {
      expect(
        query.to.difference(query.from).inDays,
        lessThan(RecordCardRepository.maxRangeDays),
      );
    }
  });

  test('더 받으면 더 과거 세 달만 묻는다', () async {
    container = build();
    await _settle();

    await container.read(recordCardControllerProvider.notifier).loadOlder();

    expect(fake.queries, hasLength(6));
    final data = container.read(recordCardControllerProvider) as RecordCardData;
    expect(data.months.first.month, DateTime(2026, 6));
    expect(data.months, hasLength(6));
    // 받아 온 빈 달은 화면에 세우지 않는다.
    expect(data.visible.first.month, DateTime(2026, 10));
  });

  test('⚠️ 연달아 더 받으라고 해도 한 번만 나간다', () async {
    // 달력이 바닥에 닿으면 스크롤하는 내내 매 프레임 부른다. 막지 않으면
    // 요청이 쏟아지고 목록이 계속 다시 그려져 **스크롤이 멈춰 보인다.**
    container = build();
    await _settle();
    final before = fake.calls;

    final controller = container.read(recordCardControllerProvider.notifier);
    await Future.wait([
      controller.loadOlder(),
      controller.loadOlder(),
      controller.loadOlder(),
    ]);

    expect(fake.calls - before, 3);
  });

  test('⚠️ 더 받을 것이 없으면 그만둔다 — 빈 달을 끝없이 붙이지 않는다', () async {
    container = build();
    await _settle();

    // 가짜는 두 달치뿐이다. 과거로 계속 파고들면 빈 달만 돌아온다.
    final controller = container.read(recordCardControllerProvider.notifier);
    await controller.loadOlder();
    final afterFirst = fake.calls;
    await controller.loadOlder();
    await controller.loadOlder();

    expect(fake.calls, afterFirst, reason: '빈 묶음을 받고도 또 물었다');
  });

  test('⚠️ 더 받다 실패해도 들고 있던 달력을 버리지 않는다', () async {
    // 지하철에서 한 번 끊겼다고 잘 보던 여섯 달이 사라지면 안 된다.
    container = build();
    await _settle();
    final before = container.read(recordCardControllerProvider);
    expect(before, isA<RecordCardData>());

    fake.failWith = RecordCardFailure.network;
    await container.read(recordCardControllerProvider.notifier).loadOlder();

    final after = container.read(recordCardControllerProvider);
    expect(after, isA<RecordCardData>(), reason: '오류 화면으로 갈아치웠다');
    expect((after as RecordCardData).months, hasLength(3));
  });

  test('⚠️ 더 과거가 비어도 force면 한 번 더 판다', () async {
    // 석 달을 통째로 쉰 사람의 그 앞이 영영 안 보이면 안 된다.
    container = build();
    await _settle();
    final controller = container.read(recordCardControllerProvider.notifier);

    await controller.loadOlder();
    expect(
      (container.read(recordCardControllerProvider) as RecordCardData).atOldest,
      isTrue,
    );

    final before = fake.calls;
    await controller.loadOlder(force: true);
    expect(fake.calls, greaterThan(before));
  });

  test('⚠️ 줌을 바꿔도 서버를 다시 부르지 않는다', () async {
    container = build();
    await _settle();
    final before = fake.calls;

    container
        .read(recordCardControllerProvider.notifier)
        .setZoom(CalendarZoom.quarter);
    await _settle();

    expect(fake.calls, before);
    final data = container.read(recordCardControllerProvider) as RecordCardData;
    expect(data.zoom, CalendarZoom.quarter);
  });

  test('⚠️ 필터를 바꿔도 서버를 다시 부르지 않는다', () async {
    container = build();
    await _settle();
    final before = fake.calls;

    container
        .read(recordCardControllerProvider.notifier)
        .setFilter(RecordCardActivity.race);
    await _settle();

    expect(fake.calls, before);
    final data = container.read(recordCardControllerProvider) as RecordCardData;
    expect(data.filter, RecordCardActivity.race);
    expect(data.months.any((m) => m.cardCount > 0), isTrue);
  });

  test('필터를 다시 떼면 전체로 돌아온다', () async {
    container = build();
    await _settle();
    final controller = container.read(recordCardControllerProvider.notifier)
      ..setFilter(RecordCardActivity.race)
      ..setFilter(null);

    expect(controller.state, isA<RecordCardData>());
    expect((controller.state as RecordCardData).filter, isNull);
  });

  test('실패하면 RecordCardError가 된다', () async {
    container = build(
      repository: FakeRecordCardRepository(
        today: _today,
        failWith: RecordCardFailure.network,
      ),
    );
    await _settle();

    final state = container.read(recordCardControllerProvider);
    expect(state, isA<RecordCardError>());
    expect((state as RecordCardError).failure, RecordCardFailure.network);
  });

  test('달마다 카드와 러닝 기록을 함께 받는다', () async {
    container = build(
      records: _Records({DateTime(2026, 11, 5), DateTime(2026, 10, 20)}),
    );
    await _settle();

    final data = container.read(recordCardControllerProvider) as RecordCardData;
    final november = data.months.firstWhere(
      (month) => month.month == DateTime(2026, 11),
    );
    expect(november.recordDays, contains(DateTime(2026, 11, 5)));
    final october = data.months.firstWhere(
      (month) => month.month == DateTime(2026, 10),
    );
    expect(october.recordDays, contains(DateTime(2026, 10, 20)));
    // 11월 조회가 10월 기록을 끌어오면 구간이 새는 것이다.
    expect(november.recordDays, isNot(contains(DateTime(2026, 10, 20))));
  });

  test('⚠️ 러닝 기록 조회가 실패해도 달력은 산다 — 운동화만 빠진다', () async {
    // 카드를 보는 것이 이 탭의 본업이다. 기록 조회 하나로 달력을 오류 화면으로
    // 날리면 1번 PR에서 고친 결함을 되살린다.
    container = build(records: _FailingRecords());
    await _settle();

    final state = container.read(recordCardControllerProvider);
    expect(state, isA<RecordCardData>());
    expect((state as RecordCardData).shoeDays, isEmpty);
    expect(state.months, hasLength(3));
  });

  test('⚠️ 계정이 바뀌면 앞 사람 카드를 버리고 다시 읽는다', () async {
    container = build();
    await _settle();
    final before = fake.calls;

    auth.set(const AuthSignedIn('u-2', isOnboarded: true));
    await _settle();

    expect(fake.calls, greaterThan(before));
    expect(container.read(recordCardControllerProvider), isA<RecordCardData>());
  });

  test('⚠️ 로그아웃하면 들고 있던 카드를 버린다', () async {
    container = build();
    await _settle();

    auth.set(const AuthSignedOut(returning: true));
    await _settle();

    expect(
      container.read(recordCardControllerProvider),
      isA<RecordCardLoading>(),
    );
  });
}
