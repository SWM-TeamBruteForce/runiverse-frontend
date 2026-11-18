import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
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

RecordCard _card({
  int id = 7,
  int runningRecordId = 11,
  String reviewText = '여행에서 뛰었다',
  int distanceMeters = 3050,
}) => RecordCard(
  id: id,
  runningRecordId: runningRecordId,
  startedAt: DateTime(2026, 9, 2, 18),
  activity: RecordCardActivity.travel,
  visibility: RecordCardVisibility.public,
  reviewText: reviewText,
  photos: const [],
  route: RouteArt.empty,
  distanceMeters: distanceMeters,
  duration: const Duration(minutes: 18),
  averagePace: const Duration(minutes: 5, seconds: 54),
  runners: const [],
);

/// 회고 칸을 화면 안으로 끌어 올린다.
///
/// ⚠️ **수정 모드는 더 길다** — 경로 미리보기와 지표가 들어가 회고 칸이 600dp
/// 테스트 화면 밑으로 내려간다. `ListView`는 화면 밖 자식을 아예 만들지 않아
/// `enterText`가 "No element"로 죽는다.
Future<void> _reachReview(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byType(TextField),
    find.byType(ListView),
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
}

String _reviewText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

bool _nextEnabled(WidgetTester tester) {
  final button = tester.widget<TextButton>(
    find.ancestor(
      of: find.text(AppStrings.recordCardComposeNext),
      matching: find.byType(TextButton),
    ),
  );
  return button.onPressed != null;
}

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
  Future<void> delete(int cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');
}

Future<void> _pump(
  WidgetTester tester, {
  RunRecordRepository? records,
  RecordCardRepository? cards,
  DateTime? day,
  bool light = false,
  RecordCard? card,
  ProviderContainer? container,
}) async {
  final overrides = [
    runRecordRepositoryProvider.overrideWithValue(
      records ?? _Records([_record(id: 11)], detail: _detail(roomId: 911)),
    ),
    recordCardRepositoryProvider.overrideWithValue(cards ?? _Cards(const [])),
    recordCardClockProvider.overrideWithValue(() => _today),
  ];

  final app = MaterialApp(
    theme: light ? AppTheme.light() : AppTheme.dark(),
    home: CardComposePage(
      day: day ?? card?.day ?? _day,
      cardId: card?.id,
      card: card,
    ),
  );

  // 미리 더럽혀 둔 초안을 보려면 컨테이너를 밖에서 들어야 한다.
  await tester.pumpWidget(
    container == null
        ? ProviderScope(overrides: overrides, child: app)
        : UncontrolledProviderScope(container: container, child: app),
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

  group('쓰던 것을 지키는 길', () {
    /// 초안을 미리 채워 둔 판. 화면이 세워질 때의 판단을 보려면 그 전에
    /// 초안이 있어야 한다.
    Future<ProviderContainer> pumpWithDraft(
      WidgetTester tester, {
      required void Function(CardDraftController draft) seed,
      DateTime? day,
    }) async {
      final container = ProviderContainer(
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(
            _Records([_record(id: 11)], detail: _detail(roomId: 911)),
          ),
          recordCardRepositoryProvider.overrideWithValue(_Cards(const [])),
          recordCardClockProvider.overrideWithValue(() => _today),
        ],
      );
      addTearDown(container.dispose);
      seed(container.read(cardDraftProvider(null).notifier));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: CardComposePage(day: day ?? _day),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('⚠️ 쓰던 초안이 있으면 들어올 때 확인을 받는다', (tester) async {
      // 설계 7절: draft 가 있는데 새로 진입하면 덮어쓰기 전에 알린다.
      await pumpWithDraft(tester, seed: (draft) => draft.setReview('쓰던 글'));

      expect(find.text(AppStrings.recordCardComposeResumeTitle), findsOne);
      expect(find.text(AppStrings.recordCardComposeResume), findsOne);
      expect(find.text(AppStrings.recordCardComposeStartOver), findsOne);
    });

    testWidgets('이어 쓰기를 고르면 쓴 글이 남는다', (tester) async {
      final container = await pumpWithDraft(
        tester,
        seed: (draft) => draft.setReview('쓰던 글'),
      );

      await tester.tap(find.text(AppStrings.recordCardComposeResume));
      await tester.pumpAndSettle();

      expect(container.read(cardDraftProvider(null)).reviewText, '쓰던 글');
      expect(find.text(AppStrings.recordCardComposeResumeTitle), findsNothing);
    });

    testWidgets('⚠️ 새로 쓰기를 고르면 초안이 비워진다', (tester) async {
      final container = await pumpWithDraft(
        tester,
        seed: (draft) => draft.setReview('쓰던 글'),
      );

      await tester.tap(find.text(AppStrings.recordCardComposeStartOver));
      await tester.pumpAndSettle();

      expect(container.read(cardDraftProvider(null)).reviewText, '');
    });

    testWidgets('쓴 것이 없으면 묻지 않는다', (tester) async {
      await pumpWithDraft(tester, seed: (_) {});

      expect(find.text(AppStrings.recordCardComposeResumeTitle), findsNothing);
    });

    testWidgets('⚠️ 쓴 것이 있을 때 뒤로 가면 확인을 받는다', (tester) async {
      await _pump(tester);
      await _reach(tester, find.byType(AppInputV2));
      await tester.enterText(find.byType(AppInputV2), '쓴 글');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsOne);
    });

    testWidgets('쓴 것이 없으면 뒤로가 그냥 나간다', (tester) async {
      await _pump(tester);

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsNothing);
    });

    testWidgets('⚠️ 복귀 시트를 바깥 탭으로 닫아도 쓴 글이 남는다', (tester) async {
      // 모든 시트가 바깥 탭으로 닫히는 앱에서, 가장 무심한 동작 하나로 쓴
      // 회고가 사라지면 안 된다. 초안은 영속화하지 않아 되돌릴 길이 없다.
      final container = await pumpWithDraft(
        tester,
        seed: (draft) => draft.setReview('쓰던 글'),
      );

      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();

      expect(container.read(cardDraftProvider(null)).reviewText, '쓰던 글');
    });

    testWidgets('⚠️ 버리기를 한 번 누르면 화면을 나간다', (tester) async {
      // PopScope 의 canPop 이 아직 다시 그려지지 않아, maybePop 이 같은 시트를
      // 또 띄운다. 사용자는 버리겠다고 한 뒤 빈 화면에 갇힌다.
      final router = GoRouter(
        initialLocation: '/host',
        routes: [
          GoRoute(
            path: '/host',
            builder: (_, _) => const Scaffold(body: Text('호스트')),
          ),
          GoRoute(
            path: '/compose',
            builder: (_, _) => CardComposePage(day: _day),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runRecordRepositoryProvider.overrideWithValue(
              _Records([_record(id: 11)], detail: _detail(roomId: 911)),
            ),
            recordCardRepositoryProvider.overrideWithValue(_Cards(const [])),
            recordCardClockProvider.overrideWithValue(() => _today),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.push('/compose');
      await tester.pumpAndSettle();

      await _reach(tester, find.byType(AppInputV2));
      await tester.enterText(find.byType(AppInputV2), '쓴 글');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.recordCardComposeDiscard));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsNothing);
      expect(find.byType(CardComposePage), findsNothing);
      expect(find.text('호스트'), findsOne);
    });

    testWidgets('⚠️ 날짜를 바꾸면 고른 기록이 풀린다', (tester) async {
      // 안 풀면 날짜 행은 5일인데 초안은 2일 기록을 들고 있고, 그 아래 경로와
      // 지표도 2일 것이다. 그대로 저장하면 엉뚱한 러닝에 카드가 붙는다.
      await _pump(tester);
      await _pickRecord(tester, _record(id: 11));
      await _reach(tester, find.text(AppStrings.recordCardActivityDaily));
      await tester.tap(find.text(AppStrings.recordCardActivityDaily));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(AppInputV2), '좋았다');
      await tester.pumpAndSettle();

      // 회고 칸까지 내려와 있어 날짜 행이 위로 사라졌다. 끌어 올린다 —
      // `ListView(children:)`는 보이지 않는 자식의 element 를 만들지 않는다.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.recordCardComposeDateLabel(_day)));
      await tester.pumpAndSettle();
      // 오늘은 9월 10일이라 일 칸은 1~10이고 지금 2일에 서 있다. 셋 굴려 5일로.
      await tester.drag(
        find.byType(ListWheelScrollView).at(2),
        const Offset(0, -132),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.wheelPickerConfirm));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(CardComposePage));
      final draft = ProviderScope.containerOf(
        element,
      ).read(cardDraftProvider(null));

      expect(
        find.text(AppStrings.recordCardComposeDateLabel(DateTime(2026, 9, 5))),
        findsOne,
      );
      expect(draft.record, isNull);
      expect(draft.route, isNull);
      expect(draft.canProceed, isFalse);
      // 앞 기록의 지표가 남아 있으면 안 된다.
      expect(find.text(AppStrings.recordCardDistance), findsNothing);
    });

    testWidgets('⚠️ 버리기를 고르면 초안이 비워진다', (tester) async {
      final container = await pumpWithDraft(tester, seed: (_) {});
      await _reach(tester, find.byType(AppInputV2));
      await tester.enterText(find.byType(AppInputV2), '쓴 글');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.recordCardComposeDiscard));
      await tester.pumpAndSettle();

      expect(container.read(cardDraftProvider(null)).reviewText, '');
    });
  });

  /// 수정은 작성 1을 그대로 다시 쓴다 (설계 6-6).
  group('카드를 고치러 들어왔을 때', () {
    testWidgets('제목이 쓰기가 아니라 고치기다', (tester) async {
      await _pump(tester, card: _card());

      expect(find.text(AppStrings.recordCardEditTitle), findsOne);
      expect(find.text(AppStrings.recordCardComposeTitle), findsNothing);
    });

    testWidgets('카드 값이 칸에 들어와 있다', (tester) async {
      await _pump(tester, card: _card());
      await _reachReview(tester);

      expect(_reviewText(tester), '여행에서 뛰었다');
      expect(_nextEnabled(tester), isTrue);
    });

    testWidgets('⚠️ 러닝 기록은 바꿀 수 없다', (tester) async {
      // `unique(running_record_id)` 때문에 카드 있는 기록으로 옮기면 서버가
      // 거절하고, 바꾸면 지표·경로가 통째로 달라져 다른 카드가 된다(설계 6-6).
      await _pump(tester, card: _card());

      expect(find.text(AppStrings.recordCardEditRecordLocked), findsOne);
    });

    testWidgets('⚠️ 날짜 줄을 눌러도 휠이 안 뜬다', (tester) async {
      // 날짜를 바꾸면 그날의 다른 기록으로 옮기는 길이 열린다.
      await _pump(tester, card: _card());

      await tester.tap(
        find.text(AppStrings.recordCardComposeDateLabel(_card().day)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardComposeDateSheet), findsNothing);
    });

    testWidgets('고를 기록 목록이 없다', (tester) async {
      await _pump(tester, card: _card());

      expect(find.text(AppStrings.recordCardComposeNoRecords), findsNothing);
      // 고른 하나를 읽기 전용으로 보여 준다.
      expect(find.textContaining('3.05'), findsWidgets);
    });

    testWidgets('⚠️ 이어 쓰기를 묻지 않는다', (tester) async {
      // 뜬 초안은 손대지 않은 것이다. 물으면 고치러 들어온 사람에게 아무
      // 말이나 묻는 꼴이다.
      await _pump(tester, card: _card());

      expect(find.text(AppStrings.recordCardComposeResumeTitle), findsNothing);
    });

    testWidgets('⚠️ 고친 뒤 뒤로 나가면 버릴지 묻는다', (tester) async {
      await _pump(tester, card: _card());

      await _reachReview(tester);
      await tester.enterText(find.byType(TextField), '고친 글');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();

      // ⚠️ **작성의 "쓰던 기록카드를 버릴까요?"가 아니다** — 고치던 기존
      // 카드를 두고 그렇게 물으면 카드가 지워지는 것으로 읽힌다.
      expect(find.text(AppStrings.recordCardEditDiscardTitle), findsOne);
      expect(find.text(AppStrings.recordCardEditDiscardBody), findsOne);
      expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsNothing);
    });

    testWidgets('⚠️ 더러운 초안으로 다시 들어와도 이어 쓰기를 묻지 않는다', (tester) async {
      // 수정 스택이 밖에서 걷히면(세션 만료 → `context.go(signIn)`) 초안은
      // keepAlive라 더러운 채 남는다. 다시 들어왔을 때 묻는 것은 **작성의
      // 말**이고, 거기서 `새로 쓰기`를 고르면 `editing`이 사라져 **저장할 수
      // 없는 수정 화면**에 갇힌다.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final card = _card();
      container.read(cardDraftProvider(card.id).notifier)
        ..seed(card)
        ..setReview('고치다 만 글');

      await _pump(tester, card: card, container: container);

      expect(find.text(AppStrings.recordCardComposeResumeTitle), findsNothing);
      expect(container.read(cardDraftProvider(card.id)).editing, isNotNull);
    });

    testWidgets('⚠️ 버리기는 카드 값으로 되돌린다 — 수정 화면을 잠그지 않는다', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final card = _card();
      container.read(cardDraftProvider(card.id).notifier)
        ..seed(card)
        ..setReview('고치다 만 글');

      await _pump(tester, card: card, container: container);
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.recordCardComposeDiscard));
      await tester.pumpAndSettle();

      final draft = container.read(cardDraftProvider(card.id));
      expect(draft.editing, isNotNull, reason: '고치던 카드를 잃으면 안 된다');
      expect(draft.reviewText, card.reviewText);
      expect(draft.canProceed, isTrue, reason: '다시 저장할 수 있어야 한다');
    });

    testWidgets('안 고치고 나가면 묻지 않는다', (tester) async {
      await _pump(tester, card: _card());

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsNothing);
    });
  });
}
