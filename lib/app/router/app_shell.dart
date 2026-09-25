import 'dart:async';

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
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

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

  /// 포그라운드 복귀를 듣는다.
  ///
  /// ## ⚠️ 돌아올 때마다 서버에 다시 묻는다
  ///
  /// 앱이 뒤에 있는 동안 **매칭이 확정되거나 러닝이 강제 종료될 수 있다.**
  /// 서버가 예약으로 상태를 바꾸므로 앱은 통보를 받지 못한다. 돌아온 순간의
  /// 화면이 옛 상태면 사용자는 이미 끝난 매칭을 기다리게 된다.
  ///
  /// **여기 하나만 둔다.** 화면마다 붙이면 복귀 한 번에 여러 번 묻는다.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshStatus);
    // ⚠️ **세워질 때도 한 번 묻는다.** 스플래시를 거쳐 들어오면 이미 읽은
    // 값이 있지만, **로그인을 마치고 들어오는 길에는 없다** — 그 경로에는
    // 상태를 읽는 곳이 없어서, 진행 중인 매칭이 있어도 홈이 처음인 것처럼
    // 그려지고 신청을 누르면 409가 난다(에뮬레이터에서 확인).
    //
    // `build` 중에 provider를 건드리면 Riverpod이 막으므로 첫 프레임 뒤로 민다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshStatus();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// 서버 상태를 다시 읽는다.
  ///
  /// ⚠️ **여기서 화면을 옮기지 않는다.** 복귀할 때마다 사용자가 보던 화면을
  /// 빼앗으면, 기록을 보다가 홈으로 튕기는 일이 생긴다. 값만 갱신하고 그것을
  /// 보는 화면(홈의 배너 등)이 알아서 반응한다.
  void _refreshStatus() {
    if (ref.read(authControllerProvider) is! AuthSignedIn) return;
    unawaited(ref.read(userStatusProvider.notifier).refresh());
  }

  /// 로그인 화면으로 데리고 나간다.
  ///
  /// ⚠️ **빌드 도중에 옮기지 않는다.** `ref.listen` 콜백이 빌드 중에 불릴 수
  /// 있어, 그 자리에서 라우터를 건드리면 그리는 도중에 트리를 바꾸는 셈이다.
  void _leaveForSignIn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(AppRoutes.signIn);
    });
  }

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

    // ⚠️ **세션이 끝나면 여기서 데리고 나간다.**
    //
    // 갱신이 거절되면 `TokenRefresher`가 `AuthController.expireSession`을 부르고
    // 상태가 `AuthSignedOut`이 된다. 그것을 듣는 곳이 없으면 화면은 그대로
    // 남는데, **러닝 중이면 "서버에 연결하는 중"에서 영영 굳는다** — 끝낼
    // 수도, 다시 로그인할 수도 없다(2026-09-18 23:47 실주행).
    //
    // 화면마다 처리하지 않고 여기 하나만 둔다. 러닝·대기실은 셸 위에 얹히므로
    // `go`가 스택째 바꿔 그 화면들도 함께 빠져나온다.
    ref.listen(authControllerProvider, (before, after) {
      if (before is! AuthSignedIn || after is! AuthSignedOut) return;
      _leaveForSignIn();
    });

    // 매칭 스트림을 여기서 살려둔다. **화면이 소유하면 탭을 옮기는 사이에
    // 확정 통지를 놓친다.** 붙을지 끊을지는 provider가 유저 상태를 보고 정한다.
    ref.watch(matchRoomProvider);

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
