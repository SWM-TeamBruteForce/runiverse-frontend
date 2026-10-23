import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/widgets/app_input.dart';

/// 비밀번호 입력 — 가림 + 보기 토글.
///
/// ## 왜 확인 입력칸이 없는가
///
/// 서버가 확인값을 받지 않고, 칸이 하나 늘면 화면이 그만큼 길어진다.
/// 오타는 **눈 아이콘**으로 막는다 — 사용자가 직접 확인하는 쪽이 다시 치는 쪽보다 빠르다.
///
/// ## 토글 상태를 여기서 드는 이유
///
/// [AppInput]은 상태 없는 위젯이고 그 규칙을 유지한다. 그렇다고 화면마다
/// `bool _revealed`를 두면 로그인·가입에 같은 코드가 두 벌 생긴다. 중간에 이 위젯을 둔다.
class PasswordField extends StatefulWidget {
  const PasswordField({
    required this.controller,
    this.label,
    this.helper,
    this.tone = AppInputTone.neutral,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? helper;
  final AppInputTone tone;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppInput(
      controller: widget.controller,
      label: widget.label,
      helper: widget.helper,
      tone: widget.tone,
      // `visiblePassword`는 자판이 비밀번호 입력임을 알게 해 자동 대문자·자동 수정을 끈다.
      // 일반 텍스트 자판을 쓰면 첫 글자가 대문자로 바뀌어 로그인이 실패한다.
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      obscureText: !_revealed,
      suffix: IconButton(
        onPressed: () => setState(() => _revealed = !_revealed),
        // 아이콘만으로는 스크린리더가 읽을 것이 없다.
        tooltip: _revealed
            ? AppStrings.authPasswordHide
            : AppStrings.authPasswordShow,
        // IconButton 기본 크기는 48이다. 입력 필드(44) 안에서 넘치지 않게 맞춘다.
        constraints: const BoxConstraints(
          minWidth: AppSizes.touchDefault,
          minHeight: AppSizes.touchDefault,
        ),
        icon: Icon(
          _revealed ? LucideIcons.eyeOff : LucideIcons.eye,
          size: AppSpacing.space5,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}
