import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/app_tab_bar.dart';
import 'package:runiverse/core/widgets/profile_prompt_sheet.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/notification/domain/push_landing.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/notification/presentation/push_provider.dart';
import 'package:runiverse/features/session/domain/run_resume.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 하단 탭 셸 — 4개 탭의 공통 껍데기.
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
/// 여기 두면 네 탭 전부가 같은 관문을 지난다. 그것이 "프로필 없이는 앱을 쓸 수
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

  /// 알림 권한을 물으러 갔는가. [_gateUp]과 같은 이유로 둔다.
  bool _pushAsked = false;

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

  /// `dispose`에서는 `ref`를 쓸 수 없어 붙일 때 잡아 둔다.
  late final PushController _push = ref.read(pushProvider.notifier);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    // 셸이 없는 사이에 누른 푸시를 가리려고 알린다([PushController.attachShell]).
    _push.attachShell();
    // ⚠️ **세워질 때도 한 번 묻는다.** 스플래시를 거쳐 들어오면 이미 읽은
    // 값이 있지만, **로그인을 마치고 들어오는 길에는 없다** — 그 경로에는
    // 상태를 읽는 곳이 없어서, 진행 중인 매칭이 있어도 홈이 처음인 것처럼
    // 그려지고 신청을 누르면 409가 난다(에뮬레이터에서 확인).
    //
    // `build` 중에 provider를 건드리면 Riverpod이 막으므로 첫 프레임 뒤로 민다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshStatus();
      _startNotifications();
      // 꺼진 앱을 푸시로 열었으면 그 푸시는 셸이 서기 전에 이미 도착해 있다.
      unawaited(_openPushed());
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _push.detachShell();
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

  /// 앱 스트림을 열고 알림 첫 페이지를 받는다.
  ///
  /// ⚠️ **순서가 규칙이다** — 스트림 먼저, 목록 나중. `start()`가 그 순서를
  /// 지킨다. 바꾸면 목록 응답과 연결 사이에 생긴 알림이 영영 사라진다.
  void _startNotifications() {
    if (ref.read(authControllerProvider) is! AuthSignedIn) return;
    unawaited(ref.read(notificationProvider.notifier).start());
  }

  /// 포그라운드로 돌아왔다.
  ///
  /// ⚠️ **알림은 연결 여부와 무관하게 다시 받는다.** 스트림이 유지된 상태에서도
  /// 이벤트를 놓칠 수 있다(모바일 백그라운드·서버측 문제). `resume()`이 끊겼으면
  /// 다시 붙고, 어느 쪽이든 목록을 재조회한다.
  void _onResume() {
    _refreshStatus();
    if (ref.read(authControllerProvider) is! AuthSignedIn) return;
    unawaited(ref.read(notificationProvider.notifier).resume());
    // 앞선 기기 등록이 실패로 남았을 때만 다시 보낸다(명세 2-1).
    unawaited(ref.read(pushProvider.notifier).resume());
  }

  /// 프로필을 채운 사람에게 알림 권한을 묻는다. 관문이 서 있는 동안은 아직
  /// 홈에 들어온 것이 아니다.
  ///
  /// `build` 중에 권한 창을 띄우지 않는다. 첫 프레임 뒤로 민다.
  void _askPushIfNeeded() {
    if (_pushAsked) return;
    _pushAsked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(pushProvider.notifier).askPermission());
    });
  }

  /// 눌린 푸시가 가리키는 화면을 연다.
  ///
  /// ## ⚠️ 갈 곳이 없으면 옮기지 않는다
  ///
  /// 꺼진 앱이었으면 이미 홈이다. 뒤에 있던 앱이면 보던 화면을 빼앗지 않는다 —
  /// 달리는 중에 홈으로 끌어내면 러닝 화면이 사라진다([_refreshStatus]와 같은 판단).
  ///
  /// ## ⚠️ 카운트다운·러닝 중이면 버린다
  ///
  /// 셸 위에 얹힌 그 화면들 위로 옮기면 출발이나 달리기가 가려진다. 알림함에는
  /// 남아 있다([LaunchGate]가 같은 두 자리를 본다).
  Future<void> _openPushed() async {
    if (ref.read(authControllerProvider) is! AuthSignedIn) return;
    final landing = _push.take();
    if (landing == null) return;
    final where = GoRouter.of(context).state.matchedLocation;
    if (where == AppRoutes.matchCountdown || where == AppRoutes.runSession) {
      debugPrint('[push] 카운트다운·러닝 중이라 옮기지 않는다');
      return;
    }
    switch (landing) {
      case PushLandingProfile(:final userId):
        context.push(AppRoutes.userProfileOf(userId));
      case PushLandingNotifications():
        context.push(AppRoutes.notifications);
      case PushLandingRoom():
        // ⚠️ **상태를 다시 읽어야 방 화면이 스트림을 연다**(알림함의 초대 수락과
        // 같은 이유). 그사이 방을 나갔으면 열지 않는다.
        final status = await ref.read(userStatusProvider.notifier).refresh();
        if (!mounted || status == null) return;
        if (!RunResume.showsMatchBanner(status)) return;
        // 이미 대기방·출발 대기실이면 그대로 둔다. 하나 더 쌓으면 뒤로가기가
        // 같은 방으로 돌아온다.
        final here = GoRouter.of(context).state.matchedLocation;
        if (here == AppRoutes.matchRoom || here == AppRoutes.matchCountdown) {
          return;
        }
        context.push(AppRoutes.matchRoom);
    }
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
  /// 아이콘 넷은 **고른 것이 아니라 시안(`158:2899`)이 쓰는 것 그대로**다 —
  /// 내보낸 SVG 가 `assets/icons/`의 넷과 바이트까지 같았다.
  ///
  /// ⚠️ **라벨은 화면에 안 그려진다.** 시안이 아이콘만 두기로 해서
  /// (CLAUDE.md Scope) 스크린리더가 읽는 이름으로만 쓰인다.
  static const _tabs = <AppTabSpec>[
    AppTabSpec(icon: AppIcons.home, label: AppStrings.tabHome),
    AppTabSpec(icon: AppIcons.book, label: AppStrings.tabRecord),
    AppTabSpec(icon: AppIcons.photo, label: AppStrings.tabRecordCard),
    AppTabSpec(icon: AppIcons.profile, label: AppStrings.tabProfile),
  ];

  /// 프로필 탭의 자리. [_tabs] 순서와 함께 움직인다.
  static const _profileTab = 3;

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
    final colors = context.appColorsV2;

    // ⚠️ `AuthUnknown`이면 세우지 않는다. 모르는 상태에서 막아서면 이미 프로필을
    // 채운 사람도 잠깐 갇힌다.
    final auth = ref.watch(authControllerProvider);
    if (auth is AuthSignedIn) _gateIfNeeded(auth.isOnboarded);
    if (auth is AuthSignedIn && auth.isOnboarded) _askPushIfNeeded();

    // 뒤에 있던 앱에서 푸시를 눌렀다. 빌드 도중에 옮기지 않는다
    // ([_leaveForSignIn]과 같은 이유).
    //
    // ⚠️ **프레임을 직접 요청한다.** 푸시는 화면이 다 그려진 뒤에 올 수 있는데,
    // post-frame 콜백은 프레임을 부르지 않아 다음 터치 때까지 옮기지 않는다.
    ref.listen(pushProvider, (_, landing) {
      if (landing == null) return;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (mounted) unawaited(_openPushed());
        })
        ..scheduleFrame();
    });

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
      // ⚠️ **알림 연결도 함께 끊는다.** 남겨두면 로그아웃한 계정의 토큰으로
      // 다시 붙으려 하고, 백오프가 그것을 계속 되풀이한다.
      unawaited(ref.read(notificationProvider.notifier).signOut());
      _leaveForSignIn();
    });

    // 매칭 스트림을 여기서 살려둔다. **화면이 소유하면 탭을 옮기는 사이에
    // 확정 통지를 놓친다.** 붙을지 끊을지는 provider가 유저 상태를 보고 정한다.
    ref.watch(matchRoomProvider);

    // 앱 스트림도 같은 이유로 여기다. **매칭 스트림과 동시에 유지한다** —
    // 한쪽을 열었다고 다른 쪽을 닫으면 방에 있는 동안 알림을 못 받는다.
    final hasUnread = ref.watch(hasUnreadProvider);

    return Scaffold(
      backgroundColor: colors.bgBase,
      // ⚠️ **탭 바가 본문 위에 뜬다.** 이걸 안 켜면 바는 그대로 떠 보이는데
      // 그 아래 빈 띠가 생긴다. 켜면 본문이 바 뒤까지 내려오고, 바 높이가
      // `MediaQuery.padding.bottom`에 실려 본문 쪽 `SafeArea`가 알아서 비켜난다.
      extendBody: true,
      body: widget.navigationShell,
      bottomNavigationBar: AppTabBarV2(
        tabs: _tabs,
        currentIndex: widget.navigationShell.currentIndex,
        // 알림함이 프로필 탭 안에 있어서, 다른 탭에 있을 때 알려 줄 자리가
        // 여기 하나뿐이다.
        badges: hasUnread ? const {_profileTab} : const <int>{},
        onSelected: _onDestinationSelected,
      ),
    );
  }
}
