import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/app_update/domain/app_update_status.dart';
import 'package:runiverse/features/app_update/presentation/app_update_page.dart';
import 'package:runiverse/features/app_update/presentation/app_update_provider.dart';

/// 최소 버전에 못 미치면 **앱 전체를 덮는다.**
///
/// ## ⚠️ 라우트로 두지 않는 이유
///
/// 라우트면 벗어날 길이 여럿이다 — 뒤로가기, 딥링크, 그리고 `LaunchGate`가
/// 출발 30초 전에 **어느 화면에 있든** 카운트다운으로 밀어 넣는 자동 이동이
/// 있다. 막힌 앱이 그 길로 러닝에 들어가면 서버는 403만 돌려주고, 사용자는
/// 좌표 한 점 없는 러닝 화면을 본다.
///
/// `MaterialApp.builder`에서 `child`를 **통째로 갈아 끼우면** 라우터가 무엇을
/// 그리든 화면에 닿지 않는다.
///
/// ## 포그라운드로 돌아올 때마다 다시 묻는다
///
/// 최소 버전은 서버에서 언제든 올라간다. 켜 둔 앱이 계속 괜찮다고 믿으면,
/// 올린 뒤에도 그 앱은 403만 받으면서 이유를 모른다.
///
/// 반대로 **막혀 있을 때도 다시 묻는다** — 최소 버전이 내려가면 풀어 줘야
/// 한다(명세).
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _recheck);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// 앱으로 돌아왔다. 판정을 다시 받는다.
  ///
  /// ⚠️ **스플래시가 아직 묻는 중이면 손대지 않는다.** 권한 팝업처럼 버전
  /// 확인도 몇 백 ms 걸리는데, 그사이 복귀가 오면 같은 요청이 두 번 나간다.
  /// (겹쳐 불러도 `check()`가 하나로 묶지만, 여기서 거르는 편이 분명하다.)
  void _recheck() {
    if (ref.read(appUpdateProvider) is AppUpdateUnknown) return;
    unawaited(ref.read(appUpdateProvider.notifier).recheck());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateProvider);

    // ⚠️ **막는 것은 `required` 하나뿐이다.** 못 물어봤거나(`unknown`) 못
    // 받은(`unreachable`) 것을 막으면, 서버가 잠깐 흔들릴 때 멀쩡한 앱이
    // 통째로 서 버린다. 스플래시가 "판정 없이 들여보내지 않는" 책임을 따로
    // 지므로 여기서 두 번 막을 이유가 없다.
    final blocked =
        state is AppUpdateChecked && state.status == AppUpdateStatus.required;

    return blocked ? const AppUpdatePage() : widget.child;
  }
}
