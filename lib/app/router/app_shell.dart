import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/profile_prompt_sheet.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';

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
///
/// ## 프로필 관문도 여기 하나뿐이다
///
/// 프로필이 없으면 [showProfilePromptSheet]가 막아선다. **탭마다 두지 않는다** —
/// `StatefulShellRoute.indexedStack`은 한 번 열린 탭을 살려두므로, 탭마다 띄우면
/// 시트가 겹쳐 쌓인다.
///
/// 여기 두면 다섯 탭 전부가 같은 관문을 지난다. 그것이 "프로필 없이는 앱을 쓸 수
/// 없다"는 규칙과도 맞는다 — 홈만 막으면 다른 탭으로 돌아 들어갈 수 있다.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// 관문을 지금 세워 뒀는가. 없으면 화면이 다시 그려질 때마다 시트가 쌓인다 —
  /// `build`는 한 번만 불리는 자리가 아니다.
  bool _gateUp = false;

  /// 프로필이 없으면 관문을 세운다.
  ///
  /// `build` 중에 `showModalBottomSheet`를 부를 수 없다(그리는 도중에 트리를
  /// 바꾸는 셈이다). 첫 프레임이 끝난 뒤로 미룬다.
  void _gateIfNeeded(bool isOnboarded) {
    if (isOnboarded || _gateUp) return;
    _gateUp = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showProfilePromptSheet(
        context,
        onStart: () async {
          // **첫 로그인 때와 같은 화면**을 연다. 프로필을 받는 곳이 둘이면
          // 규칙도 둘이 되고, 한쪽만 고치는 사고가 난다.
          await context.push(AppRoutes.profileSetup);
          if (!mounted) return;

          // ⚠️ 채우지 않고 돌아왔을 수 있다. 그때 관문을 다시 세우지 않으면
          // **뒤로가기 한 번으로 관문이 뚫린다.**
          //
          // 채웠으면 `markOnboarded`가 상태를 바꿔 아래 `build`가 건너뛴다.
          setState(() => _gateUp = false);
        },
      );
    });
  }

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
    widget.navigationShell.goBranch(
      index,
      // 이미 열려 있는 탭을 다시 누르면 그 탭의 첫 화면으로 돌아간다.
      // (기록 상세를 3단계 파고들었다가 기록 탭을 누르면 캘린더로 복귀)
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // ⚠️ `AuthUnknown`이면 세우지 않는다. 모르는 상태에서 막아서면 이미 프로필을
    // 채운 사람도 잠깐 갇힌다.
    final auth = ref.watch(authControllerProvider);
    if (auth is AuthSignedIn) _gateIfNeeded(auth.isOnboarded);

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: DecoratedBox(
        // 탭 바와 본문 사이 경계선. NavigationBar 자체에는 테두리 옵션이 없다.
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.borderDefault)),
        ),
        child: NavigationBar(
          selectedIndex: widget.navigationShell.currentIndex,
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
