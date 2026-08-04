import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_router.dart';
import 'package:runiverse/core/theme/app_theme.dart';

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
class RuniverseApp extends StatefulWidget {
  const RuniverseApp({this.initialLocation, super.key});

  /// 앱이 처음 열 화면. 비우면 스플래시(S01)에서 시작한다.
  ///
  /// 온보딩을 거치지 않고 특정 화면을 바로 띄우고 싶을 때 쓴다.
  /// 탭 셸 테스트가 온보딩 흐름에 묶이면, 온보딩에 화면을 하나 넣을 때마다
  /// 관계없는 테스트가 깨진다.
  final String? initialLocation;

  @override
  State<RuniverseApp> createState() => _RuniverseAppState();
}

class _RuniverseAppState extends State<RuniverseApp> {
  late final GoRouter _router = createAppRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
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
    );
  }
}
