import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 입력 상태의 색 톤.
///
/// 성공/실패를 색으로만 알리지 않는다. 이 값은 **테두리와 helper 색을 함께** 바꾸고,
/// helper 문구는 화면이 따로 채운다. 색맹인 사용자에게 테두리 색만 남으면 아무 정보가 아니다.
enum AppInputTone { neutral, success, error }

/// 텍스트 입력 — 디자인 시스템 `Input`(label + helper + validation).
///
/// 화면이 상태를 들고, 이 위젯은 **받은 상태를 그리기만 한다.** 유효성 판단을 위젯 안에
/// 넣으면 규칙이 화면마다 흩어지고, 서버 검증(닉네임 중복 같은)이 붙을 자리가 없어진다.
///
/// 글자 수 제한은 [inputFormatters]로 넘긴다. 잘렸다는 사실을 사용자에게 알리는 것은
/// 화면 몫이다 — 조용히 안 써지면 고장난 것으로 읽힌다.
class AppInput extends StatelessWidget {
  const AppInput({
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.counter,
    this.tone = AppInputTone.neutral,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.suffix,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;

  /// 필드 위 라벨. 질문이 이미 제목으로 있으면 생략한다.
  final String? label;

  final String? hint;

  /// 필드 아래 안내. [tone]에 따라 색이 바뀐다.
  final String? helper;

  /// `3/12` 같은 글자 수 표시. helper 반대편에 붙는다.
  final String? counter;

  final AppInputTone tone;

  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 입력을 가린다. 비밀번호용.
  ///
  /// 보기 토글은 **화면이 [suffix]로 넣는다.** 토글 상태를 이 위젯이 들면
  /// "상태는 화면이 든다"는 이 파일의 규칙이 깨진다.
  final bool obscureText;

  /// 필드 오른쪽 끝에 붙는 위젯. 보기 토글 같은 인라인 액션용.
  ///
  /// 누를 수 있는 것을 넣을 때는 44px 터치 타깃을 지킨다 — [IconButton]은 기본이 48px다.
  final Widget? suffix;

  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final accent = switch (tone) {
      AppInputTone.neutral => null,
      AppInputTone.success => colors.success,
      AppInputTone.error => colors.error,
    };

    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: AppRadius.md,
      borderSide: BorderSide(color: color),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space2),
        ],

        TextField(
          controller: controller,
          autofocus: autofocus,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          obscureText: obscureText,
          style: AppTypography.body.copyWith(color: colors.textPrimary),
          cursorColor: colors.primary,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.body.copyWith(color: colors.textDisabled),
            suffixIcon: suffix,
            filled: true,
            fillColor: colors.bgSurface,
            // 44px는 패딩이 아니라 min-height로 지킨다. 패딩만 주면
            // 박스가 라인박스 높이로 접힌다 (디자인 시스템 §3-3).
            constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            enabledBorder: border(accent ?? colors.borderDefault),
            // 오류 중에는 포커스가 가도 오류 색을 유지한다.
            // 파랗게 바뀌면 방금 뭘 잘못했는지 사라진다.
            focusedBorder: border(accent ?? colors.primary),
          ),
        ),

        if (helper != null || counter != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  helper ?? '',
                  style: AppTypography.caption.copyWith(
                    color: accent ?? colors.textTertiary,
                  ),
                ),
              ),
              if (counter != null) ...[
                const SizedBox(width: AppSpacing.space2),
                Text(
                  counter!,
                  style: AppTypography.caption.copyWith(
                    color: accent ?? colors.textTertiary,
                    // 자릿수가 바뀔 때 흔들리지 않게.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
