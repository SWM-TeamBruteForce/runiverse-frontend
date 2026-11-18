import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/card_compose_page.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/features/record_card/presentation/route_art_view.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

final _today = DateTime(2026, 9, 10);
final _day = DateTime(2026, 9, 2);

RunRecord _record({required int id, int hour = 18}) => RunRecord(
  id: id,
  runningRoomId: id + 900,
  startedAt: DateTime(2026, 9, 2, hour),
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5, seconds: 13),
  playerCount: 1,
);

RecordCard _card({required int id, required int runningRecordId}) => RecordCard(
  id: id,
  runningRecordId: runningRecordId,
  startedAt: DateTime(2026, 9, 2, 18),
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '회고',
  photos: const [],
  route: RouteArt.empty,
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5),
  runners: const [],
);

RunDetail _detail({required int roomId, bool withTrack = true}) => RunDetail(
  runningRoomId: roomId,
  players: const [],
  splitsByPlayer: const {},
  distanceMeters: 5400,
  duration: const Duration(minutes: 28),
  averagePace: const Duration(minutes: 5, seconds: 13),
  track: withTrack
      ? [
          [
            GeoPoint(
              latitude: 37.50,
              longitude: 127.00,
              recordedAt: DateTime(2026, 9, 2),
            ),
            GeoPoint(
              latitude: 37.51,
              longitude: 127.01,
              recordedAt: DateTime(2026, 9, 2),
            ),
          ],
        ]
      : const [],
  rawSplits: const [],
);

class _Records implements RunRecordRepository {
  _Records(this.records, {this.detail});

  final List<RunRecord> records;
  final RunDetail? detail;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => records;

  @override
  Future<RunDetail> byRoom(int runningRoomId) async {
    final found = detail;
    if (found == null) {
      throw const RunRecordException(RunRecordFailure.network);
    }
    return found;
  }
}

class _FailingRecords implements RunRecordRepository {
  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => throw const RunRecordException(RunRecordFailure.network);

  @override
  Future<Never> byRoom(int runningRoomId) =>
      throw const RunRecordException(RunRecordFailure.network);
}

class _Cards implements RecordCardRepository {
  _Cards(this.cards);

  final List<RecordCard> cards;

  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => cards;
}

Future<void> _pump(
  WidgetTester tester, {
  RunRecordRepository? records,
  RecordCardRepository? cards,
  DateTime? day,
  bool light = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runRecordRepositoryProvider.overrideWithValue(
          records ?? _Records([_record(id: 11)], detail: _detail(roomId: 911)),
        ),
        recordCardRepositoryProvider.overrideWithValue(
          cards ?? _Cards(const []),
        ),
        recordCardClockProvider.overrideWithValue(() => _today),
      ],
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: CardComposePage(day: day ?? _day),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 라우터를 끼운 판. `context.push`가 어디로 갔는지 보는 테스트가 쓴다.
Future<GoRouter> _pumpRouted(
  WidgetTester tester, {
  RunRecordRepository? records,
  RecordCardRepository? cards,
}) async {
  final router = GoRouter(
    initialLocation: '/compose',
    routes: [
      GoRoute(
        path: '/compose',
        builder: (_, _) => CardComposePage(day: _day),
      ),
      GoRoute(
        path: AppRoutes.recordCardDetail,
        builder: (_, _) => const Scaffold(body: Text('상세')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runRecordRepositoryProvider.overrideWithValue(
          records ?? _Records([_record(id: 11)], detail: _detail(roomId: 911)),
        ),
        recordCardRepositoryProvider.overrideWithValue(
          cards ?? _Cards(const []),
        ),
        recordCardClockProvider.overrideWithValue(() => _today),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// 기록 한 줄을 누른다.
Future<void> _pickRecord(WidgetTester tester, RunRecord record) async {
  await tester.tap(
    find.text(
      AppStrings.recordRunLine(
        record.startedAt,
        record.distanceKm,
        record.duration,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// ⚠️ **화면 밖으로 내려간 것을 끌어 올린다.** `ListView(children:)`는 보이지
/// 않는 자식의 **element 를 만들지 않아** `find`가 찾지 못한다 — 없는 것과
/// 구별되지 않는다.
Future<void> _reach(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('머리와 묶음 이름이 선다', (tester) async {
    await _pump(tester);

    expect(find.text(AppStrings.recordCardComposeTitle), findsOne);
    expect(find.text(AppStrings.recordCardComposeRecordSection), findsOne);
    expect(find.text(AppStrings.recordCardComposeDateLabel(_day)), findsOne);
    await _reach(tester, find.text(AppStrings.recordCardReview));
    expect(find.text(AppStrings.recordCardComposeActivitySection), findsOne);
    expect(find.text(AppStrings.recordCardReview), findsOne);
  });

  testWidgets('기록을 고르고 유형·회고를 채우면 다음이 켜진다', (tester) async {
    await _pump(tester);

    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );

    await _pickRecord(tester, _record(id: 11));
    await _reach(tester, find.text(AppStrings.recordCardActivityDaily));
    await tester.tap(find.text(AppStrings.recordCardActivityDaily));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppInputV2), '좋았다');
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('⚠️ 그날 기록이 없으면 한 줄로 알린다 — 날짜는 그대로 바꿀 수 있다', (tester) async {
    // 달력에서는 여기 닿지 않는다(안 뛴 날이 안 눌린다). 탭 머리의 쓰기로
    // 들어왔는데 오늘 안 뛴 경우와, 날짜 휠로 옮긴 경우에 뜬다.
    await _pump(tester, records: _Records(const []), day: DateTime(2026, 9, 3));

    expect(find.text(AppStrings.recordCardComposeNoRecords), findsOne);
    expect(
      find.text(AppStrings.recordCardComposeDateLabel(DateTime(2026, 9, 3))),
      findsOne,
    );
  });

  testWidgets('⚠️ 기록 조회가 실패하면 목록 자리에만 오류가 뜬다', (tester) async {
    // 화면 전체를 오류로 덮으면 날짜를 바꿀 길까지 사라진다.
    await _pump(tester, records: _FailingRecords());

    expect(find.text(AppStrings.recordCardComposeRecordsError), findsOne);
    expect(find.text(AppStrings.recordRetry), findsOne);
    expect(find.text(AppStrings.recordCardComposeDateLabel(_day)), findsOne);
    // 유형과 회고도 살아 있다 — 오류가 화면을 덮지 않는다.
    await _reach(
      tester,
      find.text(AppStrings.recordCardComposeActivitySection),
    );
    expect(find.text(AppStrings.recordCardComposeActivitySection), findsOne);
  });

  testWidgets('⚠️ 기록이 전부 카드를 가진 날 — 목록은 보이고 다음은 꺼져 있다', (tester) async {
    await _pump(
      tester,
      records: _Records([_record(id: 11, hour: 7), _record(id: 12)]),
      cards: _Cards([
        _card(id: 500, runningRecordId: 11),
        _card(id: 501, runningRecordId: 12),
      ]),
    );

    expect(find.text(AppStrings.recordCardComposeHasCard), findsNWidgets(2));
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });

  testWidgets('⚠️ 카드가 있는 기록을 누르면 고르지 않고 그 카드로 간다', (tester) async {
    // 수정 화면은 뒤 PR이라 지금은 상세로 보낸다. 눌리는데 아무 일도 안
    // 일어나는 줄을 만들지 않는다.
    final router = await _pumpRouted(
      tester,
      records: _Records([_record(id: 11)]),
      cards: _Cards([_card(id: 500, runningRecordId: 11)]),
    );

    await _pickRecord(tester, _record(id: 11));

    expect(router.state.uri.toString(), AppRoutes.recordCardDetailOf(500));
    expect(find.text('상세'), findsOne);
  });

  testWidgets('고른 기록의 경로와 지표가 뜬다', (tester) async {
    await _pump(tester);
    await _pickRecord(tester, _record(id: 11));

    expect(find.byType(RouteArtView), findsOne);
    await _reach(tester, find.text(AppStrings.recordCardDistance));
    expect(find.text(AppStrings.recordCardDistance), findsOne);
    expect(find.text(AppStrings.recordCardPace), findsOne);
    expect(find.text(AppStrings.recordCardDuration), findsOne);
  });

  testWidgets('⚠️ 경로가 없는 기록이면 선 아트 자리에 한 줄이 든다', (tester) async {
    await _pump(
      tester,
      records: _Records([
        _record(id: 11),
      ], detail: _detail(roomId: 911, withTrack: false)),
    );
    await _pickRecord(tester, _record(id: 11));

    expect(find.text(AppStrings.recordCardComposeRouteNone), findsOne);
    expect(find.byType(RouteArtView), findsNothing);
  });

  testWidgets('⚠️ 경로를 못 받으면 없는 것과 다르게 말한다', (tester) async {
    // 다시 열면 보일 수 있다. "경로가 없는 러닝"으로 뭉개면 사실이 아니다.
    await _pump(tester, records: _Records([_record(id: 11)]));
    await _pickRecord(tester, _record(id: 11));

    expect(find.text(AppStrings.recordCardComposeRouteFailed), findsOne);
  });

  testWidgets('⚠️ 회고는 1000자에서 멈춘다', (tester) async {
    await _pump(tester);
    await _reach(tester, find.byType(AppInputV2));
    await tester.enterText(find.byType(AppInputV2), '가' * 1200);
    await tester.pumpAndSettle();

    expect(
      find.text(
        AppStrings.recordCardComposeReviewCounter(
          CardDraft.reviewMaxLength,
          CardDraft.reviewMaxLength,
        ),
      ),
      findsOne,
    );
  });

  testWidgets('날짜 행을 누르면 휠이 뜬다', (tester) async {
    await _pump(tester);

    await tester.tap(find.text(AppStrings.recordCardComposeDateLabel(_day)));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.recordCardComposeDateSheet), findsOne);
  });

  group('날짜 휠의 상한', () {
    // ⚠️ 위젯 테스트로는 증명할 수 없다 — 휠은 보이는 항목만 그려서 "없다"가
    // "안 고를 수 있다"를 뜻하지 않는다. 계산을 직접 짚는다.

    test('⚠️ 오늘 이후는 고를 수 없다 — 뛰지 않은 날의 카드는 없다', () {
      expect(composeDayValues(year: 2026, month: 9, today: _today).last, 10);
      expect(composeMonthValues(year: 2026, today: _today).last, 9);
      expect(composeYearValues(_today).last, 2026);
    });

    test('지난 달은 그 달 끝까지 고를 수 있다', () {
      expect(composeDayValues(year: 2026, month: 8, today: _today).last, 31);
      expect(composeDayValues(year: 2026, month: 2, today: _today).last, 28);
      // 2024년은 윤년이다.
      expect(composeDayValues(year: 2024, month: 2, today: _today).last, 29);
    });

    test('지난 해는 열두 달이 다 선다', () {
      expect(composeMonthValues(year: 2025, today: _today), hasLength(12));
    });

    test('고를 수 있는 해는 올해까지 셋이다', () {
      expect(composeYearValues(_today), [2024, 2025, 2026]);
    });
  });

  testWidgets('⚠️ 초안에 쓴 것이 화면을 다시 세워도 남는다', (tester) async {
    await _pump(tester);
    await _reach(tester, find.byType(AppInputV2));
    await tester.enterText(find.byType(AppInputV2), '쓴 글');
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(CardComposePage));
    final container = ProviderScope.containerOf(element);

    expect(container.read(cardDraftProvider(null)).reviewText, '쓴 글');
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await _pump(tester, light: true);

    expect(tester.takeException(), isNull);
  });
}
