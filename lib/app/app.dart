import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_router.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/app_update/presentation/app_update_gate.dart';
import 'package:runiverse/features/matching/presentation/launch_gate.dart';
import 'package:runiverse/features/notification/presentation/push_provider.dart';

/// 앱 루트 — 테마와 라우터를 [MaterialApp]에 꽂는다.
///
/// 선언형 라우팅이므로 `MaterialApp`이 아니라 **`MaterialApp.router`** 다.
/// `home:`이나 `routes:`를 쓰지 않고 `routerConfig`에 라우터를 통째로 넘긴다.
///
/// ## 다크가 기본이다
///
/// 디자인 시스템의 기준 테마는 다크다. 라이트도 완전 대칭으로 정의돼 있어서
/// [ThemeMode.system]으로 바꾸면 바로 따라가지만, 아직 라이트 화면을 검수하지
/// 않았으므로 다크로 고정한다.
///
/// ## StatefulWidget인 이유
///
/// 라우터를 `build` 안에서 만들면 리빌드할 때마다 새 라우터가 생겨 현재 위치를
/// 잃는다. [State]에 한 번만 만들어 들고 있는다.
class RuniverseApp extends ConsumerStatefulWidget {
  const RuniverseApp({this.initialLocation, super.key});

  /// 앱이 처음 열 화면. 비우면 스플래시(S01)에서 시작한다.
  ///
  /// 온보딩을 거치지 않고 특정 화면을 바로 띄우고 싶을 때 쓴다.
  /// 탭 셸 테스트가 온보딩 흐름에 묶이면, 온보딩에 화면을 하나 넣을 때마다
  /// 관계없는 테스트가 깨진다.
  final String? initialLocation;

  @override
  ConsumerState<RuniverseApp> createState() => _RuniverseAppState();
}

class _RuniverseAppState extends ConsumerState<RuniverseApp> {
  late final GoRouter _router = createAppRouter(
    initialLocation: widget.initialLocation,
  );

  /// 마지막으로 남긴 화면. 같은 화면이 연달아 남지 않게 막는다.
  String? _lastScreen;

  /// 마지막으로 건 회원 ID. 프로필 갱신처럼 같은 회원으로 상태만 바뀔 때는
  /// 다시 걸지 않는다.
  String? _lastUserId;

  /// 이번 실행에서 회원 ID 를 한 번이라도 보냈는가. `null` 을 보낸 것과
  /// 아직 안 보낸 것을 가른다.
  bool _userIdSynced = false;

  @override
  void initState() {
    super.initState();
    // ⚠️ **`FirebaseAnalyticsObserver` 대신 라우터를 직접 듣는다.**
    // 탭을 바꿔도 라우트를 밀어 넣지 않는 `StatefulShellRoute.indexedStack`
    // 에서는 관찰자가 불리지 않아 **탭 재방문이 통째로 빠졌고**, 루트와 브랜치
    // 관찰자가 겹쳐 **첫 방문이 두 번** 찍혔다. 기기에서 보고 바꿨다.
    _router.routerDelegate.addListener(_onRouteChanged);
    // 첫 화면은 이 리스너가 붙기 전에 이미 섰다. 한 번 직접 남긴다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRouteChanged());

    // 회원 ID 도 로그인 상태를 듣고 건다. 로그인 성공 자리에서 걸면 앱을 다시
    // 켜 자동 로그인된 경우를 놓친다 — 상태는 로그인·자동 로그인·로그아웃·탈퇴·
    // 세션 만료를 다 지난다.
    ref.listenManual(
      authControllerProvider,
      (_, next) => _onAuthChanged(next),
      fireImmediately: true,
    );

    // 푸시 기기 등록도 같은 이유로 여기서 시작한다. 셸에서 시작하면 가입한
    // 사람은 프로필 입력을 마칠 때까지 등록이 미뤄진다.
    ref.read(pushProvider.notifier).start();
  }

  void _onAuthChanged(AuthState auth) {
    final String? userId;
    switch (auth) {
      // 아직 모른다. 떼지도 걸지도 않는다.
      case AuthUnknown():
        return;
      case AuthSignedIn(userId: final id):
        userId = id;
      case AuthSignedOut():
        userId = null;
    }
    // ⚠️ **처음 판정된 로그아웃도 보낸다.** GA 는 회원 ID 를 기기에 남겨 두므로,
    // 지난 실행에 로그인했다가 이번에 세션이 만료된 사람은 `null` 을 보내야 떨어진다.
    if (_userIdSynced && userId == _lastUserId) return;
    _userIdSynced = true;
    _lastUserId = userId;
    unawaited(ref.read(analyticsProvider).setUserId(userId));
  }

  void _onRouteChanged() {
    final name = _router.state.name;
    // 이름이 없는 라우트는 없지만, 생기면 조용히 건너뛴다 — 이름 없는
    // `screen_view` 는 지표에서 쓸모가 없다.
    if (name == null || name == _lastScreen) return;
    _lastScreen = name;
    unawaited(ref.read(analyticsProvider).screenView(name: name));
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onRouteChanged);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      // Android 작업 전환기에 뜨는 이름.
      title: 'Runiverse',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      // ⚠️ **출발은 화면을 가리지 않는다.** 로비에 서 있어야만 러닝이
      // 시작되던 것을 여기서 받는다 — 어느 화면에 있든 1분 전에 안내하고
      // 로비로, 30초 전에는 카운트다운으로 보낸다([LaunchGate]).
      // ⚠️ **업데이트 게이트가 바깥이다.** 안쪽에 두면 `LaunchGate`의 자동
      // 이동이 막힌 앱을 러닝으로 밀어 넣는다 — 서버는 403만 돌려주므로
      // 좌표 한 점 없는 러닝 화면이 남는다.
      builder: (context, child) => AppUpdateGate(
        child: LaunchGate(
          router: _router,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
