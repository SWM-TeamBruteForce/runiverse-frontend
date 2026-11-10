import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';

/// 홈 맨 위 줄 — 시안 `70:739`(외주 3차).
///
/// 지금은 오른쪽 알림 종만 있다. 시안 왼쪽의 `서울 강남구 · 맑음 18°`는
/// 날씨를 붙일 때 이 줄에 들어온다.
///
/// ## ⚠️ 알림함의 유일한 입구다
///
/// 하단 탭이 넷으로 고정이라 탭을 더할 자리가 없다. 예전에는 프로필 커버 위에
/// 있었고 그래서 프로필 탭에 점을 얹었는데, 입구를 홈으로 옮기면서 둘 다 뺐다.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    required this.badged,
    required this.onNotifications,
    super.key,
  });

  /// 읽지 않은 알림이 있는가.
  ///
  /// ⚠️ **숫자가 아니라 점이다.** 안 읽은 수가 서버와 어긋날 수 있어
  /// (연동 가이드 2-3) 숫자를 적으면 틀린 숫자를 적게 된다.
  final bool badged;

  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        _NotificationButton(badged: badged, onTap: onNotifications),
      ],
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.badged, required this.onTap});

  final bool badged;
  final VoidCallback onTap;

  /// 시안의 글리프 크기.
  static const _glyph = 26.0;

  /// 점의 지름. 탭 바·프로필 커버와 같다.
  static const _dot = 8.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return MergeSemantics(
      child: Semantics(
        // ⚠️ **점을 그림으로만 두면 읽히지 않는다.** 이 단추에는 글자가
        // 없어서 이 라벨이 스크린리더가 가진 전부다.
        label: badged
            ? '${AppStrings.notificationTitle}, '
                  '${AppStrings.notificationUnreadSemantics}'
            : AppStrings.notificationTitle,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              // 44 미만은 손가락이 빗나간다(`AppSizes` 주석).
              width: AppSizes.touchDefault,
              height: AppSizes.touchDefault,
              // ⚠️ **글리프를 칸의 오른쪽 끝에 붙인다** — 시안은 종과 히어로의
              // 오른쪽 끝이 같다(둘 다 x=398). 가운데에 두면 종이 안쪽으로 9
              // 들어간다.
              //
              // 칸을 오른쪽 여백으로 밀어내서 맞추면 안 된다. 부모 `Row` 밖으로
              // 나간 9는 **그려지기만 하고 눌리지 않는다** — Flutter는 누른
              // 자리가 부모 영역 밖이면 아래로 내려보내지 않는다.
              child: Align(
                alignment: Alignment.centerRight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppIcon(
                      AppIcons.bell,
                      size: _glyph,
                      color: colors.textPrimary,
                    ),
                    if (badged)
                      Positioned(
                        key: const ValueKey('home-notification-badge'),
                        top: -1,
                        right: -1,
                        child: Container(
                          width: _dot,
                          height: _dot,
                          decoration: BoxDecoration(
                            color: colors.error,
                            shape: BoxShape.circle,
                            // 글리프 선 위에 떠 보이게 바탕색 테두리를 둔다.
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
