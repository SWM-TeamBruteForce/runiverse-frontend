import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/field_action.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

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
          // 스플래시가 **토큰 복원보다 먼저** 앱 버전을 확인한다. 진짜를 두면
          // dio가 서버 주소를 찾다 죽고, 판정을 못 받은 화면은 넘어가지 않는다.
          appVersionRepositoryProvider.overrideWithValue(
            FakeAppVersionRepository(),
          ),
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
          // 스플래시가 서버 상태를 읽는다. 진짜를 두면 dio가 서버 주소를 찾다
          // 죽는다 — 테스트에는 주소가 없다.
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
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

  /// 버튼이 눌리는 상태인가.
  ///
  /// ⚠️ **두 종류가 섞여 있다.** 큰 버튼은 [AppButtonV2], 입력 칸 **안**의 작은
  /// 버튼은 [FieldActionV2]다(`인증번호 받기` `다시 받기` `변경`). 둘 다 `onPressed`가
  /// null이면 잠긴 것이라, 어느 쪽인지 찾아서 같은 것을 본다.
  bool enabled(WidgetTester tester, String label) {
    final big = find.widgetWithText(AppButtonV2, label);
    if (big.evaluate().isNotEmpty) {
      return tester.widget<AppButtonV2>(big).onPressed != null;
    }
    final small = find.widgetWithText(FieldActionV2, label);
    return tester.widget<FieldActionV2>(small).onPressed != null;
  }

  /// 이메일 칸을 고칠 수 있는가. 인증을 마치면 잠긴다.
  bool emailEnabled(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).at(0)).enabled ?? true;

  /// 이메일 칸에 커서가 있는가.
  bool emailFocused(WidgetTester tester) => tester
      .widget<EditableText>(find.byType(EditableText).at(0))
      .focusNode
      .hasFocus;

  /// 인증을 마친 뒤 비밀번호와 확인을 함께 채운다.
  ///
  /// ⚠️ **확인 칸이 생겼다**(2026-09-30). 비밀번호만 치면 CTA 가 열리지 않는다 —
  /// 서버가 확인값을 받지 않아 두 값이 다른 것을 막는 곳이 앱뿐이다.
  Future<void> enterPassword(
    WidgetTester tester,
    String password, {
    String? confirm,
  }) async {
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.enterText(find.byType(TextField).at(2), confirm ?? password);
    await tester.pumpAndSettle();
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

    await enterPassword(tester, 'abcdef');
    expect(enabled(tester, AppStrings.authSignUpCta), isFalse);
    expect(find.text(AppStrings.authPasswordMissingKind), findsOneWidget);

    await enterPassword(tester, 'runi123!');
    expect(enabled(tester, AppStrings.authSignUpCta), isTrue);
  });

  testWidgets('⚠️ 두 비밀번호가 다르면 가입할 수 없다', (tester) async {
    // 서버는 확인값을 받지 않는다. 막는 곳이 여기뿐이다.
    await pumpSignUp(tester);
    await verifyEmail(tester);

    await enterPassword(tester, 'runi123!', confirm: 'runi456!');

    expect(enabled(tester, AppStrings.authSignUpCta), isFalse);
    expect(find.text(AppStrings.authPasswordMismatch), findsOneWidget);
  });

  testWidgets('⚠️ 확인 칸이 비어 있으면 틀렸다고 하지 않는다', (tester) async {
    // 아직 안 친 것뿐이다. 치는 도중에 빨간 글씨가 뜨면 무엇이 잘못됐는지
    // 알 수 없다. 대신 버튼은 열리지 않는다.
    await pumpSignUp(tester);
    await verifyEmail(tester);

    await tester.enterText(find.byType(TextField).at(1), 'runi123!');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authPasswordMismatch), findsNothing);
    expect(enabled(tester, AppStrings.authSignUpCta), isFalse);
  });

  testWidgets('다시 같게 고치면 열린다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    await enterPassword(tester, 'runi123!', confirm: 'runi456!');
    expect(enabled(tester, AppStrings.authSignUpCta), isFalse);

    await enterPassword(tester, 'runi123!');
    expect(find.text(AppStrings.authPasswordMismatch), findsNothing);
    expect(enabled(tester, AppStrings.authSignUpCta), isTrue);
  });

  testWidgets('한글이 섞인 비밀번호로는 가입할 수 없다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    await enterPassword(tester, '러너abc12!');
    await tester.pumpAndSettle();

    expect(enabled(tester, AppStrings.authSignUpCta), isFalse);
    expect(find.text(AppStrings.authPasswordDisallowedChar), findsOneWidget);
  });

  testWidgets('인증하면 이메일 칸이 잠기고 「변경」이 생긴다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    // 잠그지 않으면 한 글자만 고쳐도 인증이 조용히 풀려 비밀번호 칸이 사라진다.
    expect(emailEnabled(tester), isFalse);
    expect(enabled(tester, AppStrings.authEmailChange), isTrue);
    expect(find.text(AppStrings.authPasswordLabel), findsOneWidget);
  });

  testWidgets('「변경」을 누르면 인증을 처음부터 다시 받는다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    await tester.tap(find.text(AppStrings.authEmailChange));
    await tester.pumpAndSettle();

    expect(emailEnabled(tester), isTrue);
    // 잠긴 칸과 풀린 칸이 똑같이 생겨, 커서가 안 가면 칸을 한 번 더 눌러야 한다.
    expect(emailFocused(tester), isTrue);
    expect(find.text('new@example.com'), findsOneWidget);
    expect(find.text(AppStrings.authVerifyDone), findsNothing);
    expect(find.text(AppStrings.authPasswordLabel), findsNothing);
    // 지난 인증번호 칸이 다시 열리면 서버가 이미 지운 번호를 눌러 보게 된다.
    expect(find.text(AppStrings.authVerifyLabel), findsNothing);
    expect(enabled(tester, AppStrings.authVerifySend), isTrue);
    // 스스로 누른 것이라 빨간 안내로 알릴 것이 없다.
    expect(find.text(AppStrings.authVerifyReset), findsNothing);
  });

  testWidgets('「변경」 뒤 다시 인증하면 친 비밀번호가 남는다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);
    await enterPassword(tester, 'runi123!');

    // 「변경」은 인증만 처음부터 다시 받게 한다. 비밀번호까지 지우면 같은 일을
    // 두 번 하게 된다.
    await tester.tap(find.text(AppStrings.authEmailChange));
    await tester.pumpAndSettle();
    await verifyEmail(tester);

    expect(enabled(tester, AppStrings.authSignUpCta), isTrue);
  });

  testWidgets('⚠️ 요청이 가는 동안에는 이메일 칸과 「변경」이 잠긴다', (tester) async {
    // 「확인」 응답을 기다리는 사이 이메일을 고치면, 응답이 예전 이메일로
    // 인증을 세워 가입 실패가 없었는데도 인증이 풀렸다는 안내가 뜬다.
    const latency = Duration(milliseconds: 100);
    repository = FakeAuthRepository(latency: latency);
    await pumpSignUp(tester);
    await enterEmail(tester, 'new@example.com');
    await tester.tap(find.text(AppStrings.authVerifySend));
    await tester.pump(latency);
    await tick(tester);
    await tester.enterText(find.byType(TextField).at(1), repository.lastCode!);
    await tick(tester);

    await tester.tap(find.text(AppStrings.authVerifyConfirm));
    await tester.pump();
    expect(emailEnabled(tester), isFalse);

    await tester.pump(latency);
    await tick(tester);
    await enterPassword(tester, 'runi123!');
    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pump();
    // 가입 요청 중에 티켓을 버리면 응답이 와도 이을 수 없다.
    expect(enabled(tester, AppStrings.authEmailChange), isFalse);

    await tester.pumpAndSettle();
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

    await enterPassword(tester, 'runi123!');
    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.authFailedEmailTaken), findsOneWidget);
    // 티켓을 들고 있으면 다시 눌렀을 때 이유가 emailNotVerified로 바뀐다.
    // 인증 단계로 되돌려 처음부터 하게 한다.
    expect(find.text(AppStrings.authVerifyDone), findsNothing);
    expect(find.text(AppStrings.authPasswordLabel), findsNothing);
    expect(find.text(AppStrings.authVerifyReset), findsOneWidget);
    // 티켓이 없으니 잠금도 풀린다 — 이메일을 고치거나 같은 이메일로 다시 받는다.
    expect(emailEnabled(tester), isTrue);
    // 쓴 번호는 서버가 지웠다. 그 칸이 다시 열리면 「확인」이 "만료됐어요"로 끝난다.
    expect(find.text(AppStrings.authVerifyLabel), findsNothing);
  });

  testWidgets('가입에 성공하면 프로필 등록으로 간다', (tester) async {
    await pumpSignUp(tester);
    await verifyEmail(tester);

    await enterPassword(tester, 'runi123!');
    await tester.tap(find.text(AppStrings.authSignUpCta));
    await tester.pumpAndSettle();

    // 약관은 앞에서 받았다. 남은 것은 프로필뿐이다.
    expect(find.byType(ProfileSetupPage), findsOneWidget);
  });
}
