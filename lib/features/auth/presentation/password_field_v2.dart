import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';

/// 비밀번호 입력 — 가림 + 보기 토글. 새 디자인. 시안 `158:2920`.
///
/// ## 왜 확인 입력칸이 없는가
///
/// 서버가 확인값을 받지 않고, 칸이 하나 늘면 화면이 그만큼 길어진다.
/// 오타는 **눈 아이콘**으로 막는다 — 사용자가 직접 확인하는 쪽이 다시 치는 쪽보다 빠르다.
///
/// ## 토글 상태를 여기서 드는 이유
///
/// [AppInputV2]는 받은 상태를 그리기만 하고 그 규칙을 유지한다. 그렇다고
/// 화면마다 `bool _revealed`를 두면 로그인·가입에 같은 코드가 두 벌 생긴다.
/// 중간에 이 위젯을 둔다.
///
/// ## 옛 [PasswordField]와 나뉜 이유
///
/// 모양이 아니라 **세대**다. 옛 것은 옛 토큰의 [AppInput]을 감싼다. 회원가입과
/// 비밀번호 변경이 아직 그쪽을 쓰고 있어, 하나로 합치면 안 옮긴 화면에 새 칸이
/// 끼어든다. 마지막 화면이 넘어오면 옛 것을 지운다.
class PasswordFieldV2 extends StatefulWidget {
  const PasswordFieldV2({
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.tone = AppInputToneV2.neutral,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? helper;
  final AppInputToneV2 tone;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordFieldV2> createState() => _PasswordFieldV2State();
}

class _PasswordFieldV2State extends State<PasswordFieldV2> {
  bool _revealed = false;

  /// 시안의 눈 아이콘이 20이다. 칸 안에 들어가는 아이콘만 24보다 작다.
  static const _eyeSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return AppInputV2(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
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
        // IconButton 기본 크기는 48이다. 칸(53) 안에서 넘치지 않게 맞춘다.
        constraints: const BoxConstraints(
          minWidth: AppSizes.touchDefault,
          minHeight: AppSizes.touchDefault,
        ),
        padding: EdgeInsets.zero,
        icon: AppIcon(
          _revealed ? AppIcons.view2 : AppIcons.view,
          size: _eyeSize,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}
