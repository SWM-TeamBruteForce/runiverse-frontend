import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/surface_card.dart';
import 'package:runiverse/core/widgets/page_indicator.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/core/widgets/run_map_view.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_controls.dart';
import 'package:runiverse/features/session/presentation/run_party_view.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 러닝 진행 (S13).
///
/// ## 실시간 기록이 **가운데**다
///
/// ```
/// 매칭:  내 GPS  │  실시간 기록 ★  │  파티원 비교
/// 혼자:  내 GPS  │  실시간 기록 ★
/// ```
///
/// 가장 자주 보는 화면이라 가운데에 두고, 양옆으로 한 번씩 밀면 닿게 한다.
/// 기록이 두 경우 모두 1번이라 [_pages]의 `initialPage`는 하나로 끝난다.
///
/// ⚠️ **시안(`158:3493`)은 기록을 첫째에 두었다 — 일부러 벗어난 것이다**
/// (2026-10-12 요청). 모르고 보면 "시안대로 되돌리는" 수정을 부른다.
///
/// ⚠️ **혼자 달릴 때도 GPS는 왼쪽이다.** 파티원이 없다고 순서를 당기면
/// 매칭과 솔로에서 **같은 손짓이 다른 화면**을 연다. 파티원 장은 끝에 붙고,
/// 없을 때는 그냥 없다 — 빈 장을 두면 밀었다가 아무것도 없는 화면을 만난다.
///
/// ## 화면을 켜 둔다
///
/// 포그라운드에서만 추적하므로 화면이 꺼지면 기록이 멈춘다. 러닝을 벗어날 때
/// 반드시 해제한다 — 안 하면 앱을 나가도 화면이 안 꺼진다.
class RunSessionPage extends ConsumerStatefulWidget {
  const RunSessionPage({super.key});

  @override
  ConsumerState<RunSessionPage> createState() => _RunSessionPageState();
}

class _RunSessionPageState extends ConsumerState<RunSessionPage> {
  /// 기록 장에서 시작한다. 지도가 0번, 기록이 1번이다.
  final _pages = PageController(initialPage: _initialPage);

  /// ⚠️ **[_initialPage]로 맞춰 둔다. 0이면 점이 거짓말을 한다.**
  ///
  /// `onPageChanged`는 처음에 불리지 않는다. 0으로 두면 기록 장이 떠 있는데
  /// **첫째 점**이 켜진다 — 예전에 지도를 0번에 두고 `initialPage`로 보정하며
  /// 실제로 겪은 일이다. `run_session_chrome_test`가 그 자리를 지킨다.
  int _page = _initialPage;

  /// 실시간 기록의 자리. 매칭이든 솔로든 **같은 1번**이다.
  static const _initialPage = 1;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _pages.dispose();
    super.dispose();
  }

  /// 멈추거나 다시 간다. **되돌릴 수 있는 것이라 길게 누르지 않는다.**
  ///
  /// ## ⚠️ 서버에도 알린다
  ///
  /// 1.1.0 전까지 일시정지는 **이 화면 안에만 있었다.** 상대 화면에서는 내가
  /// 계속 달리는 것으로 보였고, 서버는 멈춘 구간을 알 길이 없었다(가이드 2.1).
  ///
  /// 순서가 양쪽으로 다르다.
  ///
  /// - **멈출 때는 세션이 먼저다.** 세션이 멈춰야 들어오는 좌표를 버리고,
  ///   그래야 [RunningConnectionController.pause] 가 **다 흘려보낸 뒤** 알릴
  ///   수 있다. 거꾸로 하면 `PAUSE` 뒤에 좌표가 닿아 서버가 일시정지를 푼다.
  /// - **다시 갈 때는 알리는 것이 먼저다.** 좌표만으로도 서버는 돌아오지만
  ///   배치까지 최대 10초가 걸린다 — 그동안 상대 화면에는 멈춰 보인다.
  void _togglePause() {
    final controller = ref.read(runSessionControllerProvider.notifier);
    final connection = ref.read(runningConnectionProvider.notifier);
    if (ref.read(runSessionControllerProvider) is RunPaused) {
      connection.resume();
      controller.resume();
    } else {
      controller.pause();
      unawaited(connection.pause());
    }
  }

  /// 길게 누르기가 끝까지 찼다.
  ///
  /// ⚠️ `forced` 는 **목표를 채우기 전에 그만두는가**다. 서버가 이 값과 자기가
  /// 확정한 거리를 함께 보고 제재를 정한다 — 앱이 잰 거리로 단정하지 않는다.
  /// 목표가 없는 솔로는 언제나 `false` 다.
  ///
  /// ⚠️ **기준은 목표 전체다. 80% 가 아니다.** 가이드 3.2 가 "화면 거리가
  /// 목표 이상이면 `forced=false`, 미만이면 `forced=true`"로 정했다. 예전에는
  /// 80%(`_safeRatio`)로 갈랐는데, 그러면 85% 에서 멈춘 사람이 `forced=false`
  /// 로 나가 **끝낼 뜻이 분명한데 서버가 보류로 되돌려 보낸다.** 80% 는
  /// 제재 선이지 완주 선이 아니다.
  void _finishByHold() {
    final metrics = _metricsOf(ref.read(runSessionControllerProvider));
    final target = _targetDistanceMeters();
    final short = target != null && metrics.distanceMeters < target;
    unawaited(_finishRun(forced: short));
  }

  /// 목표의 80%까지 남은 거리(km). 이미 넘겼거나 목표가 없으면 `null` 이다.
  ///
  /// 예전에는 중지 시트가 이 안내를 들고 있었다. 시트를 없애면서 **종료를
  /// 누르고 있는 동안** 띄운다.
  ///
  /// ⚠️ **`null` 이 "제재 없다"는 뜻은 아니다.** 80% 판정은 서버가 정지
  /// 구간과 오염 좌표를 빼고 센 거리로 한다(가이드 3.4) — 화면에서 넘겼어도
  /// 모자랄 수 있다. 제재 안내는 `RunControls.hasTarget` 이 따로 들고 있고,
  /// 이 값은 **거리 줄 하나**만 가른다.
  double? _penaltyRemainingKm() {
    final target = _targetDistanceMeters();
    if (target == null) return null;

    final metrics = _metricsOf(ref.read(runSessionControllerProvider));
    final safe = target * _safeRatio;
    if (metrics.distanceMeters >= safe) return null;
    return (safe - metrics.distanceMeters) / 1000;
  }

  /// 러닝을 끝내고 요약으로 간다. **손으로 멈출 때와 목표에 닿을 때가 같은 길이다.**
  ///
  /// ## 순서가 명세로 정해져 있다
  ///
  /// `RUNNING_FINISH` → `RUNNING_FINISHED` ack → 로컬 트랙 삭제 → 결과 조회.
  /// 앞의 셋은 [RunningConnectionController.finish]가 맡고, 결과 조회는 요약
  /// 화면이 [RunningConnectionState.settling]이 풀린 뒤에만 연다.
  ///
  /// ⚠️ **ack를 기다리지 않고 요약으로 넘어간다.** 요약에 뜨는 값은 러닝 중
  /// 계산한 것이라 서버 확정과 무관하다. 기다리게 하면 신호가 나쁜 곳에서
  /// 요약조차 못 본다. 서버가 확정한 값을 읽는 **상세**만 기다린다.
  /// ## ⚠️ 이제 답을 기다린다
  ///
  /// 예전에는 요청만 던지고 **곧바로** 요약으로 넘어갔다. 1.1.0 서버는
  /// `RUNNING_GOAL_PENDING` 으로 **"확정 거리가 모자라다"** 고 답할 수 있는데,
  /// 그때는 러닝이 끝나지 않는다 — 먼저 넘어가 버리면 **러닝이 뒤에서 계속
  /// 도는 채로 요약 화면이 뜬다.**
  ///
  /// 기다리는 시간은 채널의 ack 타임아웃(15초)이 윗선이다. 못 받으면
  /// [FinishUnconfirmed] 로 떨어져 예전처럼 요약으로 간다 — 신호가 나쁜 곳에서
  /// 요약조차 못 보는 일은 그대로 막는다.
  Future<void> _finishRun({required bool forced}) async {
    if (_finishing) return;
    setState(() => _finishing = true);

    // 끝나면 소켓도 함께 닫힌다 — 안 닫으면 다음 러닝에서 서버가 중복 연결로
    // 보고 이쪽을 4001로 끊는다.
    final outcome = await ref
        .read(runningConnectionProvider.notifier)
        .finish(forced: forced);

    if (!mounted) return;

    // ⚠️ **러닝이 이어진다.** 세션을 접지도, 화면을 옮기지도 않는다.
    if (outcome is FinishGoalPending) {
      setState(() => _finishing = false);
      unawaited(_showGoalPending(outcome.remainingMeters));
      return;
    }

    // ⚠️ **세션은 여기서 접는다.** 보류일 수 있으므로 답을 받기 전에 접으면
    // 멀쩡한 러닝의 시계가 멈춘다.
    ref.read(runSessionControllerProvider.notifier).finish();
    context.pushReplacement(AppRoutes.runSummary);
  }

  /// 서버가 "아직 모자라다"고 답했다. **남은 거리를 보여 주고 고르게 한다** —
  /// 가이드 3.3.
  ///
  /// 돌아오는 값이 `true` 면 사용자가 끝내기로 했다는 뜻이다. 그때는
  /// `forced=true` 로 다시 보낸다 — 서버가 그 시점의 확정 거리로 완주인지
  /// 조기 종료인지 정한다.
  ///
  /// ## ⚠️ 창이 열린 동안에도 종료가 도착한다
  ///
  /// 계속 달리는 사이에 서버가 목표를 확인하면 `RUNNING_FINISHED` 가 온다.
  /// 가이드 3.3 은 그때 **창을 닫고** 종료 처리를 하라고 정했다.
  ///
  /// 닫는 일은 `Navigator` 가 한다 — 이 창은 **페이지 없는 경로**라 러닝
  /// 페이지에 매달려 있고, 요약으로 교체되는 순간 함께 걷힌다. 그래서 여기서
  /// 따로 `pop` 하지 않는다. (`pop` 을 끼워 둔 채로 **지워 보았다**. 창은 그대로
  /// 사라졌다 — 닫는 주체가 이쪽이 아니라는 뜻이다.)
  ///
  /// 걷히면 이 `await` 가 `null` 로 풀려 아무것도 보내지 않는다. 뒤늦은 손가락은
  /// [_finishing] 이 막는다 — 서버 종료를 받은 그 프레임에 세워진다.
  Future<void> _showGoalPending(int remainingMeters) async {
    final finish = await showDialog<bool>(
      context: context,
      // 바깥을 눌러 넘기지 못한다. 고를 것이 둘 다 뚜렷하다.
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.runGoalPendingTitle),
        content: Text(AppStrings.runGoalPendingBody(remainingMeters)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.runGoalPendingKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.runGoalPendingFinish),
          ),
        ],
      ),
    );
    if (finish != true || !mounted) return;
    unawaited(_finishRun(forced: true));
  }

  /// 끝내는 중인가. 목표 도달과 중지 시트가 겹쳐 두 번 보내는 것을 막는다.
  var _finishing = false;

  /// 제재 없이 끝낼 수 있는 선. 연동 가이드가 정한 값이다.
  static const _safeRatio = 0.8;

  /// 서버가 나를 참가자로 보지 않는다. **종료를 보내지 않는다** — 보내도 같은
  /// 답이 온다. 세션을 접고, 서버 상태를 다시 읽고, 홈으로 간다.
  Future<void> _leaveKickedOut() async {
    ref.read(runSessionControllerProvider.notifier).reset();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(AppStrings.runNotRoomPlayer)));
    context.go(AppRoutes.home);
    await ref.read(userStatusProvider.notifier).refresh();
  }

  /// 서버가 러닝을 끝냈다. 세션을 접고 홈으로 간다.
  ///
  /// ⚠️ **상태를 다시 읽지 않는다.** 이 화면이 여기 온 근거가 방금 읽은
  /// `IDLE`이다 — 다시 물으면 같은 답을 받고 정리가 한 번 더 돈다.
  void _leaveEnded() {
    ref.read(runSessionControllerProvider.notifier).reset();
    context.go(AppRoutes.home);
  }

  /// 매칭 러닝의 목표 거리. **솔로는 `null`이다** — 목표가 없어 제한도 없다.
  ///
  /// 방 정보가 실어 온 값을 먼저 쓴다. 그것이 없으면(복구 경로) 파티원 통지가
  /// 실어 오는 값으로 메운다. 둘 다 없으면 알 수 없고, 그때는 안내를 띄우지
  /// 않는다 — 모르면서 겁주지 않는다.
  int? _targetDistanceMeters() =>
      ref.read(runningConnectionProvider).room?.targetDistanceMeters ??
      ref
          .read(partyProvider)
          .rows
          .map((row) => row.progress?.targetDistanceMeters)
          .firstWhere((value) => value != null, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final state = ref.watch(runSessionControllerProvider);
    final metrics = _metricsOf(state);

    ref.listen(runningConnectionProvider.select((s) => s.failure), (_, next) {
      switch (next) {
        case RunningRoomFailure.notRoomPlayer:
          unawaited(_leaveKickedOut());
        // 서버가 이미 끝낸 러닝이다. **요약을 띄우지 않는다** — 화면의 수치는
        // 앱이 잰 것이라 서버가 확정한 기록과 다르고, 요약을 보여 주면 그것이
        // 남은 기록이라고 읽힌다. 기록 탭에서 서버가 만든 것을 본다.
        case RunningRoomFailure.endedByServer:
          _leaveEnded();
        case _:
          break;
      }
    });

    // ⚠️ **서버가 끝내면 따라간다.**
    //
    // 1.1.0부터 목표 도달 자동 종료는 **서버의 몫**이다(가이드 3.1). 앱이
    // 잰 거리로 보내던 것을 없앴다 — 서버는 정지 구간과 오염 좌표를 뺀
    // 확정 거리로 판단하므로, 앱 기준으로 넘었어도 아직 모자랄 수 있다.
    //
    // 내가 눌러서 끝낸 경우는 [_finishRun]이 화면을 옮기므로 여기서 또
    // 옮기지 않는다([_finishing]).
    ref.listen(runningConnectionProvider.select((s) => s.finishedRoomId), (
      previous,
      next,
    ) {
      if (next == null || next == previous || _finishing) return;
      debugPrint('[running] 서버가 끝냈다. 요약으로 간다');
      _finishing = true;
      ref.read(runSessionControllerProvider.notifier).finish();
      if (!mounted) return;

      // ⚠️ **왜 끝났는지 말해 준다.** 서버가 구간 번호를 이유로 좌표를 받지
      // 않으면 앱이 러닝을 끝내는데(1.1.1 3절), 알리지 않으면 **달리던 화면이
      // 저절로 요약으로 넘어간 것**으로만 보인다.
      //
      // `ScaffoldMessenger`는 라우트보다 위에 있어 요약으로 넘어가도 남는다 —
      // 이 화면에서 띄우고 바로 떠나는 것이 그래서 가능하다.
      if (ref.read(runningConnectionProvider).trackRejected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.runTrackRejected)),
        );
      }
      context.pushReplacement(AppRoutes.runSummary);
    });

    final party = ref.watch(partyProvider);
    // ⚠️ 매칭 방이면 파티원 줄이 비어도 화면을 둔다. 상대가 취소해도, 재시작
    // 뒤 첫 통지가 오기 전에도 **내 기록은 계속 보여야 한다.** 줄로만 정하면
    // 그 순간 3페이지가 2페이지로 접히며 내 카드가 사라진다(2026-09-17 21:38).
    final isMatched = ref.watch(
      runningConnectionProvider.select((state) => state.room?.isMatched),
    );
    final hasParty = isMatched == true || party.rows.isNotEmpty;
    // 목표는 방 정보가 실어 온다. 없으면 파티원 통지로 메운다. 솔로는 `null`.
    final target =
        ref.watch(
          runningConnectionProvider.select(
            (state) => state.room?.targetDistanceMeters,
          ),
        ) ??
        party.rows
            .map((row) => row.progress?.targetDistanceMeters)
            .firstWhere((value) => value != null, orElse: () => null);

    return PopScope(
      // 달리는 도중에 뒤로 나가지 못한다. 나가려면 중지 시트를 거쳐야 한다.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // 시안은 장마다 왼쪽 위에 제목을 둔다. 점만으로는 **몇 번째
              // 장인지는 알아도 그 장이 무엇인지는 모른다.**
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space2,
                  AppSpacing.space5,
                  AppSpacing.space4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _titleOf(_page, hasParty: hasParty),
                    style: AppTypographyV2.heading06.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),

              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (index) => setState(() => _page = index),
                  children: [
                    _MapPage(
                      metrics: metrics,
                      // ⚠️ 보정된 좌표를 그린다. 원본으로 선을 그리고 보정값으로
                      // 거리를 세면 화면의 선과 숫자가 다른 이야기를 한다.
                      track: ref
                          .read(runSessionControllerProvider.notifier)
                          .track,
                    ),
                    _MetricsPage(metrics: metrics),
                    if (hasParty)
                      RunPartyView(
                        board: party,
                        // ⚠️ 내 페이스는 앱이 잰 값이다. 내 거리는 provider가
                        // 보드에 넣는다.
                        //
                        // ⚠️ 예전 주석은 "서버는 본인 진행을 보내지 않는다"고
                        // 적혀 있었는데 **틀렸다.** 1인 러닝에서도 10초마다
                        // 보낸다(2026-10-06 확인). 거르는 것은 `PartyController`
                        // 가 맡는다.
                        myPace: metrics.currentPace,
                        targetDistanceMeters: target,
                        // ⚠️ **멈춘 것은 앱이 먼저 안다.** 서버가 콤보에서
                        // 나를 빼기까지는 시간이 걸려, 그 사이 내 카드가
                        // 서 있는 사람에게 "곁에서 달리는 중"이라고 말한다.
                        paused: state is RunPaused,
                      ),
                  ],
                ),
              ),

              // 연결이 없는 채로 달리는 중이면 알린다. **막지는 않는다** —
              // 기록은 계속 재고, 붙으면 쌓인 좌표가 올라간다(설계 문서 4절).
              if (!ref.watch(runningConnectionProvider).isReady)
                const _Notice(
                  icon: LucideIcons.cloudOff,
                  text: AppStrings.runOffline,
                )
              else if (ref.watch(
                runningConnectionProvider.select((s) => s.trackUnavailable),
              ))
                const _Notice(
                  icon: LucideIcons.cloudAlert,
                  text: AppStrings.runTrackUnavailable,
                ),

              // ⚠️ **점을 아래로 내렸다**(시안 `158:3493`). 위에 두면 제목과
              // 나란히 서서 둘 다 머리글처럼 보인다. 아래에 두면 좌우로 넘기는
              // 손가락이 닿는 자리와 가깝다.
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                child: PageIndicator(
                  // 파티원 장은 **함께 뛰는 사람이 있을 때만** 있다. 솔로에서
                  // 빈 장을 두면 스와이프했다가 아무것도 없는 화면을 만난다.
                  count: hasParty ? 3 : 2,
                  currentIndex: _page,
                ),
              ),

              RunControls(
                paused: state is RunPaused,
                enabled: state is RunRunning || state is RunPaused,
                onPauseToggle: _togglePause,
                onFinish: _finishByHold,
                hasTarget: target != null,
                penaltyRemainingKm: _penaltyRemainingKm(),
              ),
            ],
          ),
        ),
        backgroundColor: colors.bgBase,
      ),
    );
  }

  /// 지금 장의 제목. 파티원 장은 있을 때만 셋째다.
  static String _titleOf(int page, {required bool hasParty}) => switch (page) {
    0 => AppStrings.runPageMap,
    1 => AppStrings.runPageLive,
    _ => hasParty ? AppStrings.runPageParty : AppStrings.runPageLive,
  };

  static RunMetrics _metricsOf(RunSessionState state) => switch (state) {
    RunRunning(:final metrics) || RunPaused(:final metrics) => metrics,
    RunFinished(:final metrics) => metrics,
    _ => const RunMetrics(
      distanceMeters: 0,
      elapsed: Duration.zero,
      currentPace: null,
    ),
  };
}

/// 내 GPS 장 — 시안 `158:3545`.
///
/// 지도를 카드로 덮고 그 아래 `페이스`·`거리` 둘만 둔다.
///
/// ## ⚠️ 여기서는 둘만 보여준다
///
/// 실시간 기록 장에 넷이 있는데 여기에 또 넷을 두면 **같은 값을 두 번
/// 그리는 화면**이 된다. 지도를 보는 동안 궁금한 것은 "얼마나 왔나"와
/// "어느 속도인가" 둘이다 — 시안이 그렇게 골랐다.
class _MapPage extends StatelessWidget {
  const _MapPage({required this.metrics, required this.track});

  final RunMetrics metrics;

  /// 구간별 좌표. **일시정지로 끊긴 만큼 목록이 나뉜다** — 멈춘 사이를
  /// 직선으로 이으면 가지 않은 길이 그려진다.
  final List<List<GeoPoint>> track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space5,
        0,
        AppSpacing.space5,
        AppSpacing.space5,
      ),
      child: Column(
        children: [
          // 지도는 제 배경을 칠하므로 면을 깔지 않고 모서리만 깎는다.
          Expanded(
            child: ClipRRect(
              borderRadius: AppRadius.card,
              child: RunMapView.live(track: track),
            ),
          ),
          const SizedBox(height: AppSpacing.space4),

          Row(
            children: [
              Expanded(
                child: _InlineMetric(
                  label: AppStrings.runPaceLabel,
                  value: PaceCalculator.format(metrics.currentPace),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: _InlineMetric(
                  label: AppStrings.runDistanceLabel,
                  value:
                      '${(metrics.distanceMeters / 1000).toStringAsFixed(2)} km',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 지도 아래 가로 칸 — 라벨 왼쪽, 값 오른쪽.
///
/// 2×2 칸([_Metric])과 달리 **한 줄**이다. 지도에 자리를 내줘야 해서
/// 세로로 쌓을 높이가 없다.
class _InlineMetric extends StatelessWidget {
  const _InlineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space4,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypographyV2.body15.copyWith(color: colors.textTertiary),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTypographyV2.body02.copyWith(
              color: colors.textStrong,
              // 초마다 바뀐다. 안 주면 자릿수가 바뀔 때 숫자가 흔들린다.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 실시간 기록 장 — 시안 `158:3493`.
///
/// 페이스를 머리에 크게 두고, 나머지 넷을 2×2 카드로 깐다.
///
/// ## ⚠️ 라벨을 칩으로 만든 이유
///
/// 시안이 `페이스` 를 알약 안에 넣는다. 큰 수 바로 위에 맨 글자를 두면
/// **그 글자도 수치의 일부처럼 읽힌다** — 칩이 "이건 이름이다"라고 가른다.
class _MetricsPage extends StatelessWidget {
  const _MetricsPage({required this.metrics});

  final RunMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryMuted,
              borderRadius: AppRadius.full,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space2,
              ),
              child: Text(
                AppStrings.runPaceLabel,
                style: AppTypographyV2.body10.copyWith(color: colors.primary),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space3),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                PaceCalculator.format(metrics.currentPace),
                style: AppTypographyV2.heading01.copyWith(
                  color: colors.textStrong,
                  // ⚠️ **초마다 바뀐다.** 안 주면 자릿수가 바뀔 때 숫자가
                  // 좌우로 흔들린다. v1 `metricHero` 에는 들어 있던 것이다.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                AppStrings.profilePacePerKm,
                style: AppTypographyV2.body07.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space7),

          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: AppStrings.runElapsedLabel,
                  value: _elapsedText(metrics.elapsed),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: _Metric(
                  label: AppStrings.runDistanceLabel,
                  value: (metrics.distanceMeters / 1000).toStringAsFixed(2),
                  unit: 'km',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: AppStrings.runCadenceLabel,
                  // 권한이 없거나 걸음 센서가 없으면 `null`이다.
                  // 에뮬레이터에는 센서가 아예 없어 늘 `--`다.
                  value:
                      metrics.cadenceSpm?.toString() ??
                      AppStrings.runUnavailable,
                  unit: metrics.cadenceSpm == null ? null : 'spm',
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: _Metric(
                  label: AppStrings.runCaloriesLabel,
                  // 몸무게를 모르면 `null`이고 그때는 `--`다. 기본 체중으로
                  // 때우면 그 사람의 칼로리가 조용히 틀린다.
                  value:
                      metrics.calories?.toString() ?? AppStrings.runUnavailable,
                  unit: metrics.calories == null ? null : 'kcal',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _elapsedText(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 2×2 칸 하나 — 시안은 **카드**다. 예전에는 면 없는 글자였다.
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final unit = this.unit;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
      child: Column(
        children: [
          Text(
            label,
            style: AppTypographyV2.body15.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.space1),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTypographyV2.heading03.copyWith(
                  color: colors.textStrong,
                  // v1 `metricMd` 에는 들어 있던 것이다. `heading03` 에는 없다.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: AppSpacing.space1),
                Text(
                  unit,
                  style: AppTypographyV2.body15.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 서버에 아직 못 붙었거나, 붙었는데 저장이 밀리고 있다.
///
/// ⚠️ **경고가 아니라 안내다.** 기록은 계속 재고 있고, 연결되면 쌓인 좌표가
/// 올라간다. 빨간색으로 겁을 주면 달리는 사람이 폰을 들여다보게 된다.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.space4, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Text(
              text,
              style: AppTypographyV2.body15.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
