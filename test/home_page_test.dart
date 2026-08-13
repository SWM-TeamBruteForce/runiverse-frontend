import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/empty_state_card.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/home/presentation/home_hero.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';

/// 홈 (S05 상태 1) — 무엇이 보이고, 아직 없는 화면으로 가는 버튼이 무엇을 하는가.
void main() {
  Future<void> pumpHome(WidgetTester tester, {AuthState? auth}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (auth != null)
            authControllerProvider.overrideWith(
              () => _StubAuthController(auth),
            ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.home),
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

  group('프로필 관문', () {
    testWidgets('⚠️ 온보딩을 안 마쳤으면 관문이 막아선다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: false),
      );

      // 유도 카드를 대신한 것이다. 카드는 지나칠 수 있었지만 이것은 아니다 —
      // 프로필 없이는 매칭도 기록도 돌아가지 않는다.
      expect(find.text(AppStrings.profileSheetCta), findsOneWidget);
    });

    testWidgets('온보딩을 마쳤으면 막아서지 않는다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: true),
      );

      expect(find.text(AppStrings.profileSheetCta), findsNothing);
    });

    testWidgets('로그인 상태를 모를 때도 막아서지 않는다', (tester) async {
      // 스플래시를 거치지 않고 홈에 바로 온 경우다. 모르는 상태에서 막아서면
      // 이미 프로필을 채운 사람도 잠깐 갇힌다.
      await pumpHome(tester, auth: const AuthUnknown());

      expect(find.text(AppStrings.profileSheetCta), findsNothing);
    });

    testWidgets('관문의 CTA는 프로필 등록으로 간다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: false),
      );

      await tester.tap(find.text(AppStrings.profileSheetCta));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileSetupPage), findsOneWidget);
    });

    testWidgets('⚠️ 스크림을 눌러도 닫히지 않는다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: false),
      );

      // 화면 맨 위(시트 밖)를 누른다. 보통 바텀시트는 여기서 닫힌다.
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();

      // 닫히면 프로필 없는 사람이 앱을 그냥 쓰게 된다.
      expect(find.text(AppStrings.profileSheetCta), findsOneWidget);
    });
  });
}

/// 상태를 고정한 컨트롤러.
///
/// `signIn()`으로 상태를 만들면 안 된다 — `testWidgets`는 가짜 시간 위에서 도는데
/// `pumpWidget` 전에 Future를 기다리면 시간을 진행시킬 `pump`가 없어 **테스트가 멈춘다.**
/// 여기서 보는 것은 화면이 주어진 상태를 어떻게 그리는가뿐이다.
class _StubAuthController extends AuthController {
  _StubAuthController(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;
}
