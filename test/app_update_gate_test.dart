import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/core/version/installed_app_version.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_update_gate.dart';
import 'package:runiverse/features/app_update/presentation/app_update_provider.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';

/// 업데이트 게이트 — **막혔을 때 앱이 보이지 않아야 한다.**
///
/// 최소 버전에 못 미치면 서버가 `/app/version`을 뺀 모든 요청을 403으로
/// 거절한다. 그 상태로 앱 안에 들어가면 어느 화면도 제대로 뜨지 않고,
/// 사용자는 "앱이 고장났다"로 읽는다.
void main() {
  late FakeAppVersionRepository versions;

  /// 앱 자리에 두는 표지. 게이트가 덮으면 이것이 사라진다.
  const appMark = Key('app-behind-the-gate');

  setUp(() => InstalledAppVersion.setForTest(const AppVersion(1, 0, 0)));
  tearDown(InstalledAppVersion.resetForTest);

  Future<void> pumpGate(
    WidgetTester tester, {
    required AppVersion minimum,
    AppVersion? latest,
  }) async {
    versions = FakeAppVersionRepository(
      minimum: minimum,
      latest: latest ?? minimum,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appVersionRepositoryProvider.overrideWithValue(versions)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AppUpdateGate(
            child: Scaffold(body: Text('홈', key: appMark)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 스플래시가 하는 일 — 판정을 받아 둔다.
  Future<void> check(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppUpdateGate)),
    );
    await container.read(appUpdateProvider.notifier).check();
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 최소 버전에 못 미치면 앱이 보이지 않는다', (tester) async {
    await pumpGate(tester, minimum: const AppVersion(1, 1, 0));
    await check(tester);

    expect(find.text(AppStrings.updateRequiredTitle), findsOneWidget);
    // 덮는 것이 아니라 **갈아 끼운다.** 뒤에 남아 있으면 뒤로가기나 자동
    // 이동으로 닿을 수 있다.
    expect(find.byKey(appMark), findsNothing);
  });

  testWidgets('최소 버전 이상이면 앱이 그대로 뜬다', (tester) async {
    await pumpGate(tester, minimum: const AppVersion(1, 0, 0));
    await check(tester);

    expect(find.byKey(appMark), findsOneWidget);
    expect(find.text(AppStrings.updateRequiredTitle), findsNothing);
  });

  testWidgets('⚠️ 새 버전이 있어도 막지는 않는다', (tester) async {
    // 권장은 닫을 수 있는 안내다. 여기서 막으면 쓸 수 있는 앱이 선다.
    await pumpGate(
      tester,
      minimum: const AppVersion(1, 0, 0),
      latest: const AppVersion(1, 5, 0),
    );
    await check(tester);

    expect(find.byKey(appMark), findsOneWidget);
  });

  testWidgets('⚠️ 아직 묻지 않았으면 막지 않는다', (tester) async {
    // 못 물어본 것을 막으면 서버가 잠깐 흔들릴 때 멀쩡한 앱이 통째로 선다.
    // "판정 없이 들여보내지 않는" 책임은 스플래시가 따로 진다.
    await pumpGate(tester, minimum: const AppVersion(9, 9, 9));

    expect(find.byKey(appMark), findsOneWidget);
    expect(versions.fetchCount, 0);
  });

  group('포그라운드 복귀', () {
    /// 앱이 뒤로 갔다 돌아온다. 생명주기는 단계를 건너뛰지 못한다.
    Future<void> leaveAndReturn(WidgetTester tester) async {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ 돌아올 때 최소 버전이 올라가 있으면 막는다', (tester) async {
      await pumpGate(tester, minimum: const AppVersion(1, 0, 0));
      await check(tester);
      expect(find.byKey(appMark), findsOneWidget);

      // 서버에서 최소 버전을 올렸다. 켜 둔 앱은 그것을 모른 채 403만 받는다.
      versions.minimum = const AppVersion(1, 1, 0);
      await leaveAndReturn(tester);

      expect(find.text(AppStrings.updateRequiredTitle), findsOneWidget);
    });

    testWidgets('⚠️ 막혀 있어도 다시 묻는다 — 내려가면 풀어 준다', (tester) async {
      // 명세가 못 박은 동작이다. 다시 안 물으면 서버가 되돌려도 앱을 껐다
      // 켤 때까지 갇혀 있다.
      await pumpGate(tester, minimum: const AppVersion(1, 1, 0));
      await check(tester);
      expect(find.text(AppStrings.updateRequiredTitle), findsOneWidget);

      versions.minimum = const AppVersion(1, 0, 0);
      await leaveAndReturn(tester);

      expect(find.byKey(appMark), findsOneWidget);
    });

    testWidgets('⚠️ 못 받으면 막아 둔 것을 풀지 않는다', (tester) async {
      // 복귀할 때 한 번 실패했다고 화면을 풀면, 업데이트하지 않은 사람이
      // 그대로 들어간다. 명세도 "실패하면 쓰던 화면을 그대로 둔다"로 적었다.
      await pumpGate(tester, minimum: const AppVersion(1, 1, 0));
      await check(tester);

      versions.failure = Exception('네트워크');
      await leaveAndReturn(tester);

      expect(find.text(AppStrings.updateRequiredTitle), findsOneWidget);
    });

    testWidgets('아직 묻는 중이면 복귀가 끼어들지 않는다', (tester) async {
      await pumpGate(tester, minimum: const AppVersion(1, 0, 0));

      await leaveAndReturn(tester);

      // 스플래시가 묻기도 전에 복귀가 오면 같은 요청이 두 번 나간다.
      expect(versions.fetchCount, 0);
    });
  });
}
