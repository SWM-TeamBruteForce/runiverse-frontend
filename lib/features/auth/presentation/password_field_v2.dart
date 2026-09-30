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
      // ## ⚠️ 눈 아이콘이 칸의 높이를 정하면 안 된다
      //
      // 44px 짜리 [IconButton] 을 넣었더니 칸이 **53 → 79** 로 커졌다.
      // 시안(`158:2920`)의 칸은 53이고 아이콘은 20이다 — 위아래 여백 16이
      // 아이콘이 아니라 글자 높이를 감싸야 나오는 값이다.
      //
      // 그래서 자리는 20만 차지하고 **누르는 영역만 44로 넘쳐 나가게** 한다.
      // [OverflowBox] 가 부모에게는 20이라고 말하고 자식에게는 44를 준다.
      suffix: SizedBox(
        width: AppSizes.touchDefault,
        height: _eyeSize,
        child: OverflowBox(
          maxHeight: AppSizes.touchDefault,
          child: Tooltip(
            message: _revealed
                ? AppStrings.authPasswordHide
                : AppStrings.authPasswordShow,
            child: InkWell(
              onTap: () => setState(() => _revealed = !_revealed),
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: AppSizes.touchDefault,
                height: AppSizes.touchDefault,
                child: Center(
                  child: AppIcon(
                    _revealed ? AppIcons.view2 : AppIcons.view,
                    size: _eyeSize,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
