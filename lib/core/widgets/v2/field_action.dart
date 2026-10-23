import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 입력 칸 **안**에 앉는 작은 버튼.
/// 시안 `158:2729`(인증하기) · `158:2742`(재전송) · `158:2778`(중복확인).
///
/// ## ⚠️ 작아 보이되, 누르는 곳은 칸만큼 넓다
///
/// 시안의 이 버튼은 높이가 35다. 44짜리를 그대로 넣으면 **칸이 밀린다** —
/// 비밀번호 칸이 53에서 79로 커진 적이 있다(PR #100).
///
/// 처음엔 `OverflowBox`로, 다음엔 음수 `Positioned`로 "자리는 36, 탭은 44"를
/// 만들려 했는데 **둘 다 틀렸다.** Flutter 는 부모의 경계 밖을 히트 테스트하지
/// 않아서 레이아웃 크기만 커지고 **실제로는 36만 눌렸다.** 크기를 재던 테스트는
/// 그대로 통과했다 — 눌리는지를 안 보고 있었다.
///
/// 지금은 반대로 한다. 알약은 [_height]로 그리고 **누르는 영역은 부모가 주는
/// 높이를 다 쓴다.** [AppInputV2]가 `IntrinsicHeight`로 칸의 높이(53~71)를
/// 물려주므로 44는 저절로 넘는다. 칸의 높이는 글자 쪽이 정하므로 그대로다.
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final enabled = onPressed != null;

    final pill = Container(
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
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.md,
          // ⚠️ `widthFactor: 1`은 **가로만** 알약에 맞추라는 뜻이다. 세로는
          // 부모가 주는 만큼 늘어나고, 그 전체가 누르는 영역이 된다.
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}
