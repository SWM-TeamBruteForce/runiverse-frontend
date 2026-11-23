import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';
import 'package:runiverse/features/profile/presentation/profile_card_tile.dart';
import 'package:runiverse/features/profile/presentation/profile_cards_page.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 기록카드 **전체 보기** — 프로필 그리드의 `더 보기`가 오는 곳(설계 6-7).
void main() {
  final today = DateTime(2026, 11, 16);
  late FakeRecordCardRepository repo;

  setUp(() => repo = FakeRecordCardRepository(today: today));

  /// 화면만 세운다. 라우터가 필요한 것은 [pumpRouted]를 쓴다.
  Future<void> pump(
    WidgetTester tester, {
    bool mine = false,
    bool light = false,
  }) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: light ? AppTheme.light() : AppTheme.dark(),
          home: const ProfileCardsPage(userId: 'u-1'),
        ),
      ),
    );
    // 받아 오는 동안이 한 프레임 있다.
    await tester.pump();
  }

  testWidgets('받는 동안 진행 표시가 돈다', (tester) async {
    repo = FakeRecordCardRepository(
      today: today,
      delay: const Duration(milliseconds: 50),
    );
    await pump(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('공개된 카드가 칸으로 선다', (tester) async {
    await pump(tester);

    final all = await repo.byUser(userId: 'u-1');
    // 한 화면에 다 들어오지 않아 **만들어진 칸만** 센다.
    expect(find.byType(ProfileCardTile), findsWidgets);
    expect(all.length, greaterThan(6));
  });

  testWidgets('사진 없는 카드는 선 아트로 선다', (tester) async {
    await pump(tester);

    expect(find.byType(RouteArtView), findsWidgets);
  });

  testWidgets('⚠️ 카드가 없으면 한 줄로 알린다 — 눌러서 들어온 화면이다', (tester) async {
    // 그리드는 침묵하지만(설계 6-7) 이 화면이 텅 비면 고장으로 읽힌다.
    for (final card in await repo.byUser(userId: 'u-1')) {
      await repo.delete(card.id);
    }
    await pump(tester);

    expect(find.text(AppStrings.profileCardsEmpty), findsOneWidget);
  });

  testWidgets('못 읽으면 오류와 다시 시도가 선다', (tester) async {
    repo.failWith = RecordCardFailure.network;
    await pump(tester);

    expect(find.text(AppStrings.profileCardsError), findsOneWidget);

    repo.failWith = null;
    await tester.tap(find.text(AppStrings.recordRetry));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ProfileCardTile), findsWidgets);
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await pump(tester, light: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(ProfileCardTile), findsWidgets);
  });

  testWidgets('스크린리더가 무슨 칸인지 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final card = (await repo.byUser(userId: 'u-1')).first;
    expect(
      find.bySemanticsLabel(AppStrings.profileCardsOn(card.startedAt)),
      findsOneWidget,
    );

    handle.dispose();
  });

  group('칸을 누르면', () {
    /// 진짜 라우터로 세운다 — 상세로 가는 길을 본다.
    Future<void> pumpRouted(WidgetTester tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final router = createAppRouter(
        initialLocation: AppRoutes.recordCardsOf('u-1'),
      );
      addTearDown(router.dispose);

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
    }

    testWidgets('⚠️ 남의 카드에는 ⋮가 없다 — 서버가 그렇게 답한다', (tester) async {
      // 묶음 6까지는 라우트 쿼리가 소유자를 말했다. 지금은 상세(8-1)의
      // `isMine`이 정본이다.
      await pumpRouted(tester);

      // ⚠️ **첫 칸을 누르지 않는다.** 목 카드 1000번은 음악이 "만드는 중"으로
      // 심겨 있고 요청 기록이 없어 **영영 끝나지 않는다** — 상세를 열면 폴링
      // 타이머가 남아 `!timersPending`으로 죽는다(묶음 5에서 미뤄 둔 것 11번).
      final tile = find.byType(ProfileCardTile).at(1);
      // ⚠️ **번호를 짐작하지 않는다.** 그리드는 최신순이라 둘째 칸이 어느 목
      // 카드인지 날짜에 달려 있다 — 누를 칸에서 직접 읽는다.
      repo.notMineIds.add(tester.widget<ProfileCardTile>(tile).card.id);

      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.byType(CardDetailPage), findsOneWidget);
      expect(find.byIcon(LucideIcons.ellipsisVertical), findsNothing);
    });

    testWidgets('내 카드면 고칠 수 있다', (tester) async {
      await pumpRouted(tester);

      await tester.tap(find.byType(ProfileCardTile).at(1));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);
    });
  });
}
