import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/app_input.dart';
import 'package:runiverse/features/auth/domain/password_rule.dart';
import 'package:runiverse/features/settings/domain/password_change_failure.dart';
import 'package:runiverse/features/settings/presentation/settings_provider.dart';

/// 비밀번호 변경 (설정 하위). `PATCH /api/v1/users/me/password` (명세 56번).
///
/// ## ⚠️ "재설정"이 아니다
///
/// 서버가 `currentPassword`를 요구한다 — **지금 비밀번호를 알아야 바꿀 수 있다.**
/// 비밀번호를 잊은 사람을 위한 흐름(이메일 인증 후 재설정)은 명세에 없다.
///
/// ## 로컬 계정만 온다
///
/// 설정 화면이 `loginType`으로 메뉴를 숨긴다. 딥링크로 바로 들어오면 서버가
/// 409로 막고, 그때는 [PasswordChangeFailure.notLocalAccount]가 나온다.
///
/// ## 규칙은 가입 화면과 같은 것을 쓴다
///
/// `PasswordRule`을 그대로 가져다 쓴다. 여기에 규칙을 다시 적으면 가입과
/// 변경이 서로 다른 비밀번호를 허용하게 된다.
class PasswordChangePage extends ConsumerStatefulWidget {
  const PasswordChangePage({super.key});

  @override
  ConsumerState<PasswordChangePage> createState() => _PasswordChangePageState();
}

class _PasswordChangePageState extends ConsumerState<PasswordChangePage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _submitting = false;

  /// 서버가 돌려준 실패. **입력을 고치면 지운다** — 고쳤는데도 빨간 글씨가
  /// 남아 있으면 무엇이 문제인지 알 수 없다.
  PasswordChangeFailure? _failure;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // ── 판정 ──────────────────────────────────────────────────

  PasswordStatus get _status => PasswordRule.of(_next.text);

  /// 확인란이 새 비밀번호와 같은가. **아직 안 쳤으면 틀린 것이 아니다.**
  bool get _confirmed =>
      _confirm.text.isNotEmpty && _confirm.text == _next.text;

  bool get _canSubmit =>
      !_submitting && _current.text.isNotEmpty && _status.isValid && _confirmed;

  // ── 보내기 ────────────────────────────────────────────────

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _failure = null;
    });

    final failure = await ref
        .read(settingsControllerProvider.notifier)
        .changePassword(current: _current.text, next: _next.text);

    // `await` 뒤라 화면이 이미 사라졌을 수 있다.
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _failure = failure;
    });

    if (failure != null) return;

    // 성공하면 **토큰은 그대로다.** 다시 로그인시키지 않는다.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(AppStrings.passwordChanged)));
    context.pop();
  }

  // ── 그리기 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: Text(AppStrings.passwordChangeTitle, style: AppTypography.h3),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space4),
          children: [
            AppInput(
              controller: _current,
              label: AppStrings.passwordCurrentLabel,
              obscureText: true,
              autofocus: true,
              // 현재 비밀번호가 틀렸다는 답은 **여기 붙어야** 한다.
              // 아래 칸에 붙이면 새 비밀번호를 고치게 된다.
              helper: _currentHelper,
              tone: _currentHelper == null
                  ? AppInputTone.neutral
                  : AppInputTone.error,
              onChanged: (_) => setState(() => _failure = null),
            ),
            const SizedBox(height: AppSpacing.space5),
            AppInput(
              controller: _next,
              label: AppStrings.passwordNewLabel,
              obscureText: true,
              helper: _nextHelper,
              tone: _nextTone,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.space5),
            AppInput(
              controller: _confirm,
              label: AppStrings.passwordConfirmLabel,
              obscureText: true,
              helper: _confirmHelper,
              tone: _confirmHelper == null
                  ? AppInputTone.neutral
                  : AppInputTone.error,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_canSubmit) _submit();
              },
            ),
            if (_generalFailure != null) ...[
              const SizedBox(height: AppSpacing.space4),
              Text(
                _generalFailure!,
                style: AppTypography.caption.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: AppSpacing.space7),
            AppButton(
              label: AppStrings.passwordChangeCta,
              onPressed: _canSubmit ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 현재 비밀번호 칸에 붙는 말.
  String? get _currentHelper =>
      _failure == PasswordChangeFailure.wrongCurrentPassword
      ? AppStrings.passwordWrongCurrent
      : null;

  /// 새 비밀번호 칸에 붙는 말. 규칙을 통과하면 규칙 안내가 아니라 통과 표시다.
  String? get _nextHelper => switch (_status) {
    PasswordStatus.empty => AppStrings.authPasswordGuide,
    PasswordStatus.tooShort => AppStrings.authPasswordTooShort,
    PasswordStatus.tooLong => AppStrings.authPasswordTooLong,
    PasswordStatus.disallowedChar => AppStrings.authPasswordDisallowedChar,
    PasswordStatus.missingKind => AppStrings.authPasswordMissingKind,
    PasswordStatus.valid => AppStrings.authPasswordOk,
  };

  AppInputTone get _nextTone => switch (_status) {
    // 아직 안 쳤다. 규칙을 **안내**하는 것이지 틀렸다는 것이 아니다.
    PasswordStatus.empty => AppInputTone.neutral,
    PasswordStatus.valid => AppInputTone.success,
    _ => AppInputTone.error,
  };

  String? get _confirmHelper =>
      _confirm.text.isEmpty || _confirmed ? null : AppStrings.passwordMismatch;

  /// 어느 칸에도 속하지 않는 실패. 칸 밑이 아니라 버튼 위에 적는다.
  String? get _generalFailure => switch (_failure) {
    // 이 둘은 각자의 칸에 이미 붙어 있다.
    PasswordChangeFailure.wrongCurrentPassword || null => null,
    PasswordChangeFailure.notLocalAccount => AppStrings.passwordNotLocal,
    PasswordChangeFailure.sessionExpired => AppStrings.settingsSessionExpired,
    // 앱이 먼저 막고 있으므로 정상 경로에서는 나오지 않는다.
    PasswordChangeFailure.invalidNewPassword =>
      AppStrings.authPasswordMissingKind,
    _ => AppStrings.passwordChangeFailed,
  };
}
