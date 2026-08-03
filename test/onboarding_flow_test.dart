import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_intro_page.dart';
import 'package:runiverse/features/onboarding/presentation/splash_page.dart';

/// 온보딩 흐름의 상태 전이 — 스플래시에서 소개를 거쳐 앱 본체로 들어가는가.
///
/// 화면의 생김새는 보지 않는다. 여기서 보는 건 **어디로 가느냐**다.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RuniverseApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('앱의 첫 화면은 스플래시다', (tester) async {
    await pumpApp(tester);

    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.text(AppStrings.brandName), findsOneWidget);
  });

  testWidgets('스플래시는 1.6초 뒤 저절로 온보딩으로 넘어간다', (tester) async {
    await pumpApp(tester);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingIntroPage), findsOneWidget);
  });

  testWidgets('스플래시를 누르면 기다리지 않고 넘어간다', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingIntroPage), findsOneWidget);
  });

  testWidgets('마지막 카드에서 버튼 라벨이 시작하기로 바뀐다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();

    // 1장 → 2장 → 3장
    expect(find.text(AppStrings.onboardingNext), findsOneWidget);
    await tester.tap(find.text(AppStrings.onboardingNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.onboardingNext));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.onboardingNext), findsNothing);
    expect(find.text(AppStrings.onboardingStart), findsOneWidget);
  });

  testWidgets('건너뛰기는 카드를 다 보지 않고 앱으로 들어간다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(SplashPage));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.onboardingSkip));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });
}
