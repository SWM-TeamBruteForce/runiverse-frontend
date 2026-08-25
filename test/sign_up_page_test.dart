import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';

/// 가입 2 · 정보 입력 — 이메일 인증 → 비밀번호 순으로 열리는가.
///
/// 약관 동의는 이 화면 **앞**에 있다. 여기 온 사람은 이미 동의한 사람이다.
///
/// ## `pumpAndSettle`을 못 쓰는 구간이 있다
///
/// 인증번호를 보낸 뒤에는 1초짜리 카운트다운이 돈다. 프레임이 계속 예약되므로
/// `pumpAndSettle`은 끝나지 않는다. **인증을 마치면 타이머가 멈춰** 다시 쓸 수 있다.
void main() {
  late FakeAuthRepository repository;

  setUp(() => repository = FakeAuthRepository(latency: Duration.zero));

  Future<void> pumpSignUp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // ⚠️ 이것을 빠뜨리면 **가입 성공 경로에서만** 테스트가 멈춘다.
          //
          // SecureTokenStore는 플랫폼 채널을 부르는데 테스트에는 채널이 없다.
          // 거기서 던져진 예외는 AuthException이 아니라 잡히지 않고, `_submitting`이
          // true로 남아 스피너가 영원히 돈다 — `pumpAndSettle`이 끝나지 않는다.
          // 실패 경로는 저장소를 부르지 않아 멀쩡히 통과하므로 원인을 찾기 어렵다.
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.signUp),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 타이머가 도는 동안 쓰는 정착. 프레임 몇 개만 흘린다.
  Future<void> tick(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  bool enabled(WidgetTester tester, String label) {
    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, label),
    );
    return button.onPressed != null;
  }

  Future<void> enterEmail(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField).at(0), email);
    await tester.pump();
  }

  /// 이메일 입력 → 인증번호 받기 → 번호 입력 → 확인. 여기까지 마치면 타이머가 멈춘다.
  ///
  /// [code]를 주지 않으면 **저장소가 방금 보낸 번호**를 쓴다. 메일함을 열 수 없으니
  /// 가짜 저장소의 `lastCode`가 그 자리를 대신한다.
  Future<void> verifyEmail(
    WidgetTester tester, {
    String email = 'new@example.com',
    String? code,
  }) async {
    await enterEmail(tester, email);
    await tester.tap(find.text(AppStrings.authVerifySend));
    await tick(tester);

    await tester.enterText(
      find.byType(TextField).at(1),
      code ?? repository.lastCode!,
    );
    await tick(tester);
    await tester.tap(find.text(AppStrings.authVerifyConfirm));
    await tick(tester);
  }

  testWidgets('처음에는 이메일 칸만 보인다', (tester) async {
    await pumpSignUp(tester);

    // 세 칸을 한꺼번에 보여주면 무엇부터 해야 하는지가 흐려진다.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(AppStrings.authVerifyLabel), findsNothing);
    expect(find.text(AppStrings.authPasswordLabel), findsNothing);
  });

  testWidgets('이메일이 형식에 맞아야 인증번호를 받을 수 있다', (tester) async {
    await pumpSignUp(tester);

    expect(enabled(tester, AppStrings.authVerifySend), isFalse);

    await enterEmail(tester, 'runner@');
    expect(enabled(tester, AppStrings.authVerifySend), isFalse);

    await enterEmail(tester, 'new@example.com');
    expect(enabled(tester, AppStrings.authVerifySend), isTrue);
  });

  testWidgets('번호를 받으면 인증번호 칸이 열린다', (tester) async {
    await pumpSignUp(tester);
    await enterEmail(tester, 'new@example.com');

    await tester.tap(find.text(AppStrings.authVerifySend));
    await tick(tester);

    expect(find.text(AppStrings.authVerifyLabel), findsOneWidget);
    expect(find.text(AppStrings.authVerifySent), findsOneWidget);
    // 아직 비밀번호는 묻지 않는다.
    expect(find.text(AppStrings.authPasswordLabel), findsNothing);
  });

  testWidgets('6자리를 채워야 확인 버튼이 열린다', (tester) async {
    await pumpSignUp(tester);
    await enterEmail(tester, 'new@example.com');
    await tester.tap(find.text(AppStrings.authVerifySend));
    await tick(tester);

    expect(enabled(tester, AppStrings.authVerifyConfirm), isFalse);

    await tester.enterText(find.byType(TextField).at(1), '12345');
    await tick(tester);
    expect(enabled(tester, AppStrings.authVerifyConfirm), isFalse);

    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tick(tester);
    expect(enabled(tester, AppStrings.authVerifyConfirm), isTrue);
  });

  testWidgets('번호가 틀리면 실패 문구가 뜨고 비밀번호 칸은 열리지 않는다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester, code: '000000');

    expect(find.text(AppStrings.authFailedInvalidCode), findsOneWidget);
    expect(find.text(AppStrings.authPasswordLabel), findsNothing);
  });

  testWidgets('인증에 성공하면 비밀번호 칸이 열린다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    expect(find.text(AppStrings.authVerifyDone), findsOneWidget);
    expect(find.text(AppStrings.authPasswordLabel), findsOneWidget);
    // 인증이 끝났으므로 인증번호 칸은 물러난다.
    expect(find.text(AppStrings.authVerifyLabel), findsNothing);
  });

  testWidgets('인증만으로는 가입할 수 없다 — 비밀번호가 규칙에 맞아야 한다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    expect(enabled(tester, AppStrings.authSignUpCta), isFalse);

    await tester.enterText(find.byType(TextField).at(1), 'abcdef');
    await tester.pumpAndSettle();
    expect(enabled(tester, AppStrings.authSignUpCta), isFalse);
    expect(find.text(AppStrings.authPasswordMissingKind), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'runi123!');
    await tester.pumpAndSettle();
    expect(enabled(tester, AppStrings.authSignUpCta), isTrue);
  });

  testWidgets('한글이 섞인 비밀번호로는 가입할 수 없다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    await tester.enterText(find.byType(TextField).at(1), '러너abc12!');
    await tester.pumpAndSettle();

    expect(enabled(tester, AppStrings.authSignUpCta), isFalse);
    expect(find.text(AppStrings.authPasswordDisallowedChar), findsOneWidget);
  });

  testWidgets('인증한 뒤 이메일을 고치면 인증이 풀린다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);
    expect(find.text(AppStrings.authVerifyDone), findsOneWidget);

    // A로 인증받고 B로 가입하는 구멍을 막는다.
    await enterEmail(tester, 'other@example.com');

    expect(find.text(AppStrings.authVerifyDone), findsNothing);
    expect(find.text(AppStrings.authPasswordLabel), findsNothing);
    // 왜 풀렸는지 밝히지 않으면 사용자는 가입 버튼만 쳐다본다.
    expect(find.text(AppStrings.authVerifyReset), findsOneWidget);
  });

  testWidgets('이메일을 되돌려도 인증은 풀린 채로 남는다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    // 고쳤다가 원래대로 되돌린다. 이메일 비교만으로 판정하면 여기서 통과해
    // **티켓 없이 가입 버튼이 열린다** — 눌러도 아무 일이 없다.
    await enterEmail(tester, 'other@example.com');
    await enterEmail(tester, 'new@example.com');

    expect(find.text(AppStrings.authVerifyDone), findsNothing);
    expect(find.text(AppStrings.authPasswordLabel), findsNothing);
  });

  testWidgets('이미 가입한 이메일은 번호를 받는 단계에서 막힌다', (tester) async {
    await pumpSignUp(tester);
    await enterEmail(tester, FakeAuthRepository.seedEmail);

    await tester.tap(find.text(AppStrings.authVerifySend));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedEmailTaken), findsOneWidget);
    // 번호를 다 치고 나서 막으면 한 일이 통째로 버려진다.
    expect(find.text(AppStrings.authVerifyLabel), findsNothing);
  });

  testWidgets('가입에 실패하면 인증이 풀린다', (tester) async {
    await pumpSignUp(tester);
    // 인증을 마친 **뒤에** 누군가 같은 이메일로 먼저 가입한 상황이다.
    // 드물지만 서버는 409를 주고, 그때 티켓은 이미 소비됐다.
    await verifyEmail(tester);
    repository.seedAccount(email: 'new@example.com', password: 'runi123!');

    await tester.enterText(find.byType(TextField).at(1), 'runi123!');
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedEmailTaken), findsOneWidget);
    // 티켓을 들고 있으면 다시 눌렀을 때 이유가 emailNotVerified로 바뀐다.
    // 인증 단계로 되돌려 처음부터 하게 한다.
    expect(find.text(AppStrings.authVerifyDone), findsNothing);
    expect(find.text(AppStrings.authPasswordLabel), findsNothing);
  });

  testWidgets('가입에 성공하면 프로필 등록으로 간다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    await tester.enterText(find.byType(TextField).at(1), 'runi123!');
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    // 약관은 앞에서 받았다. 남은 것은 프로필뿐이다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
  });
}
