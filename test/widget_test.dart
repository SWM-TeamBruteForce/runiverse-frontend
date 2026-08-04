import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/coming_soon_page.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/record/presentation/record_page.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';

/// 탭 셸의 상태 전이 — 탭을 누르면 그 branch가 열리는가.
///
/// 화면 내용은 아직 뼈대라 검증할 게 없다. 여기서 보는 건 **라우터 배선**이다.
/// branch 순서와 탭 순서가 어긋나면(가장 흔한 실수) 이 테스트가 잡는다.
void main() {
  /// 탭 셸부터 띄운다. 온보딩은 지나오지 않는다.
  ///
  /// 예전에는 스플래시부터 눌러가며 들어왔는데, 온보딩에 화면이 하나 늘 때마다
  /// **탭과 무관한 이 테스트가 깨졌다.** 온보딩 흐름 자체는
  /// `onboarding_flow_test.dart`가 따로 본다.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: RuniverseApp(initialLocation: AppRoutes.home)),
    );
    await tester.pumpAndSettle();
  }

  /// 탭 바 안의 라벨만 찾는다. 화면 본문이 같은 글자를 그려도 헷갈리지 않는다.
  Finder tabLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(tabLabel(label));
    await tester.pumpAndSettle();
  }

  testWidgets('앱을 켜면 홈 탭이 열려 있다', (tester) async {
    await pumpApp(tester);

    expect(find.byType(HomePage), findsOneWidget);
    expect(tabLabel(AppStrings.tabHome), findsOneWidget);
  });

  testWidgets('기록 탭을 누르면 기록 화면이 열린다', (tester) async {
    await pumpApp(tester);
    await tapTab(tester, AppStrings.tabRecord);

    expect(find.byType(RecordPage), findsOneWidget);
  });

  testWidgets('피드 탭은 숨겨지지 않고 준비 중 화면을 연다', (tester) async {
    await pumpApp(tester);
    await tapTab(tester, AppStrings.tabFeed);

    expect(find.byType(ComingSoonPage), findsOneWidget);
    expect(find.text(AppStrings.comingSoonTitle), findsOneWidget);
  });
}
