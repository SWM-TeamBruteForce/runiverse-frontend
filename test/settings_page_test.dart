import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/settings/data/fake_settings_repository.dart';
import 'package:runiverse/features/auth/domain/login_type.dart';
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

    // 저장소에 직접 넣은 토큰이라 가짜 서버는 이것을 모른다. 알려주지 않으면
    // 자동 로그인이 만료로 끝나고 계정 섹션이 통째로 빈다.
    final auth = FakeAuthRepository(
      latency: Duration.zero,
      loginType: loginType,
    )..seedSession(accessToken: 'a-1', refreshToken: 'r-1');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          bodyProfileStoreProvider.overrideWithValue(
            InMemoryBodyProfileStore(),
          ),
          // ⚠️ 계정 유형은 이제 **auth**가 답한다. `/users/me`가 함께 싣고,
          // 설정 화면은 따로 조회하지 않는다.
          authRepositoryProvider.overrideWithValue(auth),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(latency: Duration.zero),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.settings),
      ),
    );
    await tester.pumpAndSettle();

    // ⚠️ **스플래시를 건너뛰고 설정으로 바로 들어왔다.** 실제 앱에서는 스플래시가
    // 자동 로그인을 돌려 `/users/me`를 읽어 두는데, 여기서는 그것이 없어
    // 계정 정보가 비어 있다. 같은 일을 대신 해준다.
    //
    // ⚠️ **`await`하지 않는다.** 위젯 테스트는 가짜 시계를 쓰므로 여기서 기다리면
    // `Future.delayed`가 영영 안 끝나고 테스트가 멈춘다. 시계는 `pump`가 돌린다.
    unawaited(
      ProviderScope.containerOf(
        tester.element(find.byType(RuniverseApp)),
        listen: false,
      ).read(authControllerProvider.notifier).restore(),
    );
    await tester.pumpAndSettle();
  }

  /// 설정 목록의 행 하나를 누른다.
  ///
  /// ⚠️ **먼저 화면 안으로 끌어와야 한다.** 테스트 화면은 800×600이라 목록
  /// 아래쪽 행(로그아웃·탈퇴)은 밖에 있고, 그대로 누르면 "off-screen"으로
  /// 실패한다. 행이 하나 늘 때마다 이 경계가 움직인다.
  Future<void> tapRow(WidgetTester tester, String label) async {
    final row = find.text(label);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
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

  group('고지 문서', () {
    testWidgets('⚠️ 방침과 계정삭제 행이 있다', (tester) async {
      // 구글 플레이 심사가 두 링크를 요구한다. 행이 사라지면 심사에서 막힌다.
      await pumpSettings(tester);

      expect(find.text(AppStrings.settingsPrivacy), findsOneWidget);
      expect(find.text(AppStrings.settingsAccountDeletion), findsOneWidget);
    });

    testWidgets('이용약관 행은 문서가 없어도 남아 있다', (tester) async {
      // 자리를 비워두면 문서가 생겼을 때 붙이는 것을 잊는다.
      await pumpSettings(tester);

      expect(find.text(AppStrings.settingsTerms), findsOneWidget);
    });
  });

  group('나가는 길', () {
    testWidgets('⚠️ 로그아웃하면 로그인 화면으로 간다', (tester) async {
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsSignOut);

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

      await tapRow(tester, AppStrings.settingsSignOut);
      await tester.tap(find.text(AppStrings.settingsCancel));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect((await tokens.read()).accessToken, isNotNull);
    });

    testWidgets('⚠️ 탈퇴해도 로그인 화면으로 간다', (tester) async {
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsWithdraw);

      // 시트의 확인 버튼.
      await tester.tap(find.text(AppStrings.withdrawConfirm));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authSignInCta), findsOneWidget);
      expect((await tokens.read()).accessToken, isNull);
    });

    testWidgets('탈퇴 시트에서 취소하면 계정이 남는다', (tester) async {
      await pumpSettings(tester);

      await tapRow(tester, AppStrings.settingsWithdraw);
      await tester.tap(find.text(AppStrings.settingsCancel));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.settingsTitle), findsOneWidget);
      expect((await tokens.read()).accessToken, isNotNull);
    });
  });
}
