import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
import 'package:runiverse/features/profile/presentation/profile_page.dart';

/// 프로필 탭(S22) — 서버 값이 화면에 닿는가, 없을 때 무엇을 하는가.
///
/// 라우터를 태워서 띄운다. 유도 시트의 CTA가 **첫 로그인 때와 같은 화면**을 여는지가
/// 이 화면의 계약이라, 화면만 떼어놓으면 그 절반을 볼 수 없다.
void main() {
  /// 프로필 탭을 띄운다.
  ///
  /// [onboarded]가 프로필을 채운 사람인지다. 값은 `GET /users/me`에서 오고,
  /// 가짜 저장소가 그 답을 흉내 낸다.
  Future<void> pumpProfile(
    WidgetTester tester, {
    required bool onboarded,
    bool meFails = false,
  }) async {
    final repository = FakeAuthRepository(latency: Duration.zero);
    const email = 'runner@example.com';
    repository.seedAccount(
      email: email,
      password: 'runi123!',
      isOnboarded: onboarded,
    );
    final session = repository.issueSession(email: email);
    final store = InMemoryTokenStore();
    await store.saveSession(
      userId: session.userId,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      isOnboarded: onboarded,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(store),
          consentStoreProvider.overrideWithValue(InMemoryConsentStore()),
          authRepositoryProvider.overrideWithValue(
            meFails ? _MeFailsRepository(repository) : repository,
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.profile),
      ),
    );
    await tester.pumpAndSettle();

    // ⚠️ 스플래시를 건너뛰고 탭으로 바로 들어왔다. 그래서 아무도 `restore()`를
    // 부르지 않았고 상태가 `AuthUnknown`에 머문다 — 실제 앱에서는 스플래시가
    // 부른다. 여기서 대신 부른다.
    ProviderScope.containerOf(
      tester.element(find.byType(ProfilePage)),
    ).read(authControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
  }

  testWidgets('프로필을 채운 사람은 서버가 준 닉네임이 보인다', (tester) async {
    await pumpProfile(tester, onboarded: true);

    // 화면이 직접 부르지 않는다. `AuthController`가 부른 `/users/me`의 답이
    // 상태에 담겨 여기까지 온다.
    expect(find.textContaining('러너-runner'), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameEmpty), findsNothing);
  });

  testWidgets('프로필을 안 채운 사람은 빈 상태 문구가 보인다', (tester) async {
    await pumpProfile(tester, onboarded: false);

    // 빈 문자열이나 "알 수 없음"을 그리지 않는다. 값을 못 불러온 것으로 읽힌다.
    expect(find.text(AppStrings.profileNicknameEmpty), findsWidgets);
  });

  testWidgets('⚠️ 채운 사람은 /me가 실패해도 완성하라는 말을 듣지 않는다', (tester) async {
    // 에뮬레이터에서 실제로 겪은 것이다. `/users/me`가 404로 실패하자
    // **이미 프로필을 채운 계정에** "프로필을 완성해주세요"가 떴다.
    //
    // 닉네임이 없는 이유가 둘("안 채웠다" · "못 불러왔다")인데 화면이
    // 그것을 가르지 않으면 이렇게 된다.
    await pumpProfile(tester, onboarded: true, meFails: true);

    expect(find.text(AppStrings.profileNicknameEmpty), findsNothing);
    expect(find.text(AppStrings.profileSheetCta), findsNothing);
  });

  testWidgets('⚠️ 프로필이 없으면 유도 시트가 뜬다', (tester) async {
    await pumpProfile(tester, onboarded: false);

    expect(find.text(AppStrings.profileSheetCta), findsOneWidget);
  });

  testWidgets('프로필을 채웠으면 시트가 뜨지 않는다', (tester) async {
    await pumpProfile(tester, onboarded: true);

    // 이미 채운 사람을 막아서면 안내가 아니라 방해다.
    expect(find.text(AppStrings.profileSheetCta), findsNothing);
  });

  testWidgets('⚠️ 시트의 CTA는 첫 로그인 때와 같은 화면을 연다', (tester) async {
    await pumpProfile(tester, onboarded: false);

    await tester.tap(find.text(AppStrings.profileSheetCta));
    await tester.pumpAndSettle();

    // 프로필을 받는 곳이 둘이면 규칙도 둘이 되고, 한쪽만 고치는 사고가 난다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
  });

  testWidgets('시트는 닫을 수 있고 닫으면 다시 뜨지 않는다', (tester) async {
    await pumpProfile(tester, onboarded: false);

    await tester.tap(find.text(AppStrings.profileSheetDismiss));
    await tester.pumpAndSettle();

    // 닫히지 않는 안내는 안내가 아니라 벽이다.
    expect(find.text(AppStrings.profileSheetCta), findsNothing);
    // 다시 그려져도 되살아나지 않는다 — `build`는 한 번만 불리는 자리가 아니다.
    await tester.pump();
    expect(find.text(AppStrings.profileSheetCta), findsNothing);
  });

  testWidgets('컬렉션 10범주가 전부 잠긴 채로 선다', (tester) async {
    await pumpProfile(tester, onboarded: true);

    for (final label in const [
      AppStrings.hueDistance,
      AppStrings.hueSpeed,
      AppStrings.hueEndurance,
      AppStrings.hueConsistency,
      AppStrings.hueCadence,
      AppStrings.hueInterval,
      AppStrings.hueHills,
      AppStrings.hueRecovery,
      AppStrings.hueCompany,
      AppStrings.hueAdversity,
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label 칸이 없다');
    }

    // 분모는 10범주 × 셰이드 3 = 30이다.
    expect(
      find.text(
        AppStrings.profileCollected(
          0,
          RunHue.values.length * RunPalette.shadeCount,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('⚠️ 팔로워·팔로잉은 눌리지 않는다', (tester) async {
    await pumpProfile(tester, onboarded: true);

    // 서버에 팔로우 기능이 없다. 누를 수 있게 만들면 반응이 없을 때
    // 고장으로 읽힌다.
    expect(
      find.ancestor(
        of: find.text(AppStrings.profileFollowers),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });
}

/// `/users/me`만 실패하는 저장소. 나머지는 [inner]에 맡긴다.
///
/// 서버에 엔드포인트가 아직 없어 실제로 404가 나는 상황을 그대로 만든다.
class _MeFailsRepository implements AuthRepository {
  _MeFailsRepository(this.inner);

  final AuthRepository inner;

  @override
  Future<CurrentUser> fetchCurrentUser(String accessToken) =>
      throw const AuthException(AuthFailure.server);

  @override
  Future<AuthTokens> refresh(String refreshToken) =>
      inner.refresh(refreshToken);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => inner.signIn(email: email, password: password);

  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) =>
      inner.signUp(verificationTicket: verificationTicket, password: password);

  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) => inner.signInWithOauth(provider: provider, authorization: authorization);

  @override
  Future<void> sendVerificationCode(String email) =>
      inner.sendVerificationCode(email);

  @override
  Future<String> verifyCode({required String email, required String code}) =>
      inner.verifyCode(email: email, code: code);

  @override
  Future<void> signOut() => inner.signOut();
}
