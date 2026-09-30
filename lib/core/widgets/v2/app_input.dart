import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 입력 상태의 색 톤.
///
/// 성공/실패를 색으로만 알리지 않는다. 이 값은 **테두리와 helper 색을 함께** 바꾸고,
/// helper 문구는 화면이 따로 채운다. 색맹인 사용자에게 테두리 색만 남으면 아무 정보가 아니다.
enum AppInputToneV2 { neutral, success, error }

/// 텍스트 입력 — 새 디자인. 시안 `158:2724`(라벨 있음) · `158:2918`(라벨 없음).
///
/// 화면이 상태를 들고, 이 위젯은 **받은 상태를 그리기만 한다.** 유효성 판단을 위젯 안에
/// 넣으면 규칙이 화면마다 흩어지고, 서버 검증(닉네임 중복 같은)이 붙을 자리가 없어진다.
///
/// 글자 수 제한은 [inputFormatters]로 넘긴다. 잘렸다는 사실을 사용자에게 알리는 것은
/// 화면 몫이다 — 조용히 안 써지면 고장난 것으로 읽힌다.
///
/// ## ⚠️ 라벨이 모양을 정한다
///
/// 시안에 입력이 두 가지로 나온다. 둘의 차이가 **라벨 유무와 정확히 겹친다.**
///
/// | | 라벨 있음 (회원가입) | 라벨 없음 (로그인) |
/// |---|---|---|
/// | 반경 | 16 (`lg`) | 12 (`md`) |
/// | 안쪽 여백 | 가로 18 · 세로 14 | 16 |
/// | 글자 | 18 Medium | 14 Regular |
/// | 높이 | 71 | 53 |
///
/// 그래서 모양을 고르는 인자를 따로 두지 않았다. **기존 `AppInput`과 인자 이름이
/// 하나도 다르지 않아야** 화면을 옮길 때 import 한 줄만 바꾸면 된다.
///
/// 라벨이 있으면서 작은 칸이 필요해지면 그때 열거형을 더한다. 지금 미리 만들면
/// 시안에 없는 조합을 우리가 정하게 된다.
///
/// ## 라벨이 칸 **안**에 있다
///
/// 옛 `AppInput`은 칸 위에 라벨을 뒀다. 시안은 칸 안에 넣는다 — 스크롤하다 칸만
/// 보여도 무엇을 적는 자리인지 알 수 있다.
class AppInputV2 extends StatefulWidget {
  const AppInputV2({
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.counter,
    this.tone = AppInputToneV2.neutral,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.suffix,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;

  /// 칸 안 위쪽 라벨. **이 값의 유무가 칸의 모양을 정한다** (클래스 주석 참고).
  final String? label;

  final String? hint;

  /// 칸 아래 안내. [tone]에 따라 색이 바뀐다.
  final String? helper;

  /// `3/12` 같은 글자 수 표시. helper 반대편에 붙는다.
  final String? counter;

  final AppInputToneV2 tone;

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

  /// 칸 오른쪽 끝에 붙는 위젯. 보기 토글·인증 버튼 같은 인라인 액션용.
  ///
  /// 누를 수 있는 것을 넣을 때는 44px 터치 타깃을 지킨다 — [IconButton]은 기본이 48px다.
  final Widget? suffix;

  final bool autofocus;

  /// 바깥에서 포커스를 옮기고 싶을 때만 준다.
  ///
  /// ⚠️ **주면 버리는 것도 준 쪽의 몫이다.** 프로필 등록이 "이미 있는 닉네임"을
  /// 들었을 때 그 칸으로 데려오려고 쓴다.
  final FocusNode? focusNode;

  @override
  State<AppInputV2> createState() => _AppInputV2State();
}

class _AppInputV2State extends State<AppInputV2> {
  /// 포커스를 직접 든다. ⚠️ **시안에 포커스 상태가 없다.** 그렇다고 두면 키보드로
  /// 옮겨 다니는 사람이 지금 어느 칸에 있는지 알 방법이 없다. 테두리를 primary로
  /// 준다.
  ///
  /// ⚠️ 바깥에서 [AppInputV2.focusNode]를 주면 그것을 쓴다. **그때는 버리지
  /// 않는다** — 남의 것을 버리면 준 쪽이 다음에 쓸 때 죽는다.
  late final FocusNode _focus = (widget.focusNode ?? FocusNode())
    ..addListener(_onFocusChange);

  bool get _ownsFocus => widget.focusNode == null;

  bool _focused = false;

  void _onFocusChange() {
    if (_focus.hasFocus == _focused) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  /// 시안의 칸 안쪽 여백. `AppSpacing`에 18도 14도 없다.
  static const _labeledPadX = 18.0;
  static const _labeledPadY = 14.0;

  /// 라벨과 값 사이. 역시 토큰에 없는 값이다.
  static const _labelGap = 6.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final labeled = widget.label != null;

    final accent = switch (widget.tone) {
      AppInputToneV2.neutral => null,
      AppInputToneV2.success => colors.success,
      AppInputToneV2.error => colors.error,
    };

    // 오류 중에는 포커스가 가도 오류 색을 유지한다.
    // 파랗게 바뀌면 방금 뭘 잘못했는지 사라진다.
    final border = accent ?? (_focused ? colors.primary : Colors.transparent);

    final valueStyle = labeled
        ? AppTypographyV2.body04
        : AppTypographyV2.body12;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          // ⚠️ **세로 여백은 여기 두지 않는다.** 여기 두면 suffix 가 그만큼
          // 좁아져(71 → 43) 44 를 못 채운다. 글자 쪽에만 준다.
          padding: EdgeInsets.symmetric(
            horizontal: labeled ? _labeledPadX : AppSpacing.space4,
          ),
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: labeled ? AppRadius.lg : AppRadius.md,
            // 투명하더라도 **테두리는 항상 그린다.** 없다가 생기면 칸이 1px씩
            // 커져 포커스를 옮길 때마다 줄이 흔들린다.
            border: Border.all(color: border),
          ),
          // ⚠️ [IntrinsicHeight] + stretch 로 **suffix 에 칸의 높이를 물려준다.**
          //
          // Flutter 는 부모의 경계 밖을 히트 테스트하지 않는다. suffix 가 제
          // 크기(36)만 차지하면 그만큼만 눌리고, 44 규칙을 지킬 길이 없다 —
          // `OverflowBox` 로도 음수 `Positioned` 로도 **레이아웃만 커지고 탭
          // 영역은 안 넓어진다.** 칸이 이미 53~71 이므로 그 높이를 주면 된다.
          //
          // 칸의 높이는 그대로다. `IntrinsicHeight` 가 자식들의 고유 높이 중
          // 큰 쪽을 쓰는데, 글자 쪽이 suffix 보다 크다.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: labeled ? _labeledPadY : AppSpacing.space4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (labeled) ...[
                          Text(
                            widget.label!,
                            style: AppTypographyV2.body22.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: _labelGap),
                        ],
                        TextField(
                          controller: widget.controller,
                          focusNode: _focus,
                          autofocus: widget.autofocus,
                          keyboardType: widget.keyboardType,
                          inputFormatters: widget.inputFormatters,
                          textInputAction: widget.textInputAction,
                          onChanged: widget.onChanged,
                          onSubmitted: widget.onSubmitted,
                          obscureText: widget.obscureText,
                          style: valueStyle.copyWith(color: colors.textPrimary),
                          cursorColor: colors.primary,
                          // 칸은 바깥 [Container]가 그린다. [TextField]가 제 여백과
                          // 테두리를 또 그리면 시안의 높이(71 · 53)를 맞출 수 없다.
                          decoration: InputDecoration(
                            hintText: widget.hint,
                            hintStyle: valueStyle.copyWith(
                              color: colors.textTertiary,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.suffix != null) ...[
                  const SizedBox(width: AppSpacing.space3),
                  widget.suffix!,
                ],
              ],
            ),
          ),
        ),

        if (widget.helper != null || widget.counter != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.helper ?? '',
                  style: AppTypographyV2.body20.copyWith(
                    color: accent ?? colors.textTertiary,
                  ),
                ),
              ),
              if (widget.counter != null) ...[
                const SizedBox(width: AppSpacing.space2),
                Text(
                  widget.counter!,
                  style: AppTypographyV2.body20.copyWith(
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
