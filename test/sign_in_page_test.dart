// 명암비를 구하는 `pow`가 여기 있다.
import 'dart:math' as math;

// `debugDefaultTargetPlatformOverride`가 여기 있다. material 이 재수출하지 않는다.
import 'package:flutter/foundation.dart';
// TextField를 이름으로 찾으려면 필요하다. flutter_test는 material을 재수출하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// 애플 로고에 칠한 색을 읽는다. 패키지가 `AppleLogoPainter`를 공개한다.
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_palette.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/data/fake_oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 로그인 화면 — 언제 버튼이 열리고, 실패했을 때 무엇이 보이는가.
///
/// 라우터를 태워서 띄운다. 성공했을 때 **홈으로 가는지**까지가 이 화면의 계약이라
/// 화면만 떼어놓으면 그 절반을 볼 수 없다.
/// 눌리기 전에 **보이게 한다.**
///
/// ⚠️ 로그인 화면이 시안의 사진 때문에 길어져 접힌 곳 아래로 내려가는 것이 생겼다.
/// `tester.tap`은 스크롤하지 않고, 화면 밖 위젯을 누르면 hit test 에서 죽는다.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  Future<void> pumpSignIn(
    WidgetTester tester, {
    FakeAuthRepository? repository,
    OauthCodeSource? codeSource,
  }) async {
    // 이미 약관에 동의한 기기로 시작한다. 카카오 버튼이 인가 전에 약관을 끼우므로,
    // 동의가 없으면 아래 테스트들이 전부 약관 화면에서 멈춘다.
    // **그 갈림길 자체는 `kakao_terms_test.dart`가 본다.**
    final consent = InMemoryConsentStore();
    await consent.markTermsAgreed();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 스플래시가 **토큰 복원보다 먼저** 앱 버전을 확인한다. 진짜를 두면
          // dio가 서버 주소를 찾다 죽고, 판정을 못 받은 화면은 넘어가지 않는다.
          appVersionRepositoryProvider.overrideWithValue(
            FakeAppVersionRepository(),
          ),
          // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
          // 로그인에 성공하면 토큰을 저장하므로 여기서도 갈아끼워야 한다.
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          consentStoreProvider.overrideWithValue(consent),
          // 지연이 있으면 pumpAndSettle이 실제로 기다린다. 테스트에서는 뺀다.
          // 스플래시가 서버 상태를 읽는다. 진짜를 두면 dio가 서버 주소를 찾다
          // 죽는다 — 테스트에는 주소가 없다.
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
          // 셸이 알림 배지를 그리며 앱 스트림을 만들고, 로그인돼 있으면 첫
          // 페이지도 받는다. 진짜를 두면 dio가 서버 주소를 찾다 죽는다.
          appStreamProvider.overrideWithValue(FakeAppStream()),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
          authRepositoryProvider.overrideWithValue(
            repository ?? FakeAuthRepository(latency: Duration.zero),
          ),
          // 카카오 SDK도 플랫폼 채널을 부른다. 이것 없이는 카카오 버튼을
          // 누르는 순간 테스트가 죽는다.
          oauthCodeSourceProvider.overrideWith(
            (ref, provider) => codeSource ?? FakeOauthCodeSource(),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.signIn),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// CTA가 눌리는 상태인가. [AppButtonV2]은 `onPressed`가 null이면 비활성이다.
  bool ctaEnabled(WidgetTester tester) {
    final cta = tester.widget<AppButtonV2>(
      find.widgetWithText(AppButtonV2, AppStrings.authSignInCta),
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

  /// 맨 끝 줄과 시스템 내비게이션 바 — **겹치는가.**
  ///
  /// 위를 `SafeArea`로 감싸지 않았다(사진을 상태바 뒤까지 깐다). 그래서 아래
  /// 여백도 받지 못하는데 고정값만 두면 **제스처 바가 가입하기를 덮는다.**
  group('맨 아래 줄', () {
    /// 시스템 하단 여백이 [bottom]인 기기에서 띄운다.
    Future<void> pumpWithInset(WidgetTester tester, double bottom) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      tester.view.viewPadding = FakeViewPadding(bottom: bottom * 3);
      tester.view.padding = FakeViewPadding(bottom: bottom * 3);
      addTearDown(tester.view.reset);
      await pumpSignIn(tester);
    }

    // 0 = 내비게이션 바 없음 · 24 = 제스처 바 · 48 = 3버튼 바.
    // **기기가 얼마를 주든 그만큼 비켜야 한다** — 한 값만 보면 고정값으로
    // 때운 것과 구별되지 않는다.
    for (final inset in const [0.0, 24.0, 48.0]) {
      testWidgets('⚠️ 하단 여백 $inset에서 가리지 않는다', (tester) async {
        await pumpWithInset(tester, inset);

        final link = find.text(AppStrings.authToSignUp);
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();

        final bottom = tester.getBottomLeft(link).dy;
        final safeTop = tester.view.physicalSize.height / 3 - inset;
        expect(
          bottom,
          lessThanOrEqualTo(safeTop),
          reason: '하단 여백 $inset에서 가입하기 줄이 시스템 영역으로 들어갔다',
        );
      });
    }

    testWidgets('⚠️ 여백이 커지면 그만큼 더 올라간다', (tester) async {
      // 위 검사만으로는 **바닥에 아주 큰 고정값**을 둔 것도 통과한다.
      // 두 기기의 차이가 여백의 차이와 같아야 실제로 반영한 것이다.
      await pumpWithInset(tester, 0);
      final link = find.text(AppStrings.authToSignUp);
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      final flat = tester.getBottomLeft(link).dy;

      await pumpWithInset(tester, 48);
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      final lifted = tester.getBottomLeft(link).dy;

      expect(flat - lifted, moreOrLessEquals(48, epsilon: 0.5));
    });

    testWidgets('가입하기는 primary 색이다', (tester) async {
      await pumpSignIn(tester);

      final text = tester.widget<Text>(find.text(AppStrings.authToSignUp));
      final colors = tester
          .element(find.text(AppStrings.authToSignUp))
          .appColorsV2;
      expect(text.style?.color, colors.primary);
    });
  });

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

    await tapVisible(tester, find.text(AppStrings.authSignInCta));
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

    await tapVisible(tester, find.text(AppStrings.authSignInCta));
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

    await tapVisible(tester, find.text(AppStrings.authSignInCta));
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

    await tapVisible(tester, find.text(AppStrings.authSignInCta));
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
    await tapVisible(tester, find.text(AppStrings.authSignInCta));
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

      await tapVisible(tester, find.byTooltip(AppStrings.authKakao));
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

      await tapVisible(tester, find.byTooltip(AppStrings.authKakao));
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

      await tapVisible(tester, find.byTooltip(AppStrings.authKakao));
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

      await tapVisible(tester, find.byTooltip(AppStrings.authKakao));
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

      await tapVisible(tester, find.byTooltip(AppStrings.authKakao));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authFailedEmailTaken), findsOneWidget);
    });
  });

  testWidgets('카카오에서 예상 못 한 오류가 나도 로그인 화면이 잠기지 않는다', (tester) async {
    await pumpSignIn(tester, codeSource: _ThrowingOauthCodeSource());
    await fill(
      tester,
      email: FakeAuthRepository.seedEmail,
      password: FakeAuthRepository.seedPassword,
    );
    expect(ctaEnabled(tester), isTrue);

    await tapVisible(tester, find.byTooltip(AppStrings.authKakao));
    // ⚠️ pumpAndSettle을 쓰면 안 된다. 잠긴 화면은 스피너가 영원히 돌아
    // **영영 안정되지 않고**, 단언에 닿기 전에 타임아웃으로 죽는다
    // (`docs/implementation-notes.md` §10-3). 정해진 횟수만 pump한다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 버튼 한 번에 **아무도 처리하지 않는 오류가 새어나가면 안 된다.**
    // 새어나가면 이 테스트가 그 오류로 죽는다 — 단언까지 오지도 못한다.

    // ⚠️ 여기가 버그다. 실패하면 CTA가 스피너로 바뀐 채 굳은 것이고,
    // **이메일 로그인까지 같이 막힌다** — 카카오를 한 번 잘못 누른 사람은
    // 앱을 다시 켜기 전에는 어떤 방법으로도 로그인할 수 없다.
    expect(
      find.widgetWithText(AppButtonV2, AppStrings.authSignInCta),
      findsOneWidget,
      reason: 'CTA가 사라졌다면 _busy가 true로 굳은 것이다',
    );
    expect(ctaEnabled(tester), isTrue);

    // 풀리기만 하면 되는 게 아니다. 아무 말도 없으면 사용자는 **버튼이 안 눌렸다**고
    // 읽고 같은 자리를 계속 누른다.
    expect(find.text(AppStrings.authFailedOauth), findsOneWidget);
  });

  /// 애플 타일 — **iOS에만 있다.**
  ///
  /// 안드로이드에서 누르면 패키지가 애플 웹 흐름을 열고, 그렇게 받은 토큰은
  /// 발급 대상이 번들 ID가 아니라서 **서버가 401을 돌려준다**(연동 가이드
  /// 3·6절). 앱에서는 인가가 성공처럼 보여 원인이 서버에서만 드러난다.
  ///
  /// `dart:io`의 `Platform.isIOS`를 보면 테스트에서 늘 호스트(Windows)라
  /// **두 경우 중 하나만 시험된다.** 화면이 `defaultTargetPlatform`을 보므로
  /// 여기서 둘 다 세울 수 있다.
  group('애플 타일', () {
    /// ⚠️ **`addTearDown`으로는 되돌릴 수 없다.** `testWidgets`가 본문이
    /// 끝나는 자리에서 "디버그 변수를 건드린 채 끝났는지"를 검사하는데,
    /// tearDown 은 그 뒤에 돈다. 본문 안에서 되돌려야 한다.
    Future<void> asPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        // 실패해도 되돌린다. 남으면 뒤따르는 테스트가 엉뚱한 플랫폼에서 돈다.
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('iOS에서는 뜬다', (tester) async {
      await asPlatform(TargetPlatform.iOS, () async {
        await pumpSignIn(tester);

        expect(find.byTooltip(AppStrings.authApple), findsOneWidget);
        // 나머지 둘은 그대로 있다.
        expect(find.byTooltip(AppStrings.authGoogle), findsOneWidget);
        expect(find.byTooltip(AppStrings.authKakao), findsOneWidget);
      });
    });

    testWidgets('⚠️ 안드로이드에서는 없다', (tester) async {
      await asPlatform(TargetPlatform.android, () async {
        await pumpSignIn(tester);

        expect(find.byTooltip(AppStrings.authApple), findsNothing);
        expect(find.byTooltip(AppStrings.authGoogle), findsOneWidget);
        expect(find.byTooltip(AppStrings.authKakao), findsOneWidget);
      });
    });

    /// 타일의 바탕색. [InkWell]을 담은 [Material]이 그린다.
    Color surfaceOf(WidgetTester tester, String label) => tester
        .widgetList<Material>(
          find.descendant(
            of: find.byTooltip(label),
            matching: find.byType(Material),
          ),
        )
        .first
        .color!;

    /// 애플 로고에 칠한 색. 패키지의 [AppleLogoPainter]가 들고 있다.
    ///
    /// ⚠️ **`find.byType(CustomPaint)`로는 못 찾는다.** [InkWell]과 [Material]이
    /// 잉크와 그림자를 [CustomPaint]로 그려서 여럿이 걸린다. 사과를 칠하는
    /// 화가로 가린다.
    Color appleInk(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byTooltip(AppStrings.authApple),
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is CustomPaint &&
                              widget.painter is AppleLogoPainter,
                        ),
                      ),
                    )
                    .painter!
                as AppleLogoPainter)
            .color;

    /// 애플 타일이 **왜 작아 보였는가** — 크기가 아니라 대비였다.
    ///
    /// 바탕이 검정(`#000000`)이고 다크 테마의 `bgBase`가 `#0A0A0A`라 타일의
    /// 경계가 배경에 묻었다. 보이는 것은 흰 사과뿐이어서, 옆 두 타일보다
    /// **작아 보였다.** 그래서 이 묶음은 **색의 대비**를 검사한다.
    ///
    /// 두 색의 명암비(WCAG 2.1 §1.4.11). UI 요소의 경계는 **3:1** 이상이어야
    /// 한다. 검정과 `#0A0A0A`는 1.06:1이라 한참 모자랐다.
    double contrast(Color a, Color b) {
      double channel(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4) as double;
      double luminance(Color c) =>
          0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

      final (high, low) = (luminance(a), luminance(b));
      return high > low
          ? (high + 0.05) / (low + 0.05)
          : (low + 0.05) / (high + 0.05);
    }

    testWidgets('⚠️ 애플 타일이 배경에 묻지 않는다', (tester) async {
      await asPlatform(TargetPlatform.iOS, () async {
        await pumpSignIn(tester);

        // 앱은 다크로 고정이다(`RuniverseApp`의 `themeMode`).
        final background = AppColorsV2.dark.bgBase;
        final surface = surfaceOf(tester, AppStrings.authApple);

        // 옛 값(검정)이면 1.06:1로 여기서 걸린다.
        expect(contrast(surface, background), greaterThan(3));
        // 나머지 둘도 같은 기준을 지킨다 — 애플만 고친 것이 아님을 못 박는다.
        expect(
          contrast(surfaceOf(tester, AppStrings.authGoogle), background),
          greaterThan(3),
        );
        expect(
          contrast(surfaceOf(tester, AppStrings.authKakao), background),
          greaterThan(3),
        );
      });
    });

    testWidgets('⚠️ 사과가 바탕에 묻지 않고, 검정이나 흰색이다', (tester) async {
      await asPlatform(TargetPlatform.iOS, () async {
        await pumpSignIn(tester);

        final surface = surfaceOf(tester, AppStrings.authApple);
        final ink = appleInk(tester);

        // 바탕을 흰색으로 바꾸고 로고를 흰색으로 두면 사과가 사라진다.
        expect(contrast(ink, surface), greaterThan(3));
        // ⚠️ 애플은 로고를 검정·흰색으로만 쓰라고 한다. 브랜드색으로 칠하는
        // 것은 상표를 우리가 고치는 일이다.
        expect(ink, anyOf(AppPaletteV2.black, AppPaletteV2.white));
      });
    });

    testWidgets('세 타일의 크기가 같다', (tester) async {
      // 보고된 현상이 "애플만 작아 보임"이었다. 실제로는 셋이 같은
      // `_SocialTile`이라 크기가 같다 — 그 사실을 여기 못 박아 둔다.
      await asPlatform(TargetPlatform.iOS, () async {
        await pumpSignIn(tester);

        final google = tester.getSize(find.byTooltip(AppStrings.authGoogle));
        expect(tester.getSize(find.byTooltip(AppStrings.authKakao)), google);
        expect(tester.getSize(find.byTooltip(AppStrings.authApple)), google);
      });
    });

    /// 쓸 수 없는 두 이유 — **같은 문구를 쓰면 안 된다.**
    ///
    /// 하나는 **빌드에 키가 없는 것**이라 다음 배포에서 열리고, 다른 하나는
    /// **기기의 성질**이라 기다려도 열리지 않는다. 둘 다 "아직 준비 중이에요"로
    /// 받으면, 기기 때문에 안 되는 사람이 **영영 오지 않을 것을 기다린다.**
    testWidgets('⚠️ 지원하지 않는 기기에 준비 중이라고 하지 않는다', (tester) async {
      await asPlatform(TargetPlatform.iOS, () async {
        await pumpSignIn(
          tester,
          codeSource: FakeOauthCodeSource(
            failure: AuthFailure.oauthNotSupported,
          ),
        );

        await tapVisible(tester, find.byTooltip(AppStrings.authApple));
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.authSocialUnsupported), findsOneWidget);
        expect(find.text(AppStrings.authSocialComingSoon), findsNothing);
      });
    });

    testWidgets('키가 없는 빌드는 그대로 준비 중이라고 한다', (tester) async {
      // 이 줄이 위의 뜻을 지킨다. 둘을 합쳐도 위만 보면 통과해 버린다.
      await pumpSignIn(
        tester,
        codeSource: FakeOauthCodeSource(failure: AuthFailure.oauthUnavailable),
      );

      await tapVisible(tester, find.byTooltip(AppStrings.authKakao));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.authSocialComingSoon), findsOneWidget);
      expect(find.text(AppStrings.authSocialUnsupported), findsNothing);
    });

    testWidgets('⚠️ 누르면 애플 제공자로 인가한다', (tester) async {
      // 로고만 있는 타일이라 **엉뚱한 제공자에 이어져도 화면만 보고는 모른다.**
      // 서버 경로가 제공자 이름으로 만들어지므로 어긋나면 404가 된다.
      final codeSource = FakeOauthCodeSource();
      await asPlatform(TargetPlatform.iOS, () async {
        await pumpSignIn(tester, codeSource: codeSource);

        await tapVisible(tester, find.byTooltip(AppStrings.authApple));
        await tester.pumpAndSettle();
      });

      expect(codeSource.lastProvider, OauthProvider.apple);
    });
  });
}

/// SDK가 초기화되지 않았을 때 실제로 올라오는 것은 `Exception`이 아니라 `Error`다
/// (`LateInitializationError`). 그래서 `KakaoCodeSource`의 `on Exception`에도,
/// `AuthController`의 `on AuthException`에도 걸리지 않고 화면까지 그대로 올라온다.
/// 그 상황을 같은 모양으로 만든다.
class _ThrowingOauthCodeSource implements OauthCodeSource {
  @override
  Future<OauthAuthorization> authorize(OauthProvider provider) async {
    throw StateError('SDK가 초기화되지 않았다');
  }
}
