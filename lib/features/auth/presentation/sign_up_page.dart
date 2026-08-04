import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/app_input.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/email_rule.dart';
import 'package:runiverse/features/auth/domain/password_rule.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/password_field.dart';

/// 이메일 회원가입.
///
/// ## 비밀번호 확인 칸이 없다
///
/// 서버가 확인값을 받지 않고, 칸이 하나 늘면 화면이 그만큼 길어진다.
/// 오타는 [PasswordField]의 눈 아이콘으로 막는다.
///
/// ## 규칙을 화면이 다시 검사한다
///
/// 서버 `SignUpRequest`와 같은 규칙을 [PasswordRule]에 옮겨 뒀다.
/// 서버까지 갔다 와서 거절당하는 것보다 치는 동안 알려주는 편이 빠르다.
/// **대신 규칙이 두 곳에 존재한다** — 서버가 바꾸면 여기도 바꿔야 한다.
///
/// ## 가입하면 약관으로 간다
///
/// 가입한 사람은 신규다. 로그인한 사람은 기존이라 곧장 홈으로 간다.
/// 서버가 온보딩 완료 여부를 알려주지 않아서 쓰는 방법이다.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  AuthFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy &&
      EmailRule.of(_email.text).isValid &&
      PasswordRule.of(_password.text).isValid;

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
        .signUp(email: _email.text.trim(), password: _password.text);

    if (!mounted) return;

    setState(() {
      _busy = false;
      _failure = failure;
    });

    if (failure == null) {
      context.go(AppRoutes.terms);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final emailStatus = EmailRule.of(_email.text);
    final passwordStatus = PasswordRule.of(_password.text);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => context.pop(),
                tooltip: AppStrings.authBack,
                constraints: const BoxConstraints(
                  minWidth: AppSizes.touchDefault,
                  minHeight: AppSizes.touchDefault,
                ),
                icon: Icon(
                  LucideIcons.arrowLeft,
                  size: AppSpacing.space6,
                  color: colors.textSecondary,
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space4,
                  AppSpacing.space5,
                  AppSpacing.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.authSignUpTitle,
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
                      tone: _toneOf(passwordStatus),
                      helper: _helperOf(passwordStatus),
                    ),

                    if (_failure != null) ...[
                      const SizedBox(height: AppSpacing.space4),
                      _FailureNotice(failure: _failure!),
                    ],

                    const SizedBox(height: AppSpacing.space6),
                    AppButton(
                      label: AppStrings.authToSignIn,
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.md,
                      onPressed: () =>
                          context.pushReplacement(AppRoutes.signIn),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                0,
                AppSpacing.space4,
                AppSpacing.space4,
              ),
              child: SizedBox(
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
                        label: AppStrings.authSignUpCta,
                        onPressed: _canSubmit ? _submit : null,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 아직 아무것도 안 쳤을 때는 중립이다. 화면을 열자마자 빨간 글씨가 뜨면
  /// 시작도 전에 혼난 것처럼 보인다.
  AppInputTone _toneOf(PasswordStatus status) => switch (status) {
    PasswordStatus.empty => AppInputTone.neutral,
    PasswordStatus.valid => AppInputTone.success,
    _ => AppInputTone.error,
  };

  /// 비어 있을 때는 **규칙 전체**를 보여준다. 무엇을 쳐야 하는지 미리 알린다.
  String _helperOf(PasswordStatus status) => switch (status) {
    PasswordStatus.empty => AppStrings.authPasswordGuide,
    PasswordStatus.disallowedChar => AppStrings.authPasswordDisallowedChar,
    PasswordStatus.tooShort => AppStrings.authPasswordTooShort,
    PasswordStatus.tooLong => AppStrings.authPasswordTooLong,
    PasswordStatus.missingKind => AppStrings.authPasswordMissingKind,
    PasswordStatus.valid => AppStrings.authPasswordOk,
  };
}

/// 실패 안내 — 아이콘 + 문구. 색만으로 알리지 않는다.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure});

  final AuthFailure failure;

  String get _message => switch (failure) {
    AuthFailure.emailAlreadyExists => AppStrings.authFailedEmailTaken,
    AuthFailure.network => AppStrings.authFailedNetwork,
    AuthFailure.server => AppStrings.authFailedServer,
    AuthFailure.invalidCredentials ||
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
