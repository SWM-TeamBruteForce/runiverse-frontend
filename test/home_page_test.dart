// flutter_test는 material을 재수출하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/empty_state_card.dart';
import 'package:runiverse/features/home/presentation/home_hero.dart';

/// 홈 (S05 상태 1) — 무엇이 보이고, 아직 없는 화면으로 가는 버튼이 무엇을 하는가.
void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: RuniverseApp(initialLocation: AppRoutes.home),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('히어로', () {
    testWidgets('버튼 두 개가 있다', (tester) async {
      await pumpHome(tester);

      expect(find.byType(HomeHero), findsOneWidget);
      expect(
        find.widgetWithText(AppButton, AppStrings.homeMatchCta),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(AppButton, AppStrings.homeSoloCta),
        findsOneWidget,
      );
    });

    testWidgets('매칭 버튼이 primary, 1인 러닝이 secondary다', (tester) async {
      await pumpHome(tester);

      final match = tester.widget<AppButton>(
        find.widgetWithText(AppButton, AppStrings.homeMatchCta),
      );
      final solo = tester.widget<AppButton>(
        find.widgetWithText(AppButton, AppStrings.homeSoloCta),
      );

      expect(match.variant, AppButtonVariant.primary);
      expect(solo.variant, AppButtonVariant.secondary);
    });

    testWidgets('시간대 인사가 넷 중 하나로 나온다', (tester) async {
      await pumpHome(tester);

      // 어느 시각에 돌려도 통과해야 한다. CI 시각을 고정할 수 없다.
      const greetings = [
        AppStrings.homeGreetingMorning,
        AppStrings.homeGreetingAfternoon,
        AppStrings.homeGreetingEvening,
        AppStrings.homeGreetingNight,
      ];
      final shown = greetings.where((g) => find.text(g).evaluate().isNotEmpty);

      expect(shown, hasLength(1));
    });
  });

  group('아직 없는 화면으로 가는 버튼', () {
    testWidgets('매칭을 누르면 준비 중이라고 알려준다', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.widgetWithText(AppButton, AppStrings.homeMatchCta));
      await tester.pump();

      expect(find.text(AppStrings.homeMatchComingSoon), findsOneWidget);
    });

    testWidgets('1인 러닝을 누르면 준비 중이라고 알려준다', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.widgetWithText(AppButton, AppStrings.homeSoloCta));
      await tester.pump();

      expect(find.text(AppStrings.homeSoloPending), findsOneWidget);
    });
  });

  group('빈 상태', () {
    testWidgets('대회와 최근 러닝 자리가 비어 있다', (tester) async {
      await pumpHome(tester);

      expect(find.byType(EmptyStateCard), findsNWidgets(2));
      expect(find.text(AppStrings.homeEmptyCompetition), findsOneWidget);
      expect(find.text(AppStrings.homeEmptyRecentRun), findsOneWidget);
    });

    testWidgets('최근 러닝 빈 자리는 무엇을 하면 채워지는지 알려준다', (tester) async {
      await pumpHome(tester);

      expect(find.text(AppStrings.homeEmptyRecentRunHint), findsOneWidget);
    });
  });
}
