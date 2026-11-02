import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
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
    this.badges = const {},
    super.key,
  });

  /// 순서가 곧 라우터의 branch 순서다. 어긋나면 엉뚱한 탭이 열린다.
  final List<AppTabSpec> tabs;

  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// 빨간 점을 얹을 탭의 인덱스.
  ///
  /// ## ⚠️ [AppTabSpec]에 담지 않는다
  ///
  /// 그 목록은 `static const`다(라우터 branch 순서와 묶여 있어 그래야 한다).
  /// 점은 알림이 오고 가며 바뀌므로 const에 들어갈 수 없다 — 셸이 매 빌드마다
  /// 여기로 넘긴다.
  ///
  /// ## ⚠️ 숫자가 아니라 점이다
  ///
  /// 서버가 깨진 행을 건너뛰어 안 읽은 수가 목록보다 클 수 있다(연동 가이드
  /// 2-3). 어긋난 숫자는 틀린 숫자지만, 점은 "있다/없다"만 말해서 틀릴 자리가
  /// 없다.
  final Set<int> badges;

  /// 바깥 프레임. 화면 좌우로 24씩 비운다.
  static const _sideMargin = 24.0;

  /// 화면 아래(제스처 바 아래)에서 띄우는 높이.
  static const _bottomMargin = 20.0;

  static const _barHeight = 60.0;
  static const _barRadius = 40.0;

  /// 알약 하나의 **최대** 폭. 시안은 86×52이고 바 안쪽으로 4 들어와 앉는다.
  ///
  /// ## ⚠️ 못 박으면 좁은 기기에서 마지막 탭이 깎인다
  ///
  /// 바 안쪽 폭은 `화면 폭 − 56`이다(좌우 여백 24씩, 안쪽 여백 4씩). 넷이면
  /// 344가 필요하니 **화면이 400보다 좁으면 넘친다** — 흔한 안드로이드 폰
  /// (360·384)도, 일반형 아이폰(393)도 여기에 든다. 넘친 자리는 둥근 모서리에
  /// 잘려 나가고, 릴리스 빌드는 넘침 경고도 안 띄운다.
  ///
  /// 그래서 이 값은 상한이고, 좁으면 `안쪽 폭 ÷ 탭 수`로 줄어든다.
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
            // 칸 폭은 **그릴 자리를 보고** 정한다. [_slotWidth] 참조.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotWidth = tabs.isEmpty
                    ? _slotWidth
                    : math.min(_slotWidth, constraints.maxWidth / tabs.length);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final (index, tab) in tabs.indexed)
                      _Slot(
                        tab: tab,
                        index: index,
                        width: slotWidth,
                        selected: index == currentIndex,
                        badged: badges.contains(index),
                        onTap: () => onSelected(index),
                      ),
                  ],
                );
              },
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
  const _Slot({
    required this.tab,
    required this.index,
    required this.width,
    required this.selected,
    required this.badged,
    required this.onTap,
  });

  final AppTabSpec tab;

  /// 점에 붙일 키를 만드는 데 쓴다. 테스트가 그것으로 찾는다.
  final int index;

  /// 바가 정해 준 폭. 넷이 나란히 들어가는 값이다([AppTabBarV2._slotWidth]).
  final double width;

  final bool selected;

  /// 읽지 않은 알림이 있는 탭인가.
  final bool badged;

  final VoidCallback onTap;

  /// 점의 지름. 글리프 모서리에 걸치는 크기다.
  static const _dot = 8.0;

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
        // ⚠️ **점을 그림으로만 두면 읽히지 않는다.** 이 바에는 글자가 하나도
        // 없어서 이 라벨이 스크린리더가 가진 전부다 — 점만 그리면 "읽지 않은
        // 알림이 있다"는 사실이 눈으로만 전해진다.
        label: badged
            ? '${tab.label}, ${AppStrings.notificationUnreadSemantics}'
            : tab.label,
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
              width: width,
              height: AppTabBarV2._slotHeight,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppIcon(
                      tab.icon,
                      // ⚠️ 선택된 아이콘은 **흰 알약 위**에 앉는다.
                      // `textPrimary`(#FAFAFA)를 쓰면 면과 같은 값이라 사라진다.
                      color: selected ? colors.primary : colors.textTertiary,
                    ),
                    if (badged)
                      Positioned(
                        key: ValueKey('tab-badge-$index'),
                        top: -2,
                        right: -2,
                        child: Container(
                          width: _dot,
                          height: _dot,
                          decoration: BoxDecoration(
                            color: colors.error,
                            shape: BoxShape.circle,
                            // 알약과 바 양쪽 면에서 모두 떠 보이게 테두리를
                            // 둔다. 없으면 선택된 흰 알약 위에서 번진다.
                            border: Border.all(color: colors.bgBase, width: 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
