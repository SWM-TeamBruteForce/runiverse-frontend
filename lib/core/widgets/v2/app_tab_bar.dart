import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';

/// 하단 탭 바 — 시안 `158:2899`.
///
/// **본문 위에 떠 있다.** 화면 아래에서 20 띄우고 좌우 24를 비운다. 반투명
/// 면에 블러를 걸어 뒤가 비치므로, 본문이 그 아래로 흘러가는 것이 보인다.
///
/// ## ⚠️ 글자 라벨이 없다
///
/// 시안이 아이콘만 둔다(CLAUDE.md Scope). 눈으로는 `책`이 기록이고 `사진`이
/// 기록카드라는 걸 알 수 없고, 스크린리더는 읽을 것이 아예 없다. 그래서
/// [AppTabSpec.label]은 **화면에 안 그려지지만 반드시 받는다** — [Semantics]가
/// 쓴다. 라벨을 선택 인자로 두면 다음 사람이 안 넣는다.
///
/// ## ⚠️ 이 위젯을 쓰는 [Scaffold]는 `extendBody: true`를 켠다
///
/// 안 켜면 바가 자리를 차지해서, 떠 있는 모양은 그대로인데 그 아래 빈 띠가
/// 생긴다. 켜면 본문이 바 뒤까지 내려오고 `MediaQuery.padding.bottom`에
/// 바 높이가 실려, 본문 쪽 `SafeArea`가 알아서 비켜난다.
class AppTabBarV2 extends StatelessWidget {
  const AppTabBarV2({
    required this.tabs,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  /// 순서가 곧 라우터의 branch 순서다. 어긋나면 엉뚱한 탭이 열린다.
  final List<AppTabSpec> tabs;

  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// 바깥 프레임. 화면 좌우로 24씩 비운다.
  static const _sideMargin = 24.0;

  /// 화면 아래(제스처 바 아래)에서 띄우는 높이.
  static const _bottomMargin = 20.0;

  static const _barHeight = 60.0;
  static const _barRadius = 40.0;

  /// 알약 하나. 86×52 이고 바 안쪽으로 4 들어와 앉는다.
  static const _slotWidth = 86.0;
  static const _slotHeight = 52.0;
  static const _barPadding = 4.0;

  static const _blur = 10.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: EdgeInsets.only(
        left: _sideMargin,
        right: _sideMargin,
        // 제스처 바 **아래**가 아니라 위로 띄운다. 기기의 시스템 여백을 먼저
        // 비우고 그 위에 20 을 더한다.
        bottom: _bottomMargin + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_barRadius),
        // ⚠️ **블러는 `ClipRRect` 안에 둔다.** 밖에 두면 화면 전체가 흐려진다 —
        // `BackdropFilter`는 자기 뒤가 아니라 **잘려나가기 전 전체**를 먹는다.
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
          child: Container(
            height: _barHeight,
            padding: const EdgeInsets.all(_barPadding),
            color: colors.bgGlass,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (index, tab) in tabs.indexed)
                  _Slot(
                    tab: tab,
                    selected: index == currentIndex,
                    onTap: () => onSelected(index),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 탭 하나의 명세. 아이콘과 — 그리지 않지만 읽히는 — 이름.
class AppTabSpec {
  const AppTabSpec({required this.icon, required this.label});

  /// [AppIcons]의 상수.
  final String icon;

  /// **화면에 안 그려진다.** 스크린리더가 읽는 이름이다.
  final String label;
}

class _Slot extends StatelessWidget {
  const _Slot({required this.tab, required this.selected, required this.onTap});

  final AppTabSpec tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    // ⚠️ **`excludeSemantics`를 쓰지 않는다.** 그걸 켜면 아래 [InkWell]이
    // 내보내는 **탭 액션까지 같이 지워진다** — 이름은 읽히는데 누를 수가
    // 없는 탭이 된다. 눈으로는 전혀 티가 안 난다(테스트가 잡았다).
    //
    // 대신 [MergeSemantics]로 이름과 탭 액션을 한 덩어리로 합친다.
    return MergeSemantics(
      child: Semantics(
        label: tab.label,
        button: true,
        selected: selected,
        child: Material(
          color: selected ? colors.bgInverse : Colors.transparent,
          // 알약 모양. `AppRadius`에 이만한 값이 없고, 시안도 높이를 넘는
          // 반경(89)을 줘서 "완전한 알약"을 뜻한다.
          borderRadius: BorderRadius.circular(AppTabBarV2._slotHeight / 2),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTabBarV2._slotHeight / 2),
            child: SizedBox(
              width: AppTabBarV2._slotWidth,
              height: AppTabBarV2._slotHeight,
              child: Center(
                child: AppIcon(
                  tab.icon,
                  // ⚠️ 선택된 아이콘은 **흰 알약 위**에 앉는다.
                  // `textPrimary`(#FAFAFA)를 쓰면 면과 같은 값이라 사라진다.
                  color: selected ? colors.primary : colors.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
