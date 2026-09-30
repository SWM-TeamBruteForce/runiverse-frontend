import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/coming_soon_page.dart';
import 'package:runiverse/core/widgets/v2/app_tab_bar.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_page.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
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
      ProviderScope(
        // ⚠️ **기록 저장소를 갈아 끼워야 한다.** 진짜 구현은 `dioProvider`를
        // 거치고, 그쪽은 `API_BASE_URL` 없이 죽는다 — 테스트는
        // `--dart-define`을 받지 않는다. 여기서 보는 건 라우터 배선이지
        // 서버 통신이 아니다.
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(
            FakeRunRecordRepository(today: DateTime(2026, 9, 3)),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.home),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 탭을 이름으로 찾는다.
  ///
  /// ⚠️ **글자로는 못 찾는다.** 탭 바가 아이콘만 두기로 바뀌어서
  /// (2026-09-30, 시안 `158:2899`) 화면에 라벨이 아예 안 그려진다.
  /// 이름은 `Semantics`에만 남아 있고, **그것이 스크린리더가 가진 전부**다 —
  /// 여기서 그걸 쓰는 것이 곧 그 이름이 살아 있는지 보는 것이기도 하다.
  Finder tabLabel(String label) => find.descendant(
    of: find.byType(AppTabBarV2),
    matching: find.bySemanticsLabel(label),
  );

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(tabLabel(label));
    await tester.pumpAndSettle();
  }

  testWidgets('앱을 켜면 홈 탭이 열려 있다', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);

    expect(find.byType(HomePage), findsOneWidget);
    expect(tabLabel(AppStrings.tabHome), findsOneWidget);
    handle.dispose();
  });

  testWidgets('기록 탭을 누르면 기록 화면이 열린다', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await tapTab(tester, AppStrings.tabRecord);

    expect(find.byType(RecordPage), findsOneWidget);
    handle.dispose();
  });

  testWidgets('기록카드 탭은 숨겨지지 않고 준비 중 화면을 연다', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await tapTab(tester, AppStrings.tabRecordCard);

    expect(find.byType(ComingSoonPage), findsOneWidget);
    expect(find.text(AppStrings.comingSoonTitle), findsOneWidget);
    handle.dispose();
  });

  testWidgets('⚠️ 탭은 넷이고, 뺀 둘은 없다', (tester) async {
    // 피드·대회일정을 뺀 결정(CLAUDE.md Scope)이 코드에 남아 있는지 본다.
    // branch 를 지우고 탭만 지우면 라우터에 닿을 수 없는 화면이 남는다.
    final handle = tester.ensureSemantics();
    await pumpApp(tester);

    expect(find.byType(AppTabBarV2), findsOneWidget);
    for (final name in [
      AppStrings.tabHome,
      AppStrings.tabRecord,
      AppStrings.tabRecordCard,
      AppStrings.tabProfile,
    ]) {
      expect(tabLabel(name), findsOneWidget, reason: '$name 탭이 없다');
    }
    expect(tabLabel('피드'), findsNothing);
    expect(tabLabel('대회일정'), findsNothing);
    handle.dispose();
  });
}
