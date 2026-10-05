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
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/surface_card.dart';
import 'package:runiverse/core/widgets/page_indicator.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/core/widgets/run_map_view.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_party_view.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/run_stop_sheet.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 러닝 진행 (S13).
///
/// ## 2페이지다
///
/// 정본은 지도 · 실시간 기록 · 파티원 비교 셋인데 **혼자 달릴 때는 파티원이
/// 없다.** 빈 페이지를 두면 스와이프해서 아무것도 없는 화면을 만나게 된다.
/// 매칭이 붙으면 셋째 장으로 들어간다.
///
/// 첫 장은 **실시간 기록**이다. 가장 자주 보는 화면이라 정본이 그렇게 정했다.
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
  /// ⚠️ **첫 장이 실시간 기록이다. 시안(`158:3493`)의 점 셋 중 첫째가 켜져
  /// 있다.** 예전에는 지도를 0번에 두고 `initialPage: 1` 로 보정했는데,
  /// 그러면 기록 장에서 **둘째 점이 켜져** 점이 거짓말을 했다.
  final _pages = PageController();
  int _page = 0;

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

  Future<void> _openStopSheet() async {
    final controller = ref.read(runSessionControllerProvider.notifier);
    controller.pause();

    final metrics = _metricsOf(ref.read(runSessionControllerProvider));
    final target = _targetDistanceMeters();

    final action = await showRunStopSheet(
      context,
      metrics: metrics,
      targetDistanceMeters: target,
    );
    if (!mounted) return;

    switch (action) {
      case RunStopAction.resume || null:
        // 시트를 쓸어내려 닫아도 재개한다. 멈춘 채로 두면 시간이 흐르지 않는데
        // 화면은 러닝 중으로 보인다.
        controller.resume();
      case RunStopAction.finish:
        // ⚠️ `forced`는 **목표를 채우기 전에 그만두는가**다. 서버가 이 값과
        // 자기가 확정한 거리를 함께 보고 제재를 정한다 — 앱이 잰 거리로
        // 단정하지 않는다. 목표가 없는 솔로는 언제나 `false`다.
        final short =
            target != null && metrics.distanceMeters < target * _safeRatio;
        _finishRun(forced: short);
    }
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
  void _finishRun({required bool forced}) {
    if (_finishing) return;
    _finishing = true;

    ref.read(runSessionControllerProvider.notifier).finish();
    // 끝나면 소켓도 함께 닫힌다 — 안 닫으면 다음 러닝에서 서버가 중복 연결로
    // 보고 이쪽을 4001로 끊는다.
    unawaited(
      ref.read(runningConnectionProvider.notifier).finish(forced: forced),
    );
    if (mounted) context.pushReplacement(AppRoutes.runSummary);
  }

  /// 끝내는 중인가. 목표 도달과 중지 시트가 겹쳐 두 번 보내는 것을 막는다.
  var _finishing = false;

  /// 목표 거리에 닿았다. **사용자가 누르기를 기다리지 않는다.**
  ///
  /// ## ⚠️ `forced`는 거짓이다
  ///
  /// 명세가 `forced`를 **"목표 거리 달성 전 사용자의 종료 의사"** 로 정의한다.
  /// 목표를 채우고 끝나는 것은 의사 표시가 아니라 완주라, 참이면 서버가 조기
  /// 종료로 읽는다. 최종 완주·이탈 판정은 어차피 서버가 확정 거리로 한다.
  void _finishIfTargetReached(RunSessionState state) {
    if (_finishing || state is! RunRunning) return;
    final target = _targetDistanceMeters();
    if (target == null || state.metrics.distanceMeters < target) return;

    debugPrint('[running] 목표 ${target}m에 닿았다. 종료를 보낸다');
    _finishRun(forced: false);
  }

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

    // ⚠️ **목표에 닿으면 스스로 끝낸다.** 명세가 정한 순서는
    // `RUNNING_FINISH` → ack → 로컬 트랙 삭제 → 결과 조회인데, 예전에는 그
    // 첫 줄이 **사용자가 중지를 누를 때만** 나갔다. 목표를 채우고도 안 누르면
    // 서버는 그 러닝을 계속 진행 중으로 들고 있는다.
    //
    // `listen`으로 듣는다 — `build` 안에서 바로 판정하면 그리는 도중에
    // 화면을 옮기게 된다.
    ref.listen(runSessionControllerProvider, (_, next) {
      _finishIfTargetReached(next);
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
                    _MetricsPage(metrics: metrics),
                    // ⚠️ 보정된 좌표를 그린다. 원본으로 선을 그리고 보정값으로
                    // 거리를 세면 화면의 선과 숫자가 다른 이야기를 한다.
                    RunMapView(
                      track: ref
                          .read(runSessionControllerProvider.notifier)
                          .track,
                    ),
                    if (hasParty)
                      RunPartyView(
                        board: party,
                        // ⚠️ 내 페이스는 앱이 잰 값이다. 서버는 본인 진행을
                        // 보내지 않는다. 내 거리는 provider가 보드에 넣는다.
                        myPace: metrics.currentPace,
                        targetDistanceMeters: target,
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

              Padding(
                padding: const EdgeInsets.all(AppSpacing.space5),
                child: AppButtonV2(
                  label: AppStrings.runStopCta,
                  variant: AppButtonV2Variant.secondary,
                  onPressed: state is RunRunning ? _openStopSheet : null,
                ),
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
    0 => AppStrings.runPageLive,
    1 => AppStrings.runPageMap,
    _ => hasParty ? AppStrings.runPageParty : AppStrings.runPageMap,
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
