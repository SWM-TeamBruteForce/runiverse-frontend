import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';

/// 가입 흐름의 몇 걸음째인지 알리는 막대.
/// 시안 `158:2840`(약관) · `158:2721`(회원가입) · `158:2767`(프로필 등록).
///
/// ## ⚠️ 시안의 픽셀을 옮기지 않는다
///
/// 시안의 채움 폭이 `91 / 182 / 273`(=25 / 50 / 75%)이라 **네 걸음을 전제**한다.
/// 우리 가입 흐름은 **세 걸음**이다 — 약관 → 회원가입 → 프로필 등록.
/// 그래서 폭을 [step] / [total]로 센다. 흐름이 늘거나 줄어도 부르는 쪽만 고치면 된다.
///
/// ## 색으로만 알리지 않는다
///
/// 막대는 눈으로만 읽힌다. [Semantics]에 `2 / 3`을 넣어 스크린리더가 같은 것을
/// 말하게 한다.
class StepProgressV2 extends StatelessWidget {
  const StepProgressV2({required this.step, required this.total, super.key});

  /// 지금 몇 걸음째인가. 1부터 센다.
  final int step;

  /// 모두 몇 걸음인가.
  final int total;

  /// 위젯 테스트가 폭의 비율을 재는 손잡이.
  static const trackKey = ValueKey('step-progress-track');
  static const fillKey = ValueKey('step-progress-fill');

  /// 시안의 막대 두께. `AppSpacing.space1`과 같은 4다.
  static const _thickness = AppSpacing.space1;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    // ⚠️ 부르는 쪽이 먼저 틀릴 수 있다. 범위를 벗어난 값이 와도 막대는 넘치지
    // 않게 잘라 둔다 — 레이아웃까지 깨지면 무엇이 원인인지 찾기 어려워진다.
    final ratio = total <= 0 ? 0.0 : (step / total).clamp(0.0, 1.0);

    return Semantics(
      value: '$step / $total',
      child: Container(
        key: trackKey,
        height: _thickness,
        decoration: BoxDecoration(
          // ⚠️ 트랙에 맞는 이름의 토큰이 아직 없다. 시안의 `#575757`에 가장
          // 가까운 값이 `borderStrong`(다크 `#434343`)이고, 역할도 "면을 가르는
          // 선"이라 그나마 맞다. `bgControl` 같은 이름이 생기면 그리로 옮긴다.
          color: colors.borderStrong,
          borderRadius: AppRadius.full,
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio,
          child: DecoratedBox(
            key: fillKey,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: AppRadius.full,
            ),
          ),
        ),
      ),
    );
  }
}
