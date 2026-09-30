import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 입력 칸 **안**에 앉는 작은 버튼.
/// 시안 `158:2729`(인증하기) · `158:2742`(재전송) · `158:2778`(중복확인).
///
/// ## ⚠️ 작아야 하고, 그러면서 44를 지켜야 한다
///
/// 시안의 이 버튼은 높이가 35다. 44짜리를 그대로 넣으면 **칸이 밀린다** —
/// 비밀번호 칸이 53에서 79로 커진 적이 있다(PR #100).
///
/// 그래서 [OverflowBox]로 나눈다. **자리는 35만 차지하고 누르는 영역만 44로
/// 넘쳐 나간다.** 부모에게는 작다고 말하고 자식에게는 넉넉히 준다 —
/// `password_field_v2.dart`의 눈 아이콘이 같은 방법을 쓴다.
///
/// ## 글자 색을 시안보다 올렸다
///
/// 시안은 `#767676`을 `#434343` 면에 얹는데 대비가 **2.18:1**이라 어떤 기준도
/// 넘지 못한다. 한 단계 밝은 [AppColorsV2.textSecondary]를 쓴다(약 5.7:1).
///
/// ## ⚠️ 잠긴 글자에 `textDisabled`를 쓰지 않는다
///
/// 다크에서 `textDisabled`가 `#434343`인데 **이 버튼의 면과 같은 값이다.**
/// 그대로 쓰면 잠긴 버튼이 글자 없는 회색 알약으로 보인다 — 에뮬레이터에서
/// 실제로 그렇게 나왔다. 한 단계 밝은 [AppColorsV2.textTertiary]를 쓴다.
class FieldActionV2 extends StatelessWidget {
  const FieldActionV2({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;

  /// `null`이면 눌리지 않는다. 재전송은 쿨다운 동안 잠긴다.
  final VoidCallback? onPressed;

  /// 시안 실측. 가로 여백 14 · 세로 10.5 · 글자 12/1.24.
  ///
  /// 높이는 세로 여백에 맡기지 않고 **직접 못 박는다** — 글꼴이 바뀌면 줄 높이가
  /// 따라 바뀌고, 그러면 칸 안에서 이 버튼만 커진다.
  static const _padX = 14.0;
  static const _height = 36.0;

  /// 누르는 영역이 44가 되도록 위아래로 넘치는 양.
  static const _reach = (AppSizes.touchDefault - _height) / 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      child: Stack(
        // ⚠️ 넘치는 것을 자르지 않는다. 자르면 누르는 영역이 도로 36이 된다.
        clipBehavior: Clip.none,
        children: [
          // 면과 글자. **자리를 차지하는 것은 이것뿐이고**, 이 위젯의 크기를 정한다.
          Container(
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: _padX),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: AppRadius.md,
            ),
            child: Text(
              label,
              style: AppTypographyV2.body21.copyWith(
                color: enabled ? colors.textSecondary : colors.textTertiary,
              ),
            ),
          ),

          // 누르는 영역만 위아래로 넘쳐 나간다. 음수 [Positioned]라
          // 부모의 크기 계산에 들어가지 않는다.
          Positioned(
            top: -_reach,
            bottom: -_reach,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: AppRadius.md,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
