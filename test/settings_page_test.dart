import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/settings/data/fake_settings_repository.dart';
import 'package:runiverse/features/settings/domain/login_type.dart';
import 'package:runiverse/features/settings/presentation/settings_provider.dart';

/// 설정 화면 — **계정 유형에 따른 분기**와 **나가는 길**.
///
/// ## 왜 나가는 길을 테스트하나
///
/// 라우터에 인증 `redirect`가 아직 없다. `AppShell`의 관문도 `AuthSignedIn`일
/// 때만 서는데 이 화면은 **셸 밖**이라 그 앞도 지나지 않는다.
/// **화면이 직접 내보내지 않으면 로그아웃한 사람이 설정 화면에 그대로 남는다.**
void main() {
  late InMemoryTokenStore tokens;

  Future<void> pumpSettings(
    WidgetTester tester, {
    LoginType? loginType = LoginType.local,
  }) async {
    tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(latency: Duration.zero),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(
              latency: Duration.zero,
              loginType: loginType,
            ),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.settings),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('비밀번호 메뉴 분기', () {
    testWidgets('로컬 계정이면 보인다', (tester) async {
      await pumpSettings(tester);

      expect(find.text(AppStrings.settingsPassword), findsOneWidget);
    });

    testWidgets('⚠️ 카카오 계정이면 숨는다', (tester) async {
      // 보여줬다가 409를 맞는 것보다 안 보이는 편이 낫다.
      await pumpSettings(tester, loginType: LoginType.kakao);

      expect(find.text(AppStrings.settingsPassword), findsNothing);
    });

    testWidgets('⚠️ 계정 유형을 모르면 숨는다', (tester) async {
      // 서버가 새 제공자를 보냈다. 모르는 것은 대개 소셜이다.
      await pumpSettings(tester, loginType: null);

      expect(find.text(AppStrings.settingsPassword), findsNothing);
      expect(find.text(AppStrings.settingsLoginUnknown), findsOneWidget);
    });
  });

  group('나가는 길', () {
    testWidgets('⚠️ 로그아웃하면 로그인 화면으로 간다', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(AppStrings.settingsSignOut));
      await tester.pumpAndSettle();

      // 다이얼로그의 확인 버튼. 행과 같은 문구라 마지막 것을 누른다.
      await tester.tap(find.text(AppStrings.settingsSignOut).last);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsTitle), findsNothing);
      expect(find.text(AppStrings.authSignInCta), findsOneWidget);
      // 토큰도 지워져야 한다. 화면만 옮기고 남겨두면 다음에 켤 때 되살아난다.
      expect((await tokens.read()).accessToken, isNull);
    });

    testWidgets('취소하면 그대로 남는다', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(AppStrings.settingsSignOut));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.settingsCancel));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect((await tokens.read()).accessToken, isNotNull);
    });

    testWidgets('⚠️ 탈퇴해도 로그인 화면으로 간다', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(AppStrings.settingsWithdraw));
      await tester.pumpAndSettle();

      // 시트의 확인 버튼.
      await tester.tap(find.text(AppStrings.withdrawConfirm));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authSignInCta), findsOneWidget);
      expect((await tokens.read()).accessToken, isNull);
    });

    testWidgets('탈퇴 시트에서 취소하면 계정이 남는다', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text(AppStrings.settingsWithdraw));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.settingsCancel));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect((await tokens.read()).accessToken, isNotNull);
    });
  });
}
