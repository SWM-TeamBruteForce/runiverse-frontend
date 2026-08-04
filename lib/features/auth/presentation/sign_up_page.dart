import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:runiverse/features/auth/domain/verification_code_rule.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/password_field.dart';

/// 가입 2 · 정보 입력 — 이메일 인증 + 비밀번호.
///
/// 약관 동의(S03)를 지나온 사람만 여기 온다. 성공하면 **자동으로 로그인된 상태**가 되고
/// 프로필 등록(S04)으로 넘어간다.
///
/// ## 한 화면에서 세 단계가 순서대로 열린다
///
/// 이메일 → 인증번호 → 비밀번호. 앞 단계를 마쳐야 다음 칸이 나타난다.
/// 세 칸을 한꺼번에 보여주면 무엇부터 해야 하는지가 흐려지고,
/// 비밀번호를 다 지어놓고 인증에서 막히면 그 일이 통째로 버려진다.
///
/// ## ⚠️ 이메일을 고치면 인증이 풀린다
///
/// [_verifiedEmail]에 **인증한 이메일 자체**를 담고 현재 입력값과 비교한다.
/// `bool _verified` 하나로 두면 A로 인증받고 B로 가입하는 구멍이 생긴다.
/// 비교식이라 입력이 바뀌는 순간 저절로 풀린다 — 따로 지우는 코드가 없어 빠뜨릴 수 없다.
///
/// ## 카운트다운은 표시일 뿐이다
///
/// **만료 판정은 저장소(서버)가 한다.** 화면 타이머로 판정하면 앱을 백그라운드에
/// 두거나 기기 시계를 돌렸을 때 어긋난다. 여기 타이머는 남은 시간을 그리기만 한다.
///
/// ## 비밀번호 확인 칸이 없다
///
/// 서버가 확인값을 받지 않고, 칸이 하나 늘면 화면이 그만큼 길어진다.
/// 오타는 [PasswordField]의 눈 아이콘으로 막는다.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  /// 인증번호를 보낸 이메일. 현재 입력과 다르면 보낸 적 없는 것으로 친다.
  String? _codeSentTo;

  /// 인증을 마친 이메일. 현재 입력과 다르면 인증이 풀린 것으로 친다.
  String? _verifiedEmail;

  /// 카운트다운 표시용. 판정 기준이 아니다.
  DateTime? _expiresAt;
  Timer? _ticker;

  bool _sending = false;
  bool _verifying = false;
  bool _submitting = false;

  AuthFailure? _failure;

  /// 전송 직후 한 번 보여주는 안내. 인증번호를 치기 시작하면 치운다.
  bool _justSent = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _normalizedEmail => _email.text.trim().toLowerCase();

  bool get _emailValid => EmailRule.of(_email.text).isValid;

  /// 지금 입력된 이메일로 인증번호를 보낸 상태인가.
  bool get _codeSent => _codeSentTo != null && _codeSentTo == _normalizedEmail;

  /// 지금 입력된 이메일이 인증된 상태인가.
  bool get _verified =>
      _verifiedEmail != null && _verifiedEmail == _normalizedEmail;

  /// 인증을 마쳤다가 이메일을 고쳐서 풀린 상태인가. 왜 풀렸는지 알려주려고 쓴다.
  bool get _verificationReset => _verifiedEmail != null && !_verified;

  Duration get _remaining {
    final at = _expiresAt;
    if (at == null) return Duration.zero;
    final left = at.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get _codeExpired => _codeSent && _remaining == Duration.zero;

  bool get _busy => _sending || _verifying || _submitting;

  bool get _canSubmit =>
      !_busy && _verified && PasswordRule.of(_password.text).isValid;

  void _startCountdown() {
    _ticker?.cancel();
    _expiresAt = DateTime.now().add(VerificationCodeRule.ttl);
    // 1초마다 남은 시간을 다시 그린다. 인증을 마치거나 만료되면 멈춘다 —
    // 계속 돌면 화면이 떠 있는 내내 초당 한 번씩 리빌드된다.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_remaining == Duration.zero) _stopCountdown();
    });
  }

  void _stopCountdown() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onEmailChanged(String _) {
    setState(() {
      _failure = null;
      _justSent = false;
      // 이메일이 바뀌면 이전 이메일의 카운트다운은 의미가 없다.
      if (!_codeSent) _stopCountdown();
    });
  }

  void _onCodeChanged(String _) {
    setState(() {
      _failure = null;
      _justSent = false;
    });
  }

  void _onPasswordChanged(String _) {
    setState(() => _failure = null);
  }

  Future<void> _send() async {
    if (!_emailValid || _busy) return;

    final email = _normalizedEmail;
    setState(() {
      _sending = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .sendVerificationCode(email);

    if (!mounted) return;

    setState(() {
      _sending = false;
      _failure = failure;
      if (failure == null) {
        _codeSentTo = email;
        // 다시 받으면 이전에 친 번호는 무효다. 남겨두면 그걸 그대로 눌러보게 된다.
        _code.clear();
        _justSent = true;
        _startCountdown();
      }
    });
  }

  Future<void> _verify() async {
    if (!VerificationCodeRule.of(_code.text).isValid || _busy) return;

    final email = _normalizedEmail;
    setState(() {
      _verifying = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .verifyCode(email: email, code: _code.text);

    if (!mounted) return;

    setState(() {
      _verifying = false;
      _failure = failure;
      if (failure == null) {
        _verifiedEmail = email;
        _justSent = false;
        // 인증이 끝났으니 남은 시간은 볼 이유가 없다.
        _stopCountdown();
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _submitting = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .signUp(email: _normalizedEmail, password: _password.text);

    if (!mounted) return;

    setState(() {
      _submitting = false;
      _failure = failure;
    });

    if (failure == null) {
      // 가입에 성공하면 **이미 로그인된 상태**다(`AuthController`가 토큰을 저장했다).
      // 약관은 앞에서 받았으므로 남은 것은 프로필뿐이다.
      //
      // go라 스택이 통째로 갈린다. 프로필에서 뒤로 눌러 가입 화면으로
      // 돌아가면 이미 만들어진 계정을 또 만들려 하게 된다.
      context.go(AppRoutes.profileSetup);
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

                    // ── 1단계 · 이메일 ────────────────────────────
                    AppInput(
                      controller: _email,
                      label: AppStrings.authEmailLabel,
                      hint: AppStrings.authEmailHint,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: _onEmailChanged,
                      tone: _emailTone(emailStatus),
                      helper: _emailHelper(emailStatus),
                    ),

                    if (!_verified) ...[
                      const SizedBox(height: AppSpacing.space3),
                      SizedBox(
                        height: AppButtonSize.md.height,
                        child: _sending
                            ? _Spinner(color: colors.primary)
                            : AppButton(
                                label: _codeSent
                                    ? AppStrings.authVerifyResend
                                    : AppStrings.authVerifySend,
                                variant: AppButtonVariant.secondary,
                                size: AppButtonSize.md,
                                onPressed: _emailValid && !_busy ? _send : null,
                              ),
                      ),
                    ],

                    // ── 2단계 · 인증번호 ──────────────────────────
                    if (_codeSent && !_verified) ...[
                      const SizedBox(height: AppSpacing.space5),
                      AppInput(
                        controller: _code,
                        label: AppStrings.authVerifyLabel,
                        hint: AppStrings.authVerifyHint,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(
                            VerificationCodeRule.length,
                          ),
                        ],
                        textInputAction: TextInputAction.done,
                        onChanged: _onCodeChanged,
                        onSubmitted: (_) => _verify(),
                        tone: _codeExpired
                            ? AppInputTone.error
                            : AppInputTone.neutral,
                        helper: _codeHelper(),
                        // 만료되면 남은 시간을 지운다. `0:00`이 남아 있으면
                        // 아직 셀 것이 있는 것처럼 보인다.
                        counter: _codeExpired
                            ? null
                            : _formatRemaining(_remaining),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      SizedBox(
                        height: AppButtonSize.md.height,
                        child: _verifying
                            ? _Spinner(color: colors.primary)
                            : AppButton(
                                label: AppStrings.authVerifyConfirm,
                                size: AppButtonSize.md,
                                onPressed:
                                    VerificationCodeRule.of(
                                          _code.text,
                                        ).isValid &&
                                        !_codeExpired &&
                                        !_busy
                                    ? _verify
                                    : null,
                              ),
                      ),
                    ],

                    // ── 3단계 · 비밀번호 ──────────────────────────
                    if (_verified) ...[
                      const SizedBox(height: AppSpacing.space3),
                      _VerifiedNotice(),
                      const SizedBox(height: AppSpacing.space5),
                      PasswordField(
                        controller: _password,
                        label: AppStrings.authPasswordLabel,
                        textInputAction: TextInputAction.done,
                        onChanged: _onPasswordChanged,
                        onSubmitted: (_) => _submit(),
                        tone: _passwordTone(passwordStatus),
                        helper: _passwordHelper(passwordStatus),
                      ),
                    ],

                    if (_failure != null) ...[
                      const SizedBox(height: AppSpacing.space4),
                      _FailureNotice(failure: _failure!),
                    ],

                    const SizedBox(height: AppSpacing.space6),
                    SizedBox(
                      height: AppButtonSize.lg.height,
                      child: _submitting
                          ? _Spinner(color: colors.primary)
                          : AppButton(
                              label: AppStrings.authSignUpCta,
                              onPressed: _canSubmit ? _submit : null,
                            ),
                    ),

                    const SizedBox(height: AppSpacing.space6),
                    AppButton(
                      label: AppStrings.authToSignIn,
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.md,
                      // 로그인은 이 스택의 **맨 아래**에 있다. 새로 쌓지 않고 거기로 되돌린다.
                      // push를 쓰면 로그인 화면이 두 장이 되고 뒤로가기가 이상해진다.
                      onPressed: () => context.go(AppRoutes.signIn),
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

  AppInputTone _emailTone(EmailStatus status) {
    if (status == EmailStatus.invalid) return AppInputTone.error;
    if (_verificationReset) return AppInputTone.error;
    return AppInputTone.neutral;
  }

  String? _emailHelper(EmailStatus status) {
    if (status == EmailStatus.invalid) return AppStrings.authEmailInvalid;
    // 인증을 마친 뒤 이메일을 고쳤다. **왜 인증이 풀렸는지** 밝히지 않으면
    // 사용자는 방금 한 인증이 사라진 것을 모른 채 가입 버튼만 쳐다본다.
    if (_verificationReset) return AppStrings.authVerifyReset;
    return null;
  }

  String _codeHelper() {
    if (_codeExpired) return AppStrings.authFailedCodeExpired;
    if (_justSent) return AppStrings.authVerifySent;
    if (VerificationCodeRule.of(_code.text) == VerificationCodeStatus.valid) {
      return '';
    }
    return AppStrings.authVerifyIncomplete;
  }

  /// 아직 아무것도 안 쳤을 때는 중립이다. 화면을 열자마자 빨간 글씨가 뜨면
  /// 시작도 전에 혼난 것처럼 보인다.
  AppInputTone _passwordTone(PasswordStatus status) => switch (status) {
    PasswordStatus.empty => AppInputTone.neutral,
    PasswordStatus.valid => AppInputTone.success,
    _ => AppInputTone.error,
  };

  /// 비어 있을 때는 **규칙 전체**를 보여준다. 무엇을 쳐야 하는지 미리 알린다.
  String _passwordHelper(PasswordStatus status) => switch (status) {
    PasswordStatus.empty => AppStrings.authPasswordGuide,
    PasswordStatus.disallowedChar => AppStrings.authPasswordDisallowedChar,
    PasswordStatus.tooShort => AppStrings.authPasswordTooShort,
    PasswordStatus.tooLong => AppStrings.authPasswordTooLong,
    PasswordStatus.missingKind => AppStrings.authPasswordMissingKind,
    PasswordStatus.valid => AppStrings.authPasswordOk,
  };

  /// `4:59`. 분은 한 자리다 — 최대가 5분이라 `04:59`로 쓸 이유가 없다.
  String _formatRemaining(Duration left) {
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 버튼 자리에서 도는 표시. 버튼과 같은 높이를 차지해 화면이 튀지 않는다.
class _Spinner extends StatelessWidget {
  const _Spinner({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: AppSpacing.space6,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
    );
  }
}

/// 인증을 마쳤다는 표시.
///
/// **색만으로 알리지 않는다.** 초록 테두리만 남으면 색을 구분하지 못하는
/// 사용자에게는 아무 정보가 아니다 (디자인 시스템 §1-5).
class _VerifiedNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Icon(
          LucideIcons.circleCheck,
          size: AppSpacing.space5,
          color: colors.success,
        ),
        const SizedBox(width: AppSpacing.space2),
        Text(
          AppStrings.authVerifyDone,
          style: AppTypography.caption.copyWith(color: colors.success),
        ),
      ],
    );
  }
}

/// 실패 안내 — 아이콘 + 문구. 색만으로 알리지 않는다.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure});

  final AuthFailure failure;

  String get _message => switch (failure) {
    AuthFailure.emailAlreadyExists => AppStrings.authFailedEmailTaken,
    AuthFailure.invalidCode => AppStrings.authFailedInvalidCode,
    AuthFailure.codeExpired => AppStrings.authFailedCodeExpired,
    AuthFailure.emailNotVerified => AppStrings.authFailedNotVerified,
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
