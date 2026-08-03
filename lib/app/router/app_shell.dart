import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 하단 탭 셸 — 5개 탭의 공통 껍데기.
///
/// [StatefulNavigationShell]이 탭별 [Navigator]를 들고 있고, 이 위젯은
/// 그것을 `body`에 꽂고 아래에 탭 바를 붙인다. **탭을 옮겨도 이 위젯은 살아있다** —
/// 그래서 탭 바가 깜빡이지 않고, 각 탭의 스크롤 위치와 화면 스택이 보존된다.
///
/// ⚠️ **위젯이 살아있다고 provider까지 사는 건 아니다.**
/// 안 보이는 탭의 provider는 구독자가 없어 dispose된다. 매칭 타이머나 WebSocket을
/// 홈 화면 provider에 두면 탭을 옮기는 순간 끊긴다.
/// 전역 상태는 `keepAlive`를 명시하고 셸 레이어에서 구독한다
/// (`docs/implementation-notes.md` §5-1).
///
/// 글로벌 매칭 스티키 배너도 나중에 **여기 한 곳에만** 붙인다. 화면마다 복붙하지 않는다.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// 탭 바 항목. 순서가 곧 라우터의 branch 순서이고, 어긋나면 엉뚱한 탭이 열린다.
  ///
  /// 아이콘은 **Lucide 2px 스트로크**다(와이어프레임_최종 C1).
  /// 어느 글리프를 쓸지는 문서가 정해두지 않아 뜻이 가장 가까운 것을 골랐다 —
  /// 피드는 카드 리스트 화면(S19)이라 `layoutList`를 썼다.
  static const _tabs = <_TabSpec>[
    _TabSpec(AppStrings.tabHome, LucideIcons.house),
    _TabSpec(AppStrings.tabRecord, LucideIcons.calendarDays),
    _TabSpec(AppStrings.tabFeed, LucideIcons.layoutList),
    _TabSpec(AppStrings.tabCompetition, LucideIcons.flag),
    _TabSpec(AppStrings.tabProfile, LucideIcons.user),
  ];

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      // 이미 열려 있는 탭을 다시 누르면 그 탭의 첫 화면으로 돌아간다.
      // (기록 상세를 3단계 파고들었다가 기록 탭을 누르면 캘린더로 복귀)
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        // 탭 바와 본문 사이 경계선. NavigationBar 자체에는 테두리 옵션이 없다.
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.borderDefault)),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onDestinationSelected,
          backgroundColor: colors.bgSurface,
          // 다크에서는 그림자 대신 면 밝기로 높이를 표현한다. M3 기본 틴트도 함께 꺼진다.
          elevation: 0,
          indicatorColor: colors.primaryMuted,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return AppTypography.caption.copyWith(
              color: selected ? colors.primary : colors.textTertiary,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            );
          }),
          destinations: [
            for (final tab in _tabs)
              NavigationDestination(
                label: tab.label,
                icon: Icon(tab.icon, color: colors.textTertiary),
                // 같은 글리프에 색만 바꾼다. Lucide는 채움 변형이 없다.
                selectedIcon: Icon(tab.icon, color: colors.primary),
              ),
          ],
        ),
      ),
    );
  }
}

/// 탭 하나의 명세. 라벨과 아이콘.
///
/// 선택 상태에 다른 글리프를 쓰지 않는다. Lucide는 스트로크 전용이라 채움 변형이 없다.
/// 그래도 **색만으로 구분하지는 않는다** — M3 `NavigationBar`가 선택 항목 뒤에
/// pill 인디케이터를 깔아주고, 라벨 웨이트도 함께 올라간다.
class _TabSpec {
  const _TabSpec(this.label, this.icon);

  final String label;
  final IconData icon;
}
