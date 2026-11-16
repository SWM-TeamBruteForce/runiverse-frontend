import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
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

/// 떠난 조회가 끝날 때까지 기다린다. 가짜는 지연이 0이라 한 바퀴면 된다.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeRecordCardRepository fake;
  late ProviderContainer container;
  late _Auth auth;

  ProviderContainer build({FakeRecordCardRepository? repository}) {
    fake = repository ?? FakeRecordCardRepository(today: _today);
    auth = _Auth(const AuthSignedIn('u-1', isOnboarded: true));
    final made = ProviderContainer(
      overrides: [
        recordCardRepositoryProvider.overrideWithValue(fake),
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
    expect(
      data.visible.map((m) => m.month),
      [DateTime(2026, 9), DateTime(2026, 10), DateTime(2026, 11)],
    );
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
    expect(data.visible.first.month, DateTime(2026, 6));
    expect(data.visible, hasLength(6));
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

    expect(container.read(recordCardControllerProvider), isA<RecordCardLoading>());
  });
}
