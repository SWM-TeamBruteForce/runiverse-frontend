import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/card_face.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';
import 'package:runiverse/features/profile/presentation/profile_card_grid.dart';
import 'package:runiverse/features/profile/presentation/profile_card_tile.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 프로필의 기록카드 그리드 (설계 6-7).
void main() {
  late _Cards repo;

  setUp(() => repo = _Cards(7));

  /// 그리드 하나를 세운다. 전체 보기로 가는 길을 함께 깐다.
  Future<GoRouter> pump(
    WidgetTester tester, {
    bool light = false,
  }) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: const ProfileCardGrid(userId: 'u-1'),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.recordCardsOfUser,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('전체 보기'))),
        ),
        GoRoute(
          path: AppRoutes.recordCardDetail,
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('상세'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(
          theme: light ? AppTheme.light() : AppTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    return router;
  }

  testWidgets('⚠️ 여섯 장만 묻는다 — 한 장 더 받아 가늠하지 않는다', (tester) async {
    // 묶음 6까지는 일곱 장을 받아 "더 있나"를 가늠했다. 서버가 `nextCursor`를
    // 주면서 그 꾀가 필요 없어졌다(연동 가이드 5절 1번).
    await pump(tester);

    expect(repo.asked.single, ProfileCardGrid.previewCount);
    expect(find.byType(ProfileCardTile), findsNWidgets(6));
  });

  testWidgets('⚠️ 서버가 커서를 주면 더 보기가 선다', (tester) async {
    await pump(tester);

    expect(find.text(AppStrings.profileCardsMore), findsOneWidget);
  });

  testWidgets('⚠️ 여섯 장 이하면 더 보기가 없다', (tester) async {
    // 세워 두면 딱 여섯 장인 사람이 아무것도 더 없는 화면으로 간다.
    repo = _Cards(6);
    await pump(tester);

    expect(find.byType(ProfileCardTile), findsNWidgets(6));
    expect(find.text(AppStrings.profileCardsMore), findsNothing);
  });

  testWidgets('더 보기를 누르면 전체 보기로 간다', (tester) async {
    final router = await pump(tester);

    await tester.tap(find.text(AppStrings.profileCardsMore));
    await tester.pumpAndSettle();

    expect(find.text('전체 보기'), findsOneWidget);
    // ⚠️ **소유자를 쿼리로 싣지 않는다.** 상세가 8-1의 `isMine`으로 안다
    // (2026-11-24). 쿼리를 남기면 두 출처가 어긋날 수 있다.
    expect(router.state.uri.toString(), isNot(contains('mine')));
  });

  testWidgets('⚠️ 칸을 누르면 그 카드 번호로 상세에 간다', (tester) async {
    final router = await pump(tester);

    await tester.tap(find.byType(ProfileCardTile).first);
    await tester.pumpAndSettle();

    expect(find.text('상세'), findsOneWidget);
    // 첫 칸은 가장 최근 카드다(`_Cards`가 날짜를 내림차순으로 짓는다).
    expect(router.state.uri.path, contains('card-500'));
  });

  testWidgets('⚠️ 좌우 여백은 두는 쪽이 정한다 — 화면마다 다르면 안 된다', (tester) async {
    // 안쪽에 여백을 품으면 **이미 여백이 있는 화면**(남의 프로필)에서 두 번
    // 들어가, 같은 위젯이 내 프로필보다 좁고 더 들여써진다(설계 6-7은 "같은
    // 위젯").
    await pump(tester);

    expect(tester.getSize(find.byType(GridView)).width, 412);
  });

  testWidgets('⚠️ 카드가 없으면 아무것도 그리지 않는다', (tester) async {
    // 남의 프로필에 "아직 없어요"를 띄울 이유가 없다(설계 6-7).
    repo = _Cards(0);
    await pump(tester);

    expect(find.byType(ProfileCardTile), findsNothing);
    expect(find.text(AppStrings.profileCardsMore), findsNothing);
    expect(tester.getSize(find.byType(ProfileCardGrid)).height, 0);
  });

  testWidgets('⚠️ 사진 없는 카드는 점 하나로 선다 — 여기엔 경로가 없다', (tester) async {
    await pump(tester);

    // 7장 중 홀수 번째가 사진 없는 카드다(`_Cards`). 10-3 항목에는 경로가
    // 없어(연동 가이드 5절) 선을 그을 수 없다 — 달력 칸은 선을 긋는다.
    expect(find.byType(RouteArtView), findsNothing);
    expect(find.byType(CardMarkDot), findsWidgets);
  });

  testWidgets('⚠️ 받는 동안 두 줄을 미리 비워 두지 않는다', (tester) async {
    // 두 줄은 412dp 기기에서 약 440dp — **화면의 절반**이다. 그만큼 비워 두면
    // 카드가 없는 사람(새 계정, 남의 빈 프로필)에게 큰 빈 칸이 떴다가 통째로
    // 사라지며 아래가 솟는다. 받는 자리는 한 줄로 잡고, 카드가 오면 내려간다.
    repo = _Cards(7, delay: const Duration(milliseconds: 50));
    await pump(tester);

    final loading = tester.getSize(find.byType(ProfileCardGrid)).height;
    expect(loading, ProfileCardGrid.loadingHeight);
    expect(loading, lessThan(ProfileCardGrid.blockHeight(412) / 2));

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.byType(ProfileCardTile), findsNWidgets(6));
    // 칸 두 줄이 섰다 — 그리드가 제 높이를 찾았다.
    expect(
      tester.getSize(find.byType(ProfileCardTile).first).height * 2 + 8,
      closeTo(ProfileCardGrid.blockHeight(412), 0.5),
    );
  });

  testWidgets('못 읽으면 한 줄로 말하고 다시 시도가 선다', (tester) async {
    repo = _Cards(7, failure: RecordCardFailure.network);
    await pump(tester);

    expect(find.text(AppStrings.profileCardsError), findsOneWidget);

    repo.failure = null;
    await tester.tap(find.text(AppStrings.recordRetry));
    // 버리고 다시 받는다 — 한 프레임으로는 안 된다.
    await tester.pumpAndSettle();

    expect(find.byType(ProfileCardTile), findsNWidgets(6));
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await pump(tester, light: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(ProfileCardTile), findsNWidgets(6));
  });

  testWidgets('스크린리더가 무슨 칸인지 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(
      find.bySemanticsLabel(
        AppStrings.profileCardsOn(repo.cards.first.startedAt),
      ),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('⚠️ 스크린리더로도 눌린다 — 읽히기만 하면 죽은 버튼이다', (tester) async {
    // 칸에는 사진뿐이라 `Semantics`가 안쪽을 가린다. 가리면 탭 동작을 들고
    // 있는 노드까지 함께 사라져, **읽히고 버튼이라고 말하지만 눌러도 아무 일도
    // 없는 칸**이 된다. 전체 보기 화면도 같은 칸을 쓴다.
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          AppStrings.profileCardsOn(repo.cards.first.startedAt),
        ),
      ),
      isSemantics(isButton: true, hasTapAction: true),
    );

    handle.dispose();
  });
}

/// 카드를 정해진 수만큼 주는 저장소. **장수를 손으로 쥐어야** `더 보기`가
/// 서는 경계를 볼 수 있다.
class _Cards implements RecordCardRepository {
  _Cards(int count, {this.delay = Duration.zero, this.failure})
    : cards = [
        for (var i = 0; i < count; i++)
          RecordCard(
            id: 'card-${500 + i}',
            runningRecordId: 11 + i,
            startedAt: DateTime(2026, 11, 16 - i, 7),
            activity: RecordCardActivity.daily,
            visibility: RecordCardVisibility.public,
            reviewText: '$i번째',
            // 홀수 번째는 사진이 없다 — 선 아트가 서는 자리를 본다.
            photos: i.isEven
                ? [RecordCardPhoto(id: 'img-${70 + i}', url: 'assets/images/a$i.jpg')]
                : const [],
            route: const RouteArt(
              strokes: [
                [RoutePoint(0, 0), RoutePoint(1, 1)],
              ],
              aspect: 1,
            ),
            distanceMeters: 5400,
            duration: const Duration(minutes: 28),
            averagePace: const Duration(minutes: 5, seconds: 13),
            runners: const [],
          ),
      ];

  final List<RecordCard> cards;
  final Duration delay;
  RecordCardFailure? failure;

  /// 몇 장씩 물었나.
  final asked = <int?>[];

  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) async {
    asked.add(limit);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failure != null) throw RecordCardException(failure!);

    final size = limit ?? cards.length;
    return RecordCardListPage(
      items: [
        for (final card in cards.take(size))
          RecordCardListItem(
            id: card.id,
            startedAt: card.startedAt,
            distanceMeters: card.distanceMeters,
            imageCount: card.photos.length,
            thumbnailUrl: card.thumbnailUrl,
          ),
      ],
      // ⚠️ **더 있으면 커서를 준다.** `더 보기`가 이것으로 선다 — 묶음 6까지는
      // 한 장 더 받아 가늠했다.
      nextCursor: cards.length > size ? '$size' : null,
    );
  }

  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) => throw UnsupportedError('그리드는 달력을 받지 않는다');

  @override
  Future<RecordCard> create(NewRecordCard card) =>
      throw UnsupportedError('그리드는 카드를 만들지 않는다');

  @override
  Future<RecordCard> update(EditRecordCard card) =>
      throw UnsupportedError('그리드는 카드를 고치지 않는다');

  @override
  Future<RecordCard> detailOf(String cardId) =>
      throw UnsupportedError('이 테스트는 상세를 열지 않는다');

  @override
  Future<void> delete(String cardId) => throw UnsupportedError('그리드는 카드를 지우지 않는다');

  /// 이 테스트는 **음악을 보지 않는다.** 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<void> retryMusic(String cardId) =>
      throw UnsupportedError('이 테스트는 음악을 다시 만들지 않는다');

}
