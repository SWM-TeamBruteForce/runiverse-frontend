import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/card_compose_page.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_slide.dart';
import 'package:runiverse/features/record_card/presentation/compose_records_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

import 'record_card_fixtures.dart';

/// 작성 화면 0장의 목록 열쇠. 화면이 `PageStorageKey` 로 쓰는 값과 같다.
const composeFormKey = 'record-card-compose-form';

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

ComposableRecord _card({int id = 7, int runningRecordId = 11}) =>
    runWith(summary(id: id), runningRecordId: runningRecordId);

/// 수정 화면의 씨앗. **카드 전부**가 필요하다 — 초안이 회고와 사진까지 받는다.
RecordCard _full({
  int id = 7,
  int runningRecordId = 11,
  String reviewText = '여행에서 뛰었다',
  int distanceMeters = 3050,
}) => RecordCard(
  id: 'card-$id',
  runningRecordId: runningRecordId,
  startedAt: DateTime(2026, 9, 2, 18),
  activity: RecordCardActivity.travel,
  visibility: RecordCardVisibility.public,
  reviewText: reviewText,
  photos: const [],
  route: RouteArt.empty,
  distanceMeters: distanceMeters,
  duration: const Duration(minutes: 30),
  averagePace: const Duration(minutes: 6),
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

/// **첫 조회는 비어 있고, 두 번째부터 기록이 온다.** 서버가 방금 끝난 러닝을
/// 아직 싣지 않는 구간을 흉내낸다.
class _LateRecords implements RunRecordRepository {
  _LateRecords(this.records, {this.detail});

  final List<RunRecord> records;
  final RunDetail? detail;
  var calls = 0;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => calls++ == 0 ? const [] : records;

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
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) => throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  _Cards(this.cards);

  final List<ComposableRecord> cards;

  @override
  Future<List<ComposableRecord>> runsInRange({
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
  Future<RecordCard> detailOf(String cardId) =>
      throw UnsupportedError('이 테스트는 상세를 열지 않는다');

  @override
  Future<void> delete(String cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<void> retryMusic(String cardId) =>
      throw UnsupportedError('이 테스트는 음악을 다시 만들지 않는다');
}

/// **첫 조회는 비어 있고, 두 번째부터 기록이 온다.** 서버가 방금 끝난 러닝을
/// 아직 싣지 않는 구간을 흉내낸다.
class _LateCards extends _Cards {
  _LateCards(List<RunRecord> runs, RecordCardRepository? carded)
    : _rows = [
        for (final run in runs)
          ComposableRecord(
            record: run,
            existingCard: carded is _Cards
                ? {
                    for (final row in carded.cards)
                      row.record.id: row.existingCard,
                  }[run.id]
                : null,
          ),
      ],
      super(const []);

  final List<ComposableRecord> _rows;
  var _calls = 0;

  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) async => _calls++ == 0 ? const [] : _rows;
}

/// 조회가 깨지는 저장소. 목록 자리에 오류를 세우는 테스트가 쓴다.
class _ThrowingCards extends _Cards {
  _ThrowingCards() : super(const []);

  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) async => throw const RecordCardException(RecordCardFailure.network);
}

/// 두 스텁을 **7-1 한 응답으로 합친다.**
///
/// 서버는 러닝 기록과 카드 유무를 한 응답에 싣는다(연동 가이드 1절). 테스트는
/// `records:`로 기록을, `cards:`로 그중 어느 것에 카드가 있는지 세우던 모양을
/// 유지한다 — 호출부를 전부 고치는 대신 **합치는 일을 하네스가 한다.**
RecordCardRepository _merged(
  RunRecordRepository? records,
  RecordCardRepository? cards,
) {
  // 실패를 보는 테스트는 그대로 흘린다. 조회가 하나로 줄어서, 기록 조회가
  // 실패하던 자리는 **카드 조회 실패**가 된다 — 같은 한 요청이다.
  if (records is _FailingRecords) return _ThrowingCards();
  // 늦게 오는 목록도 그대로 흘린다.
  if (records is _LateRecords) {
    return _LateCards(records.records, cards);
  }

  final runs = records is _Records ? records.records : [_record(id: 11)];
  final carded = cards is _Cards ? cards.cards : const <ComposableRecord>[];
  final byRecord = {for (final row in carded) row.record.id: row.existingCard};

  return _Cards([
    for (final run in runs)
      ComposableRecord(record: run, existingCard: byRecord[run.id]),
  ]);
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
    recordCardRepositoryProvider.overrideWithValue(_merged(records, cards)),
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
  int? roomId,
}) async {
  final router = GoRouter(
    initialLocation: '/compose',
    routes: [
      GoRoute(
        path: '/compose',
        builder: (_, _) => CardComposePage(day: _day, roomId: roomId),
      ),
      GoRoute(
        path: AppRoutes.recordCardDetail,
        builder: (_, _) => const Scaffold(body: Text('상세')),
      ),
      GoRoute(
        path: AppRoutes.recordCardEdit,
        builder: (_, _) => const Scaffold(body: Text('수정')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runRecordRepositoryProvider.overrideWithValue(
          records ?? _Records([_record(id: 11)], detail: _detail(roomId: 911)),
        ),
        recordCardRepositoryProvider.overrideWithValue(_merged(records, cards)),
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
    // ⚠️ **폼 목록을 집어서 끈다.** `find.byType(Scrollable).first` 로는 가로
    // `PageView` 가 먼저 잡혀 장만 넘어가고 찾는 것에는 영영 닿지 않는다.
    // ⚠️ `.first` — 폼 안에 칩 줄 같은 작은 스크롤이 더 있다. 바깥의 것이
    // 목록 자신이다.
    scrollable: find
        .descendant(
          of: find.byKey(const PageStorageKey(composeFormKey)),
          matching: find.byType(Scrollable),
        )
        .first,
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

  testWidgets('⚠️ 이모지가 많아도 서버가 세는 길이에서 멈춘다', (tester) async {
    // 서버는 String.length(UTF-16)로 센다. grapheme 으로 막으면 포매터는
    // 통과시키고 서버가 400 을 준다 — 쓴 글을 거기서 잃는다.
    await _pump(tester);
    await _pickRecord(tester, _record(id: 11));
    await _reach(tester, find.byType(AppInputV2));
    await tester.enterText(find.byType(AppInputV2), '🏃' * 600);
    await tester.pumpAndSettle();

    final text = tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .text;
    expect(text.length, lessThanOrEqualTo(CardDraft.reviewMaxLength));
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

  testWidgets('⚠️ 카드가 있는 기록을 누르면 고르지 않고 수정으로 간다', (tester) async {
    // 설계 6-2 — "`카드` 표시를 붙이고, 누르면 수정으로 보낸다." 묶음 4에서
    // 수정 화면이 생기기 전에는 상세로 보냈다.
    final router = await _pumpRouted(
      tester,
      records: _Records([_record(id: 11)]),
      cards: _Cards([_card(id: 500, runningRecordId: 11)]),
    );

    await _pickRecord(tester, _record(id: 11));

    expect(router.state.uri.toString(), AppRoutes.recordCardEditOf('card-500'));
    expect(find.text('수정'), findsOne);
  });

  /// 러닝 요약에서 들어온 길 (설계 6-2 · 6-8).
  group('러닝 요약에서 왔으면', () {
    testWidgets('⚠️ 그 방에서 뛴 기록이 미리 골라진다', (tester) async {
      // 요약이 가진 것은 방 번호뿐이다 — `RunDetail`에 기록 번호가 없다.
      await _pumpRouted(
        tester,
        records: _Records([
          _record(id: 11),
          _record(id: 12, hour: 7),
        ], detail: _detail(roomId: 912)),
        roomId: 912,
      );

      // 고른 기록의 경로가 뜬다 = 골라졌다.
      expect(find.byType(RouteArtView), findsOne);
    });

    testWidgets('⚠️ 그 기록에 이미 카드가 있으면 수정으로 보낸다', (tester) async {
      // 작성 화면을 띄워 놓고 못 쓰게 하는 것보다 낫다(설계 6-2).
      final router = await _pumpRouted(
        tester,
        records: _Records([_record(id: 11)], detail: _detail(roomId: 911)),
        cards: _Cards([_card(id: 500, runningRecordId: 11)]),
        roomId: 911,
      );

      expect(
        router.state.uri.toString(),
        AppRoutes.recordCardEditOf('card-500'),
      );
      // ⚠️ **작성 화면을 남겨 두지 않는다** — 뒤로가 쓸 수 없는 화면으로
      // 돌아온다.
      expect(router.canPop(), isFalse);
    });

    testWidgets('⚠️ 처음 목록에 없었어도 다시 받으면 그때 골라진다', (tester) async {
      // 서버가 방금 끝난 러닝을 아직 목록에 싣지 않는 구간이 있다. 한 번
      // 못 찾고 **깃발을 태우면 그 러닝으로는 카드를 쓸 수 없다** — 목록에도
      // 없고, 미리 고르기도 이미 끝났다.
      final records = _LateRecords([
        _record(id: 11),
      ], detail: _detail(roomId: 911));
      final container = ProviderContainer(
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(records),
          recordCardRepositoryProvider.overrideWithValue(
            _merged(records, null),
          ),
          recordCardClockProvider.overrideWithValue(() => _today),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: CardComposePage(day: _day, roomId: 911),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 첫 목록은 비어 있었다 — 고른 것이 없다.
      expect(find.byType(RouteArtView), findsNothing);

      container.invalidate(composeRecordsProvider(_day));
      await tester.pumpAndSettle();

      expect(find.byType(RouteArtView), findsOne);
    });

    testWidgets('⚠️ 그 방이 목록에 없으면 아무 일도 하지 않는다', (tester) async {
      // 기록이 아직 서버에 없거나 날짜가 다른 경우다. 고르는 것은 사용자가
      // 한다 — 빈 화면을 띄우거나 엉뚱한 기록을 고르지 않는다.
      await _pumpRouted(
        tester,
        records: _Records([_record(id: 11)]),
        roomId: 7777,
      );

      expect(find.byType(RouteArtView), findsNothing);
      expect(tester.takeException(), isNull);
    });
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
          recordCardRepositoryProvider.overrideWithValue(
            _merged(_Records([_record(id: 11)]), null),
          ),
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
            recordCardRepositoryProvider.overrideWithValue(
              _merged(_Records([_record(id: 11)]), null),
            ),
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
      await _pump(tester, card: _full());

      expect(find.text(AppStrings.recordCardEditTitle), findsOne);
      expect(find.text(AppStrings.recordCardComposeTitle), findsNothing);
    });

    testWidgets('카드 값이 칸에 들어와 있다', (tester) async {
      await _pump(tester, card: _full());
      await _reachReview(tester);

      expect(_reviewText(tester), '여행에서 뛰었다');
      expect(_nextEnabled(tester), isTrue);
    });

    testWidgets('⚠️ 러닝 기록은 바꿀 수 없다', (tester) async {
      // `unique(running_record_id)` 때문에 카드 있는 기록으로 옮기면 서버가
      // 거절하고, 바꾸면 지표·경로가 통째로 달라져 다른 카드가 된다(설계 6-6).
      await _pump(tester, card: _full());

      expect(find.text(AppStrings.recordCardEditRecordLocked), findsOne);
    });

    testWidgets('⚠️ 날짜 줄을 눌러도 휠이 안 뜬다', (tester) async {
      // 날짜를 바꾸면 그날의 다른 기록으로 옮기는 길이 열린다.
      await _pump(tester, card: _full());

      await tester.tap(
        find.text(AppStrings.recordCardComposeDateLabel(_card().day)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardComposeDateSheet), findsNothing);
    });

    testWidgets('고를 기록 목록이 없다', (tester) async {
      await _pump(tester, card: _full());

      expect(find.text(AppStrings.recordCardComposeNoRecords), findsNothing);
      // 고른 하나를 읽기 전용으로 보여 준다.
      expect(find.textContaining('3.05'), findsWidgets);
    });

    testWidgets('⚠️ 이어 쓰기를 묻지 않는다', (tester) async {
      // 뜬 초안은 손대지 않은 것이다. 물으면 고치러 들어온 사람에게 아무
      // 말이나 묻는 꼴이다.
      await _pump(tester, card: _full());

      expect(find.text(AppStrings.recordCardComposeResumeTitle), findsNothing);
    });

    testWidgets('⚠️ 고친 뒤 뒤로 나가면 버릴지 묻는다', (tester) async {
      await _pump(tester, card: _full());

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
      final card = _full();
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
      final card = _full();
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
      await _pump(tester, card: _full());

      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsNothing);
    });
  });

  /// 작성 1과 사진이 **한 화면의 좌우 장**이 된 뒤의 일들
  /// (사용자 결정 2026-11-24).
  group('옆으로 미는 사진', () {
    Future<ProviderContainer> pumpPaged(
      WidgetTester tester, {
      void Function(CardDraftController draft)? seed,
    }) async {
      final container = ProviderContainer(
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(
            _Records([_record(id: 11)], detail: _detail(roomId: 911)),
          ),
          recordCardRepositoryProvider.overrideWithValue(
            _merged(_Records([_record(id: 11)]), null),
          ),
          recordCardClockProvider.overrideWithValue(() => _today),
        ],
      );
      addTearDown(container.dispose);
      seed?.call(container.read(cardDraftProvider(null).notifier));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: CardComposePage(day: _day),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    /// 작성 1을 통과한 초안에 사진 [photos]장.
    void ready(CardDraftController draft, {int photos = 0}) {
      draft
        ..pickRecord(_record(id: 11))
        ..setActivity(RecordCardActivity.daily)
        ..setReview('좋았다');
      for (var i = 0; i < photos; i++) {
        draft.addPhoto(
          PickedImage.validated(path: '/tmp/p$i.jpg', sizeBytes: 1024),
        );
      }
    }

    /// ⚠️ **반 장보다 넉넉히 민다.** 시험 화면이 800 넓이라 `-400`은 딱
    /// 절반이고, 거기서는 넘어갈지 돌아갈지가 갈린다.
    Future<void> swipeLeft(WidgetTester tester) async {
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('옆으로 밀면 사진 장이 나온다', (tester) async {
      await pumpPaged(tester);

      await swipeLeft(tester);

      expect(find.byType(CardAddPhotoSlide), findsOne);
    });

    testWidgets('다음은 사진이 아니라 저장하기로 간다', (tester) async {
      final router = GoRouter(
        initialLocation: '/compose',
        routes: [
          GoRoute(
            path: '/compose',
            builder: (_, _) => CardComposePage(day: _day),
          ),
          GoRoute(
            path: AppRoutes.recordCardNewPublish,
            builder: (_, _) => const Scaffold(body: Text('저장하기')),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(
            _Records([_record(id: 11)], detail: _detail(roomId: 911)),
          ),
          recordCardRepositoryProvider.overrideWithValue(
            _merged(_Records([_record(id: 11)]), null),
          ),
          recordCardClockProvider.overrideWithValue(() => _today),
        ],
      );
      addTearDown(container.dispose);
      ready(container.read(cardDraftProvider(null).notifier));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 쓰던 초안이 있으면 이어 쓰기를 묻는다 — 이어 쓴다.
      if (find.text(AppStrings.recordCardComposeResume).evaluate().isNotEmpty) {
        await tester.tap(find.text(AppStrings.recordCardComposeResume));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text(AppStrings.recordCardComposeNext));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), AppRoutes.recordCardNewPublish);
    });

    testWidgets('⚠️ 사진 장에서 뒤로 눌러도 버릴지 묻는다', (tester) async {
      // 버릴지 묻는 문은 작성 1에만 있었다. 한 화면이 되면 사진 장에서 눌러도
      // 그 문을 지나야 한다 — 안 그러면 쓴 글이 조용히 사라진다.
      await pumpPaged(tester, seed: (draft) => ready(draft));
      if (find.text(AppStrings.recordCardComposeResume).evaluate().isNotEmpty) {
        await tester.tap(find.text(AppStrings.recordCardComposeResume));
        await tester.pumpAndSettle();
      }

      await swipeLeft(tester);
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardComposeDiscardTitle), findsOne);
    });

    testWidgets('⚠️ 마지막 사진을 지우면 넣기 장으로 당겨진다', (tester) async {
      // 장 수가 줄어 보고 있던 자리가 범위를 벗어나면 빈 화면이 선다.
      final container = await pumpPaged(
        tester,
        seed: (draft) => ready(draft, photos: 1),
      );
      if (find.text(AppStrings.recordCardComposeResume).evaluate().isNotEmpty) {
        await tester.tap(find.text(AppStrings.recordCardComposeResume));
        await tester.pumpAndSettle();
      }

      await swipeLeft(tester);
      expect(find.byType(CardPhotoSlide), findsOne);

      // ⚠️ **끌어 올려야 닿는다.** 지우기 줄은 600dp 시험 화면 바로 밑에
      // 있다(기기 915dp에서는 보이는 자리다).
      await tester.drag(find.byType(PageView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.recordCardPhotoRemove));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(container.read(cardDraftProvider(null)).photos, isEmpty);
      expect(find.byType(CardAddPhotoSlide), findsOne);
    });

    testWidgets('⚠️ 사진 장에 갔다 와도 첫 장의 스크롤 자리가 남는다', (tester) async {
      // 옛 흐름에서는 사진이 위에 쌓인 다른 라우트라 작성 1이 살아 있었다.
      // 한 화면이 되면서 장 0이 버려지면, 회고를 쓰다 사진을 넣고 돌아온
      // 사람이 **맨 위로 튕겨** 쓰던 자리를 다시 찾아야 한다.
      await pumpPaged(tester, seed: (draft) => ready(draft));
      if (find.text(AppStrings.recordCardComposeResume).evaluate().isNotEmpty) {
        await tester.tap(find.text(AppStrings.recordCardComposeResume));
        await tester.pumpAndSettle();
      }

      final form = find.byType(PageView);
      await tester.drag(form, const Offset(0, -300));
      await tester.pumpAndSettle();
      final scrolled = tester
          .widget<Scrollable>(find.byType(Scrollable).at(1))
          .controller!
          .position
          .pixels;
      expect(scrolled, greaterThan(0));

      await swipeLeft(tester);
      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Scrollable>(find.byType(Scrollable).at(1))
            .controller!
            .position
            .pixels,
        scrolled,
      );
    });

    testWidgets('⚠️ 점은 손가락으로 누를 만큼 넓다', (tester) async {
      // 미는 사진 위에서는 가로 끌기를 사진이 먹어, 점이 사실상 유일한
      // 통로다(card_photo_pan.dart). 8dp 점을 그대로 과녁으로 쓰면 닿지 않는다.
      await pumpPaged(tester);

      final handle = tester.ensureSemantics();

      final dot = find.bySemanticsLabel(AppStrings.recordCardComposeGoToAdd);
      final size = tester.getSize(
        find.descendant(of: dot, matching: find.byType(GestureDetector)).first,
      );
      handle.dispose();

      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('⚠️ 회고를 쓰다 밀면 키보드가 따라오지 않는다', (tester) async {
      // 포커스가 캡션 칸으로 끌려가면 치던 글자가 엉뚱한 장에 들어간다.
      await pumpPaged(tester);
      await _reach(tester, find.byType(AppInputV2));
      await tester.tap(find.byType(AppInputV2));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);

      await swipeLeft(tester);

      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
    });

    testWidgets('⚠️ 마지막 사진을 지우면 남은 사진으로 당겨진다', (tester) async {
      // 넣기 장으로 튀면 남은 사진을 두고 빈 화면을 본다.
      final container = await pumpPaged(
        tester,
        seed: (draft) => ready(draft, photos: 2),
      );
      if (find.text(AppStrings.recordCardComposeResume).evaluate().isNotEmpty) {
        await tester.tap(find.text(AppStrings.recordCardComposeResume));
        await tester.pumpAndSettle();
      }

      await swipeLeft(tester);
      await swipeLeft(tester);
      await tester.drag(find.byType(PageView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.recordCardPhotoRemove));
      await tester.pumpAndSettle();

      expect(container.read(cardDraftProvider(null)).photos, hasLength(1));
      expect(find.byType(CardPhotoSlide), findsOne);
      expect(find.byType(CardAddPhotoSlide), findsNothing);
    });

    testWidgets('⚠️ 첫 장을 세로로 끌어도 장이 넘어가지 않는다', (tester) async {
      // 첫 장은 세로로 길다. 세로로 끌었는데 사진으로 넘어가면 회고를 읽다가
      // 화면이 바뀐다.
      await pumpPaged(tester);

      await tester.drag(find.byType(PageView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.byType(CardAddPhotoSlide), findsNothing);
    });
  });

  /// 지운 사진 화면 테스트에서 작성 화면으로 **옮겨 온 동작들**
  /// (2026-11-24 리뷰).
  group('사진 넣기', () {
    Future<ProviderContainer> pumpWithPicker(
      WidgetTester tester, {
      required PhotoPicker picker,
      int photos = 0,
    }) async {
      final container = ProviderContainer(
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(
            _Records([_record(id: 11)], detail: _detail(roomId: 911)),
          ),
          recordCardRepositoryProvider.overrideWithValue(
            _merged(_Records([_record(id: 11)]), null),
          ),
          recordCardClockProvider.overrideWithValue(() => _today),
          photoPickerProvider.overrideWithValue(picker),
        ],
      );
      addTearDown(container.dispose);

      final draft = container.read(cardDraftProvider(null).notifier);
      for (var i = 0; i < photos; i++) {
        draft.addPhoto(
          PickedImage.validated(path: '/tmp/seed\$i.jpg', sizeBytes: 1024),
        );
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: CardComposePage(day: _day),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (find.text(AppStrings.recordCardComposeResume).evaluate().isNotEmpty) {
        await tester.tap(find.text(AppStrings.recordCardComposeResume));
        await tester.pumpAndSettle();
      }
      return container;
    }

    /// 넣기 장으로 가서 더하기를 누른다.
    Future<void> tapAdd(WidgetTester tester) async {
      await tester.tap(
        find.bySemanticsLabel(AppStrings.recordCardComposeGoToAdd),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(LucideIcons.plus));
      await tester.pumpAndSettle();
    }

    testWidgets('넣으면 그 장으로 넘어간다', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await pumpWithPicker(
        tester,
        picker: _Picker(
          PickedImage.validated(path: '/tmp/a.jpg', sizeBytes: 9),
        ),
      );

      await tapAdd(tester);
      handle.dispose();

      expect(container.read(cardDraftProvider(null)).photos, hasLength(1));
      // 안 넘기면 무엇이 들어왔는지 모른다.
      expect(find.byType(CardPhotoSlide), findsOne);
    });

    testWidgets('⚠️ 취소는 실패가 아니다', (tester) async {
      // 올릴 생각을 접었을 뿐인 사람에게 "못 가져왔다"고 하면 거짓말이다.
      final handle = tester.ensureSemantics();
      final container = await pumpWithPicker(
        tester,
        picker: const _Picker(null),
      );

      await tapAdd(tester);
      handle.dispose();

      expect(container.read(cardDraftProvider(null)).photos, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('⚠️ 너무 큰 사진은 카드의 말로 거절한다', (tester) async {
      // 프로필 문구를 그대로 쓰면 "프로필 사진"이 카드 작성 화면에 나온다.
      final handle = tester.ensureSemantics();
      await pumpWithPicker(
        tester,
        picker: const _Picker.throwing(ProfileImageFailure.tooLarge),
      );

      await tapAdd(tester);
      handle.dispose();

      expect(find.text(AppStrings.recordCardPhotoTooLarge), findsOne);
    });

    testWidgets('⚠️ 대표로 지정하면 그 사진이 1번이 되고 화면이 따라간다', (tester) async {
      final container = await pumpWithPicker(
        tester,
        picker: const _Picker(null),
        photos: 2,
      );
      final draft = container.read(cardDraftProvider(null).notifier);
      draft.setCaption(0, 'ㄱ');
      draft.setCaption(1, 'ㄴ');
      await tester.pumpAndSettle();

      // 둘째 사진 장으로 간다.
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.recordCardPhotoMakeCover));
      await tester.pumpAndSettle();

      expect(
        container.read(cardDraftProvider(null)).photos.map((p) => p.caption),
        ['ㄴ', 'ㄱ'],
      );
      // 올려 놓고 다른 장을 보여 주면 무엇이 대표가 됐는지 알 수 없다.
      expect(_visibleCaption(tester), 'ㄴ');
    });

    testWidgets('⚠️ 장마다 제 캡션을 든다', (tester) async {
      // 컨트롤러 하나를 돌려 쓰면 이웃 장이 함께 서 있어 한쪽 글자가 다른
      // 쪽 칸에도 뜬다(2026-11-24 ruling).
      final container = await pumpWithPicker(
        tester,
        picker: const _Picker(null),
        photos: 2,
      );
      final draft = container.read(cardDraftProvider(null).notifier);
      draft.setCaption(0, 'ㄱ');
      draft.setCaption(1, 'ㄴ');
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(_visibleCaption(tester), 'ㄱ');

      await tester.drag(find.byType(PageView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(_visibleCaption(tester), 'ㄴ');
    });

    testWidgets('⚠️ 사진 장에 몇 번째인지 이름표가 붙는다', (tester) async {
      // 미리보기는 그림뿐이라 스크린리더가 읽을 것이 없다.
      final handle = tester.ensureSemantics();
      await pumpWithPicker(tester, picker: const _Picker(null), photos: 2);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(AppStrings.recordCardPhotoSemantics(1, 2)),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('라이트 테마에서도 사진 장이 그려진다', (tester) async {
      final container = ProviderContainer(
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(
            _Records([_record(id: 11)], detail: _detail(roomId: 911)),
          ),
          recordCardRepositoryProvider.overrideWithValue(
            _merged(_Records([_record(id: 11)]), null),
          ),
          recordCardClockProvider.overrideWithValue(() => _today),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(cardDraftProvider(null).notifier)
          .addPhoto(
            PickedImage.validated(path: '/tmp/light.jpg', sizeBytes: 1024),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: CardComposePage(day: _day),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (find.text(AppStrings.recordCardComposeResume).evaluate().isNotEmpty) {
        await tester.tap(find.text(AppStrings.recordCardComposeResume));
        await tester.pumpAndSettle();
      }
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.byType(CardPhotoSlide), findsOne);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 지금 보이는 장의 캡션 칸 글.
///
/// ⚠️ **칸이 여럿이다.** 장마다 제 칸을 들고 PageView 는 이웃 장을 함께
/// 만들어 둔다 — 눌릴 수 있는 것만 고른다.
String _visibleCaption(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField).hitTestable())
    .last
    .controller!
    .text;

/// 고르기를 흉내 낸다. 던지게 하려면 [_Picker.throwing].
class _Picker implements PhotoPicker {
  const _Picker(this._image) : _failure = null;
  const _Picker.throwing(ProfileImageFailure failure)
    : _image = null,
      _failure = failure;

  final PickedImage? _image;
  final ProfileImageFailure? _failure;

  @override
  Future<PickedImage?> pick() async {
    final failure = _failure;
    if (failure != null) throw ProfileImageException(failure);
    return _image;
  }
}
