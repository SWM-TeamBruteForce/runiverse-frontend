import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/presentation/run_prepare_page.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

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
        overrides: [locationRepositoryProvider.overrideWithValue(location)],
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

  AppButton startButton(WidgetTester tester) => tester.widget<AppButton>(
    find.widgetWithText(AppButton, AppStrings.runStartCta),
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
      find.widgetWithText(AppButton, AppStrings.runPermissionOpenSettings),
    );
    await tester.pumpAndSettle();

    expect(location.openSettingsCount, 1);
  });

  testWidgets('⚠️ 기기의 위치 기능이 꺼진 것과 권한 거부를 갈라 말한다', (tester) async {
    // 묶으면 설정에서 권한을 켜고 와도 여전히 안 되는 이유를 알 수 없다.
    await pumpPrepare(tester, access: LocationAccess.serviceDisabled);

    expect(find.text(AppStrings.runServiceDisabled), findsOneWidget);
    expect(find.text(AppStrings.runPermissionTitle), findsNothing);
  });
}
