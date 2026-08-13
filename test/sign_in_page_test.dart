// TextField를 이름으로 찾으려면 필요하다. flutter_test는 material을 재수출하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/data/fake_oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';

/// 로그인 화면 — 언제 버튼이 열리고, 실패했을 때 무엇이 보이는가.
///
/// 라우터를 태워서 띄운다. 성공했을 때 **홈으로 가는지**까지가 이 화면의 계약이라
/// 화면만 떼어놓으면 그 절반을 볼 수 없다.
void main() {
  Future<void> pumpSignIn(
    WidgetTester tester, {
    FakeAuthRepository? repository,
    FakeOauthCodeSource? codeSource,
  }) async {
    // 이미 약관에 동의한 기기로 시작한다. 카카오 버튼이 인가 전에 약관을 끼우므로,
    // 동의가 없으면 아래 테스트들이 전부 약관 화면에서 멈춘다.
    // **그 갈림길 자체는 `kakao_terms_test.dart`가 본다.**
    final consent = InMemoryConsentStore();
    await consent.markTermsAgreed();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
          // 로그인에 성공하면 토큰을 저장하므로 여기서도 갈아끼워야 한다.
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          consentStoreProvider.overrideWithValue(consent),
          // 지연이 있으면 pumpAndSettle이 실제로 기다린다. 테스트에서는 뺀다.
          authRepositoryProvider.overrideWithValue(
            repository ?? FakeAuthRepository(latency: Duration.zero),
          ),
          // 카카오 SDK도 플랫폼 채널을 부른다. 이것 없이는 카카오 버튼을
          // 누르는 순간 테스트가 죽는다.
          oauthCodeSourceProvider.overrideWithValue(
            codeSource ?? FakeOauthCodeSource(),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.signIn),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// CTA가 눌리는 상태인가. [AppButton]은 `onPressed`가 null이면 비활성이다.
  bool ctaEnabled(WidgetTester tester) {
    final cta = tester.widget<AppButton>(
      find.widgetWithText(AppButton, AppStrings.authSignInCta),
    );
    return cta.onPressed != null;
  }

  Future<void> fill(
    WidgetTester tester, {
    required String email,
    required String password,
  }) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.pumpAndSettle();
  }

  testWidgets('아무것도 입력하지 않으면 로그인할 수 없다', (tester) async {
    await pumpSignIn(tester);

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('이메일 형식이 아니면 로그인할 수 없다', (tester) async {
    await pumpSignIn(tester);
    await fill(tester, email: 'runner@', password: 'runi123!');

    expect(ctaEnabled(tester), isFalse);
  });

  testWidgets('이메일과 비밀번호가 채워지면 로그인할 수 있다', (tester) async {
    await pumpSignIn(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );

    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('한영 변환을 깜빡한 이메일은 버튼이 열리지 않는다', (tester) async {
    await pumpSignIn(tester);
    // `runner`를 한글 자판으로 치면 이런 것이 들어간다.
    // 통과시키면 버튼이 켜지고, 눌러본 뒤에야 틀린 것을 알게 된다.
    await fill(tester, email: 'ㄱㅕㅜㅜㄷㄱ@example.com', password: 'runi123!');

    expect(ctaEnabled(tester), isFalse);
    expect(find.text(AppStrings.authEmailInvalid), findsOneWidget);
  });

  testWidgets('로그인 화면은 비밀번호 규칙을 따지지 않는다', (tester) async {
    await pumpSignIn(tester);
    // 규칙이 바뀌기 전에 만든 계정은 지금 규칙을 통과하지 못할 수 있다.
    // 로그인에서 규칙을 들이대면 그 사람은 자기 계정에 영영 못 들어간다.
    await fill(tester, email: FakeAuthRepository.seedEmail, password: 'a');

    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('한글 비밀번호는 제출까지 가고 서버 판정으로 막힌다', (tester) async {
    await pumpSignIn(tester);
    // 로그인 화면은 비밀번호 규칙을 따지지 않는다. 그래서 한글도 버튼이 열리고,
    // 저장된 값과 다르다는 이유로 막힌다 — "형식이 틀렸다"가 아니라 "안 맞는다"여야 한다.
    await fill(tester, email: FakeAuthRepository.seedEmail, password: '러너러너러너');
    expect(ctaEnabled(tester), isTrue);

    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedCredentials), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('비밀번호가 틀리면 실패 문구가 뜬다', (tester) async {
    await pumpSignIn(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: 'wrong123!',
    );

    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedCredentials), findsOneWidget);
    // 실패했는데 화면이 넘어가면 안 된다.
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('로그인에 성공하면 홈으로 간다', (tester) async {
    await pumpSignIn(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );

    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('프로필을 안 채웠으면 홈이 아니라 폼으로 간다', (tester) async {
    final repository = FakeAuthRepository(latency: Duration.zero);
    // 가입은 했지만 프로필을 안 채운 계정. isOnboarded가 false로 온다.
    //
    // ⚠️ signUp()을 쓰면 안 된다. testWidgets는 가짜 시간 위에서 도는데
    // pumpWidget 전에 Future를 기다리면 시간을 진행시킬 pump가 없어 멈춘다.
    repository.seedAccount(email: 'new@example.com', password: 'runi123!');

    await pumpSignIn(tester, repository: repository);
    await fill(tester, email: 'new@example.com', password: 'runi123!');

    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    // 프로필은 **있어야 쓸 수 있다.** 매칭도 기록도 그 값들 위에 선다.
    // 건너뛴 사람이 다음 로그인에 폼을 다시 보는 것은 받아들인 결과다 —
    // 기기에 "한 번 보여줬다"를 남기지 않기로 했다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('다시 입력하면 이전 실패 문구가 사라진다', (tester) async {
    await pumpSignIn(tester);
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: 'wrong123!',
    );
    await tester.tap(find.text(AppStrings.authSignInCta));
    await tester.pumpAndSettle();

    // 고치는 중에도 빨간 글씨가 남아 있으면 방금 고친 것이 반영됐는지 알 수 없다.
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );

    expect(find.text(AppStrings.authFailedCredentials), findsNothing);
  });

  group('카카오 로그인', () {
    testWidgets('처음 들어오면 프로필 폼으로 간다', (tester) async {
      // 카카오는 **가입과 로그인이 한 경로다.** 계정이 없으면 서버가 그 자리에서
      // 만들고 isOnboarded=false로 답한다. 그러니 첫 로그인은 이메일의 *가입*이다.
      await pumpSignIn(tester);

      await tester.tap(find.widgetWithText(AppButton, AppStrings.authKakao));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileSetupPage), findsOneWidget);
    });

    testWidgets('프로필을 채운 계정이면 홈으로 간다', (tester) async {
      final repository = FakeAuthRepository(latency: Duration.zero);
      // 예전에 카카오로 들어와 프로필까지 채운 사람이다.
      repository.seedOauthAccount(
        code: 'fake-code',
        email: 'kakao-done@example.com',
        isOnboarded: true,
      );

      await pumpSignIn(tester, repository: repository);

      await tester.tap(find.widgetWithText(AppButton, AppStrings.authKakao));
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('취소하면 아무 문구도 뜨지 않는다', (tester) async {
      // ⚠️ 이 화면에서 가장 중요한 동작이다. 스스로 그만둔 사람에게 오류를
      // 보여주면 무언가 잘못된 것처럼 읽힌다.
      await pumpSignIn(
        tester,
        codeSource: FakeOauthCodeSource(failure: AuthFailure.oauthCancelled),
      );

      await tester.tap(find.widgetWithText(AppButton, AppStrings.authKakao));
      await tester.pumpAndSettle();

      // 로그인 화면에 그대로 머문다.
      expect(find.byType(HomePage), findsNothing);
      // 실패 문구가 하나도 없어야 한다.
      expect(find.text(AppStrings.authFailedOauth), findsNothing);
      expect(find.text(AppStrings.authFailedUnknown), findsNothing);
    });

    testWidgets('인가에 실패하면 이유를 알린다', (tester) async {
      await pumpSignIn(
        tester,
        codeSource: FakeOauthCodeSource(failure: AuthFailure.oauthFailed),
      );

      await tester.tap(find.widgetWithText(AppButton, AppStrings.authKakao));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authFailedOauth), findsOneWidget);
    });

    testWidgets('이메일이 겹치면 이메일 로그인으로 안내한다', (tester) async {
      // 서버가 자동 연동하지 않는다. "이미 가입했다"만으로는 갈 곳을 모른다.
      final repository = FakeAuthRepository(latency: Duration.zero);
      repository.seedAccount(email: 'taken@example.com', password: 'runi123!');
      repository.seedOauthAccount(
        code: 'fake-code',
        email: 'taken@example.com',
      );

      await pumpSignIn(tester, repository: repository);

      await tester.tap(find.widgetWithText(AppButton, AppStrings.authKakao));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authFailedOauthEmailTaken), findsOneWidget);
    });
  });
}
