import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/activity_filter.dart';
import 'package:runiverse/features/record_card/presentation/record_card_calendar.dart';
import 'package:runiverse/features/record_card/presentation/record_card_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

final _today = DateTime(2026, 11, 16);

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn('u-1', isOnboarded: true);
}

/// 9월 9일에만 뛴 기록이 있는 저장소. 그날은 카드가 없어 운동화가 선다.
class _OneRun implements RunRecordRepository {
  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    const day = 9;
    final at = DateTime(2026, 11, day, 8);
    if (at.isBefore(from) || at.isAfter(to)) return const [];
    return [
      RunRecord(
        id: 11,
        runningRoomId: 911,
        startedAt: at,
        distanceMeters: 5400,
        duration: const Duration(minutes: 28),
        averagePace: const Duration(minutes: 5),
        playerCount: 1,
      ),
    ];
  }

  @override
  Future<Never> byRoom(int runningRoomId) =>
      throw UnimplementedError('이 테스트는 상세를 부르지 않는다');
}

/// 카드가 한 장도 없는 저장소.
class _EmptyRepository implements RecordCardRepository {
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<List<RecordCard>> byUser({required String userId, int? limit}) =>
      throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> create(NewRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 만들지 않는다');

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> update(EditRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 고치지 않는다');

  /// 이 테스트는 **읽기만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<RecordCard> detailOf(String cardId) =>
      throw UnsupportedError('이 테스트는 상세를 열지 않는다');

  @override
  Future<void> delete(String cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<MusicGeneration> musicOf(String cardId) =>
      throw UnsupportedError('이 테스트는 음악을 보지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<MusicGeneration> requestMusic(String cardId) =>
      throw UnsupportedError('이 테스트는 음악을 만들지 않는다');
}

Future<void> _pump(
  WidgetTester tester, {
  RecordCardRepository? repository,
  bool light = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recordCardRepositoryProvider.overrideWithValue(
          repository ?? FakeRecordCardRepository(today: _today),
        ),
        // 달력이 러닝 기록도 받는다 — 실제 구현을 그대로 두면 dio와 토큰
        // 저장소를 끌어온다.
        runRecordRepositoryProvider.overrideWithValue(
          FakeRunRecordRepository(today: _today),
        ),
        recordCardClockProvider.overrideWithValue(() => _today),
        authControllerProvider.overrideWith(_Auth.new),
      ],
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: const RecordCardPage(),
      ),
    ),
  );
}

/// 라우터를 끼운 판. 입구가 어디로 보내는지 보는 테스트가 쓴다.
Future<GoRouter> _pumpRouted(
  WidgetTester tester, {
  RecordCardRepository? repository,
  RunRecordRepository? records,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.recordCard,
    routes: [
      GoRoute(
        path: AppRoutes.recordCard,
        builder: (_, _) => const RecordCardPage(),
      ),
      GoRoute(
        path: AppRoutes.recordCardNew,
        builder: (_, _) => const Scaffold(body: Text('작성')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recordCardRepositoryProvider.overrideWithValue(
          repository ?? FakeRecordCardRepository(today: _today),
        ),
        runRecordRepositoryProvider.overrideWithValue(
          records ?? FakeRunRecordRepository(today: _today),
        ),
        recordCardClockProvider.overrideWithValue(() => _today),
        authControllerProvider.overrideWith(_Auth.new),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  test('recordCardNewOn이 날짜를 쿼리로 싣는다', () {
    // `extra`로 넘기면 딥링크·복구에서 사라진다.
    expect(
      AppRoutes.recordCardNewOn(DateTime(2026, 9, 3)),
      '/record-card/new?date=2026-09-03',
    );
    expect(
      AppRoutes.recordCardNewOn(DateTime(2026, 12, 25)),
      '/record-card/new?date=2026-12-25',
    );
  });

  testWidgets('⚠️ 탭 머리의 쓰기로 작성에 들어간다', (tester) async {
    final router = await _pumpRouted(tester);

    await tester.tap(find.byTooltip(AppStrings.recordCardEmptyAction));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.recordCardNew);
    expect(find.text('작성'), findsOne);
  });

  testWidgets('⚠️ 카드가 한 장도 없으면 빈 안내에 쓰기 버튼이 선다', (tester) async {
    final router = await _pumpRouted(tester, repository: _EmptyRepository());

    expect(find.text(AppStrings.recordCardEmptyTitle), findsOne);
    await tester.tap(find.text(AppStrings.recordCardEmptyAction));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.recordCardNew);
  });

  testWidgets('⚠️ 운동화 날을 누르면 그 날짜로 작성에 간다', (tester) async {
    // 1번 PR 에서는 아무 일도 하지 않았다 — 눌리는데 반응이 없는 칸이었다.
    final router = await _pumpRouted(
      tester,
      repository: _EmptyRepository(),
      records: _OneRun(),
    );

    await tester.tap(
      find.bySemanticsLabel(
        AppStrings.recordCardCellUnwrittenSemantics(DateTime(2026, 11, 9)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      router.state.uri.toString(),
      AppRoutes.recordCardNewOn(DateTime(2026, 11, 9)),
    );
  });

  testWidgets('받는 동안 로딩을 보여준다', (tester) async {
    await _pump(
      tester,
      repository: FakeRecordCardRepository(
        today: _today,
        delay: const Duration(milliseconds: 50),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('받아 오면 달력이 선다', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(RecordCardCalendar), findsOneWidget);
  });

  testWidgets('실패하면 오류와 다시 시도가 뜬다', (tester) async {
    await _pump(
      tester,
      repository: FakeRecordCardRepository(
        today: _today,
        failWith: RecordCardFailure.network,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.recordCardError), findsOneWidget);
    expect(find.text(AppStrings.recordRetry), findsOneWidget);
    expect(find.byType(RecordCardCalendar), findsNothing);
  });

  testWidgets('⚠️ 카드가 하나도 없어도 달력은 남는다', (tester) async {
    await _pump(tester, repository: _EmptyRepository());
    await tester.pumpAndSettle();

    expect(find.byType(RecordCardCalendar), findsOneWidget);
    expect(find.text(AppStrings.recordCardEmptyTitle), findsOneWidget);
  });

  testWidgets('⚠️ 필터로 0장이 된 것은 빈 상태가 아니다', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.recordCardActivityRace));
    await tester.pumpAndSettle();

    // 카드는 있는데 유형 필터로 안 보일 뿐이다. 안내를 띄우면 필터 때문인 줄 모른다.
    expect(find.text(AppStrings.recordCardEmptyTitle), findsNothing);
  });

  testWidgets('유형 칩은 하나만 고를 수 있다', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(ActivityFilter), findsOneWidget);
    expect(find.text(AppStrings.recordCardFilterAll), findsOneWidget);

    await tester.tap(find.text(AppStrings.recordCardActivityTravel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.recordCardActivityDaily));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('고른 칩을 다시 누르면 전체로 돌아온다', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.recordCardActivityDaily));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.recordCardActivityDaily));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await _pump(tester, light: true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(RecordCardCalendar), findsOneWidget);
  });
}
