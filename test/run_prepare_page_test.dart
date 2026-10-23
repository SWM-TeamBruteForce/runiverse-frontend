import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/presentation/run_prepare_page.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 출발 준비 — **신호를 받기 전에는 출발하지 못한다.**
///
/// 이 잠금이 이 화면의 존재 이유다. GPS가 위성을 잡기 전에 출발하면 초반 거리가
/// 통째로 빠지고, 사용자는 기록이 짧게 나온 이유를 알 수 없다.
void main() {
  late FakeLocationRepository location;

  Future<void> pumpPrepare(
    WidgetTester tester, {
    LocationAccess access = LocationAccess.granted,
  }) async {
    location = FakeLocationRepository(access: access);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(location),
          // 준비 화면이 들어올 때 상태를 다시 읽는다. 진짜 HTTP를
          // 열지 않게 갈아 끼운다 — 쉬는 중이라 막지 않는다.
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RunPreparePage(),
        ),
      ),
    );
    // 권한을 묻는 것이 첫 프레임 뒤로 미뤄져 있다.
    await tester.pumpAndSettle();
  }

  GeoPoint point() => GeoPoint(
    latitude: 37.5665,
    longitude: 126.9780,
    recordedAt: DateTime(2026, 8, 25, 19),
    accuracy: 5,
  );

  AppButtonV2 startButton(WidgetTester tester) => tester.widget<AppButtonV2>(
    find.widgetWithText(AppButtonV2, AppStrings.runStartCta),
  );

  testWidgets('⚠️ 첫 신호를 받기 전에는 시작이 잠긴다', (tester) async {
    await pumpPrepare(tester);

    expect(startButton(tester).onPressed, isNull);
    // 잠긴 이유를 글로 말한다 — 색만으로 알리지 않는다(정본 C9).
    expect(find.text(AppStrings.runWaitingFix), findsOneWidget);
    expect(find.text(AppStrings.runWaitingFixWhy), findsOneWidget);
  });

  testWidgets('좌표가 들어오면 시작이 열린다', (tester) async {
    await pumpPrepare(tester);

    location.emit(point());
    await tester.pumpAndSettle();

    expect(startButton(tester).onPressed, isNotNull);
    expect(find.text(AppStrings.runFixReady), findsOneWidget);
  });

  testWidgets('권한이 없으면 설정으로 보낸다', (tester) async {
    await pumpPrepare(tester, access: LocationAccess.deniedForever);

    expect(find.text(AppStrings.runPermissionTitle), findsOneWidget);

    await tester.tap(
      find.widgetWithText(AppButtonV2, AppStrings.runPermissionOpenSettings),
    );
    await tester.pumpAndSettle();

    expect(location.openSettingsCount, 1);
  });

  /// 설정에 다녀온 사람을 받는가.
  ///
  /// iOS는 한 번 거절하면 곧바로 `deniedForever`라 앱에서 다시 물을 길이 없다 —
  /// **설정 앱에 다녀와야** 한다. 권한을 화면에 들어올 때 한 번만 읽으면, 켜고
  /// 돌아와도 "위치 권한이 필요해요"가 그대로 남는다. 홈으로 나갔다 다시
  /// 들어와야 풀렸다.
  group('설정에 다녀오면', () {
    /// 앱이 뒤로 갔다 돌아온다. **곧장 `resumed`로 보낼 수 없다** —
    /// 생명주기는 단계를 건너뛰지 못한다.
    Future<void> leaveAndReturn(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    testWidgets('⚠️ 권한을 켜고 오면 안내가 사라진다', (tester) async {
      await pumpPrepare(tester, access: LocationAccess.deniedForever);
      expect(find.text(AppStrings.runPermissionTitle), findsOneWidget);

      // 설정 앱에서 켜고 돌아온다.
      location.access = LocationAccess.granted;
      await leaveAndReturn(tester);

      // 화면을 나갔다 들어와야만 풀리던 것이 이 자리다.
      expect(find.text(AppStrings.runPermissionTitle), findsNothing);
    });

    testWidgets('⚠️ 켜지 않고 오면 안내가 남는다', (tester) async {
      await pumpPrepare(tester, access: LocationAccess.deniedForever);

      await leaveAndReturn(tester);

      // 다시 읽기는 하되, 답이 그대로면 화면도 그대로여야 한다.
      expect(find.text(AppStrings.runPermissionTitle), findsOneWidget);
    });

    testWidgets('⚠️ 이미 허용된 상태면 다시 묻지 않는다', (tester) async {
      // 달리는 중에 앱을 다시 띄울 때마다 `prepare()`를 부르면 위치 구독을
      // 끊고 새로 연다 — 러닝이 끊긴다.
      await pumpPrepare(tester);
      expect(location.ensureAccessCount, 1);

      await leaveAndReturn(tester);

      expect(location.ensureAccessCount, 1);
    });
  });

  testWidgets('⚠️ 기기의 위치 기능이 꺼진 것과 권한 거부를 갈라 말한다', (tester) async {
    // 묶으면 설정에서 권한을 켜고 와도 여전히 안 되는 이유를 알 수 없다.
    await pumpPrepare(tester, access: LocationAccess.serviceDisabled);

    expect(find.text(AppStrings.runServiceDisabled), findsOneWidget);
    expect(find.text(AppStrings.runPermissionTitle), findsNothing);
  });
}
