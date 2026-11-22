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
          home: ProfileCardsPage(userId: 'u-1', mine: mine),
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
    /// 진짜 라우터로 세운다 — 상세로 가는 길과 `mine`이 흘러가는지 본다.
    Future<void> pumpRouted(WidgetTester tester, {required bool mine}) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final router = createAppRouter(
        initialLocation: AppRoutes.recordCardsOf('u-1', mine: mine),
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

    testWidgets('⚠️ 남의 카드로 열린다 — 고칠 수 없다', (tester) async {
      await pumpRouted(tester, mine: false);

      // ⚠️ **첫 칸을 누르지 않는다.** 목 카드 1000번은 음악이 "만드는 중"으로
      // 심겨 있고 요청 기록이 없어 **영영 끝나지 않는다** — 상세를 열면 폴링
      // 타이머가 남아 `!timersPending`으로 죽는다(묶음 5에서 미뤄 둔 것 11번).
      await tester.tap(find.byType(ProfileCardTile).at(1));
      await tester.pumpAndSettle();

      expect(find.byType(CardDetailPage), findsOneWidget);
      expect(find.byIcon(LucideIcons.ellipsisVertical), findsNothing);
    });

    testWidgets('내 카드로 들어왔으면 고칠 수 있다', (tester) async {
      await pumpRouted(tester, mine: true);

      await tester.tap(find.byType(ProfileCardTile).at(1));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);
    });
  });
}
