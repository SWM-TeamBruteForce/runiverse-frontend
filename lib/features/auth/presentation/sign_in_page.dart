import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/app_input.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/email_rule.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/auth/presentation/password_field.dart';

/// 로그인 (S02.5).
///
/// **정본 와이어프레임의 S02.5는 소셜 버튼 셋과 하단 링크뿐이다.**
/// 백엔드가 이메일·비밀번호 방식을 요구해 입력칸을 이 화면에 합쳤다.
/// 방식 선택 화면을 따로 두면 탭이 한 번 더 필요한데, 실제로 고를 것은 셋뿐이라
/// 한 화면에 다 보이는 편이 짧다.
///
/// ## 뒤로가기 버튼이 없다
///
/// 온보딩 소개에서 `go`로 들어와 스택이 비어 있다. 되돌아갈 곳이 없다.
/// 가입 흐름(약관 → 정보 입력)은 `push`로 쌓이므로 그쪽에는 뒤로가기가 있다.
///
/// ## 비밀번호 규칙을 검사하지 않는다
///
/// 규칙(6~16자, 3종 혼합)은 **가입할 때만** 본다. 로그인에서 들이대면, 규칙이 바뀌기 전에
/// 만든 계정의 주인이 자기 비밀번호를 정확히 치고도 막힌다.
/// 비어 있지 않은지만 본다.
///
/// ## 로딩·실패를 provider에 올리지 않는다
///
/// "버튼이 도는 중"은 이 화면이 떠 있는 동안만 의미 있는 값이다.
/// 앱 전체의 인증 상태(`authControllerProvider`)와 섞으면, 로그인 실패가
/// 앱을 로그아웃시키는 식의 사고가 난다.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  AuthFailure? _failure;

  @override
  void dispose() {
    // 컨트롤러를 버리지 않으면 화면을 떠난 뒤에도 메모리에 남는다.
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && EmailRule.of(_email.text).isValid && _password.text.isNotEmpty;

  /// 입력이 바뀌면 이전 실패 문구를 지운다.
  /// 고치는 중에도 빨간 글씨가 남아 있으면 무엇이 반영됐는지 알 수 없다.
  void _onChanged(String _) {
    setState(() => _failure = null);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _busy = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .signIn(email: _email.text.trim(), password: _password.text);

    // await 사이에 화면이 사라졌을 수 있다. setState나 context를 쓰기 전에 반드시 본다.
    if (!mounted) return;

    setState(() {
      _busy = false;
      _failure = failure;
    });

    if (failure == null) _goAfterSignIn();
  }

  /// 로그인에 성공했다. 어디로 갈 것인가.
  ///
  /// **프로필이 없으면 폼이다.** 매칭도 기록도 그 값들 위에 서므로 채워야 쓸 수 있다.
  ///
  /// 이메일과 카카오가 이 한 곳을 함께 쓴다 — 나누면 "로그인 방식에 따라 도착지가
  /// 다르다"는 규칙이 생기고, 한쪽만 고치는 사고가 난다. 스플래시도 같은 기준이다.
  void _goAfterSignIn() {
    final state = ref.read(authControllerProvider);
    final isOnboarded = state is AuthSignedIn && state.isOnboarded;

    // go는 스택을 통째로 갈아치운다. 도착한 뒤 뒤로 눌러 로그인으로 돌아가면 안 된다.
    context.go(isOnboarded ? AppRoutes.home : AppRoutes.profileSetup);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final emailStatus = EmailRule.of(_email.text);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space8,
                  AppSpacing.space5,
                  AppSpacing.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.authSignInTitle,
                      style: AppTypography.h1.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space7),

                    AppInput(
                      controller: _email,
                      label: AppStrings.authEmailLabel,
                      hint: AppStrings.authEmailHint,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: _onChanged,
                      // 입력하는 도중에 "형식이 아니에요"가 뜨면 안 된다.
                      // 아직 다 치지 않았을 뿐이다. 빈 칸도 오류가 아니다.
                      tone: emailStatus == EmailStatus.invalid
                          ? AppInputTone.error
                          : AppInputTone.neutral,
                      helper: emailStatus == EmailStatus.invalid
                          ? AppStrings.authEmailInvalid
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.space5),

                    PasswordField(
                      controller: _password,
                      label: AppStrings.authPasswordLabel,
                      textInputAction: TextInputAction.done,
                      onChanged: _onChanged,
                      onSubmitted: (_) => _submit(),
                    ),

                    if (_failure != null) ...[
                      const SizedBox(height: AppSpacing.space4),
                      _FailureNotice(failure: _failure!),
                    ],

                    const SizedBox(height: AppSpacing.space6),
                    // 높이를 고정해 로딩 중에 아래 버튼들이 밀려 올라가지 않게 한다.
                    SizedBox(
                      height: AppButtonSize.lg.height,
                      child: _busy
                          ? Center(
                              child: SizedBox.square(
                                dimension: AppSpacing.space6,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.primary,
                                ),
                              ),
                            )
                          : AppButton(
                              label: AppStrings.authSignInCta,
                              onPressed: _canSubmit ? _submit : null,
                            ),
                    ),

                    const SizedBox(height: AppSpacing.space6),
                    const _OrDivider(),
                    const SizedBox(height: AppSpacing.space6),

                    // 카카오·애플을 지우지 않는다. 정본에 셋 다 있고, 나중에 붙일 때
                    // 레이아웃을 다시 잡지 않아도 된다. **회색으로 잠그지도 않는다** —
                    // 잠긴 버튼이 둘이면 앱이 미완성으로 읽힌다. 눌리고, 준비 중임을 알린다.
                    AppButton(
                      label: AppStrings.authKakao,
                      variant: AppButtonVariant.secondary,
                      onPressed: _busy ? null : _startKakao,
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    AppButton(
                      label: AppStrings.authApple,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => _notReady(context),
                    ),

                    const SizedBox(height: AppSpacing.space6),
                    AppButton(
                      label: AppStrings.authToSignUp,
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.md,
                      // 가입은 **약관 동의부터** 시작한다. 동의를 받기 전에
                      // 이메일·비밀번호를 받아두면 동의 없이 개인정보를 쥐게 된다.
                      //
                      // push라 뒤로가기 한 번에 로그인으로 돌아온다.
                      onPressed: () => context.push(AppRoutes.terms),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 카카오 버튼이 부르는 첫 걸음. **인가보다 약관이 먼저다.**
  ///
  /// 카카오 화면에서 받는 동의는 *카카오가 우리에게 이메일을 넘기는 것*에 대한
  /// 동의다. 우리가 서비스를 제공하고 개인정보를 수집하는 것에 대한 동의는 아니다.
  ///
  /// ⚠️ **순서를 바꾸면 안 된다.** 인가가 끝나면 서버가 곧바로 계정을 만들고
  /// 이메일을 저장한다. 그 뒤에 약관을 보이면 이미 수집한 뒤다.
  ///
  /// 한 번 동의하면 기기에 남아 다음부터 건너뛴다. 기기 단위라 재설치하면 다시
  /// 묻는데, 서버가 `termsAgreed`를 저장하면 그 한계가 사라진다.
  Future<void> _startKakao() async {
    final agreedBefore = await ref.read(consentStoreProvider).hasAgreedTerms();
    if (!mounted) return;

    if (agreedBefore) {
      await _signInWithKakao();
      return;
    }

    // 약관 화면은 **동의를 기록하고 `true`를 돌려주기만 한다.** 카카오 SDK를
    // 거기서 부르면 온보딩 화면이 auth의 구현을 알게 된다. 인가는 이쪽 몫이다.
    //
    // 뒤로가기로 나오면 `null`이 온다 — 그때는 인가하지 않는다.
    final agreed = await context.push<bool>(
      AppRoutes.terms,
      extra: TermsNext.kakao,
    );
    if (!mounted || agreed != true) return;

    await _signInWithKakao();
  }

  /// 카카오로 로그인한다. **[_startKakao]를 거쳐서만 들어온다.**
  ///
  /// ## 취소는 화면에 남기지 않는다
  ///
  /// 사용자가 인가 화면에서 뒤로 가면 실패 이유가 돌아오지만, **그것을 그리면
  /// 스스로 그만둔 사람에게 오류를 보여주는 셈**이다. 여기서 걸러낸다.
  Future<void> _signInWithKakao() async {
    setState(() {
      _busy = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .signInWithOauth(OauthProvider.kakao);

    if (!mounted) return;

    setState(() {
      _busy = false;
      _failure = failure == AuthFailure.oauthCancelled ? null : failure;
    });

    // 카카오는 **가입과 로그인이 한 경로다.** 계정이 없으면 서버가 그 자리에서
    // 만들고 `isOnboarded=false`로 답한다. 그래서 첫 로그인은 이메일의 *가입*에
    // 해당하고, [_goAfterSignIn]이 그것을 폼으로 보낸다.
    if (failure == null) _goAfterSignIn();
  }

  void _notReady(BuildContext context) {
    final colors = context.appColors;

    // 이전 안내가 남아 있으면 겹쳐서 쌓인다. 하나만 띄운다.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.authSocialComingSoon,
            style: AppTypography.body.copyWith(color: colors.textPrimary),
          ),
          backgroundColor: colors.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
        ),
      );
  }
}

/// `───── 또는 ─────`
///
/// 이메일 로그인과 소셜 로그인이 **대등한 선택지**임을 보인다.
/// 구분선이 없으면 카카오·애플 버튼이 이메일 로그인의 하위 단계처럼 읽힌다.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Expanded(child: Divider(color: colors.borderDefault, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
          child: Text(
            AppStrings.authOr,
            style: AppTypography.caption.copyWith(color: colors.textTertiary),
          ),
        ),
        Expanded(child: Divider(color: colors.borderDefault, height: 1)),
      ],
    );
  }
}

/// 실패 안내 — 아이콘 + 문구.
///
/// **색만으로 알리지 않는다.** 빨간 테두리만 남으면 색을 구분하지 못하는 사용자에게는
/// 아무 정보가 아니다 (디자인 시스템 §1-5).
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure});

  final AuthFailure failure;

  /// 서버 `message`를 쓰지 않는다. 서버는 습니다체, 앱은 해요체다.
  String get _message => switch (failure) {
    AuthFailure.invalidCredentials => AppStrings.authFailedCredentials,
    AuthFailure.network => AppStrings.authFailedNetwork,
    AuthFailure.server => AppStrings.authFailedServer,
    // 앱의 EmailRule·PasswordRule이 못 막은 값이 서버까지 갔다.
    AuthFailure.validation => AppStrings.authFailedValidation,

    // 소셜 로그인 — 이 화면에서 실제로 난다.
    AuthFailure.oauthFailed => AppStrings.authFailedOauth,
    AuthFailure.oauthEmailMissing => AppStrings.authFailedOauthEmail,
    // 카카오 계정의 이메일로 이미 가입한 사람이다. 서버가 자동 연동하지 않으므로
    // **이메일 로그인으로 안내한다** — "이미 가입했다"만으로는 갈 곳을 모른다.
    AuthFailure.emailAlreadyExists => AppStrings.authFailedOauthEmailTaken,
    // 취소는 `_signInWithKakao`가 걸러내 여기까지 오지 않는다.
    // enum이라 자리는 있어야 하고, 빈 문구가 그 사실을 드러낸다.
    AuthFailure.oauthCancelled => '',

    // 가입·인증·갱신 전용 실패다. 이 화면에 올 일이 없지만 enum이라
    // 컴파일러가 빠짐을 잡아준다. 뭉뚱그린 문구로 받는다.
    AuthFailure.invalidCode ||
    AuthFailure.codeExpired ||
    AuthFailure.tooManyCodeAttempts ||
    AuthFailure.sendCooldown ||
    AuthFailure.sendDailyLimit ||
    AuthFailure.sendFailed ||
    AuthFailure.emailNotVerified ||
    AuthFailure.sessionExpired ||
    AuthFailure.unknown => AppStrings.authFailedUnknown,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          LucideIcons.circleAlert,
          size: AppSpacing.space5,
          color: colors.error,
        ),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            _message,
            style: AppTypography.caption.copyWith(color: colors.error),
          ),
        ),
      ],
    );
  }
}
