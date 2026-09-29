import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';

/// 페이지 위치 표시 점. 온보딩 소개(S02)와 러닝 중 3페이지 스와이프(S13)가 쓴다.
///
/// **활성 점은 색만 바뀌지 않고 길어진다.** 색으로만 정보를 전달하지 않는다는
/// 규칙(`docs/implementation-notes.md` §3-5)을 모양으로 만족시킨다.
///
/// 점은 정보 표시일 뿐 조작 수단이 아니다 — 눌러서 이동하게 만들지 않는다.
/// 8px짜리 탭 타깃은 44px 규칙을 지킬 수 없다. 이동은 스와이프와 버튼으로 한다.
///
/// ## 기존 [PageIndicator]와 모양이 같다
///
/// 시안(`158:2708`)의 점 묶음이 `44×8`이고, 이쪽은 점 8 · 활성 20 · 간격 8이라
/// 셋이면 `52×8`이다. **8px 차이뿐이고 형태·높이·활성 표시 방식이 같다.**
///
/// 그런데도 따로 두는 이유는 색이다. 기존 것은 `AppColors`를 읽는데 그것은
/// 옛 세대 토큰이라, 옮긴 화면이 쓰면 한 화면에 두 세대가 섞인다.
/// **모양이 아니라 토큰 때문에 나뉜 부품이다** — 시안이 점 모양을 바꾸면
/// 그때 여기만 고친다.
class PageIndicatorV2 extends StatelessWidget {
  const PageIndicatorV2({
    required this.count,
    required this.currentIndex,
    super.key,
  });

  final int count;
  final int currentIndex;

  /// 점 지름. 활성 점의 높이이기도 하다.
  static const _dotSize = AppSpacing.space2;

  /// 활성 점의 가로 길이.
  static const _activeWidth = AppSpacing.space5;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Semantics(
      label: '${currentIndex + 1} / $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.space2),
            AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.easeStandard,
              width: i == currentIndex ? _activeWidth : _dotSize,
              height: _dotSize,
              decoration: BoxDecoration(
                color: i == currentIndex ? colors.primary : colors.borderStrong,
                borderRadius: AppRadius.full,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
