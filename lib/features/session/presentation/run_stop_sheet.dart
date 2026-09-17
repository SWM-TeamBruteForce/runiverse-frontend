import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/session/domain/pace_calculator.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';

/// 중지 시트에서 고른 것.
enum RunStopAction {
  /// 계속 달린다.
  resume,

  /// 러닝을 끝낸다. **길게 눌러야만** 나온다.
  finish,
}

/// 달리다 멈췄을 때 뜨는 시트.
///
/// ⚠️ **부르기 전에 `pause()`를 먼저 한다.** 시트가 뜨는 동안에도 시간이 흐르면
/// "멈췄는데 기록은 늘어난다"가 된다.
///
/// 쓸어내려 닫으면 `null`이 온다. 부르는 쪽이 그것을 [RunStopAction.resume]과
/// 같이 다뤄야 한다 — 멈춘 채로 두면 화면은 러닝 중인데 시간이 흐르지 않는다.
Future<RunStopAction?> showRunStopSheet(
  BuildContext context, {
  required RunMetrics metrics,
  int? targetDistanceMeters,
}) {
  return showModalBottomSheet<RunStopAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.appColors.bgScrim,
    // 실수로 닫히면 안 된다. 멈춘 상태가 화면에 드러나야 한다.
    isDismissible: false,
    builder: (context) => _StopSheet(
      metrics: metrics,
      targetDistanceMeters: targetDistanceMeters,
    ),
  );
}

class _StopSheet extends StatelessWidget {
  const _StopSheet({required this.metrics, this.targetDistanceMeters});

  final RunMetrics metrics;

  /// 매칭 러닝의 목표 거리. **솔로는 `null`이다** — 목표가 없어 제한도 없다.
  final int? targetDistanceMeters;

  /// 제재 없이 끝낼 수 있는 선. 가이드가 정한 값이다.
  static const _safeRatio = 0.8;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space5,
          AppSpacing.space5,
          AppSpacing.space5,
          AppSpacing.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.runPausedTitle,
              textAlign: TextAlign.center,
              style: AppTypography.h3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space4),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Value(
                  label: AppStrings.runDistanceLabel,
                  value: (metrics.distanceMeters / 1000).toStringAsFixed(2),
                ),
                _Value(
                  label: AppStrings.runTimeLabel,
                  value: _elapsedText(metrics.elapsed),
                ),
                _Value(
                  label: AppStrings.runPaceLabel,
                  value: PaceCalculator.format(metrics.currentPace),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space5),

            // ⚠️ 끝내기 전에 알린다. 끝낸 뒤에 알리면 되돌릴 수 없다.
            if (_shortfallKm case final short?) ...[
              _PenaltyNotice(remainingKm: short),
              const SizedBox(height: AppSpacing.space5),
            ],

            AppButton(
              label: AppStrings.runResumeCta,
              size: AppButtonSize.lg,
              onPressed: () => Navigator.of(context).pop(RunStopAction.resume),
            ),
            const SizedBox(height: AppSpacing.space3),

            _HoldToFinish(
              onFinish: () => Navigator.of(context).pop(RunStopAction.finish),
            ),
          ],
        ),
      ),
    );
  }

  /// 제재를 피하려면 얼마나 더 가야 하는가. 이미 넘었거나 목표가 없으면 `null`.
  double? get _shortfallKm {
    final target = targetDistanceMeters;
    if (target == null || target <= 0) return null;
    final safe = target * _safeRatio;
    final left = safe - metrics.distanceMeters;
    return left <= 0 ? null : left / 1000;
  }

  static String _elapsedText(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 제재 안내. **경고가 아니라 사실을 적는다** — 그만두는 것이 잘못은 아니다.
class _PenaltyNotice extends StatelessWidget {
  const _PenaltyNotice({required this.remainingKm});

  final double remainingKm;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.md,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.runFinishPenaltyNotice,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              AppStrings.runFinishRemaining(remainingKm),
              style: AppTypography.caption.copyWith(color: colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      children: [
        Text(
          value,
          style: AppTypography.metricMd.copyWith(color: colors.textPrimary),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// [AppMotion.holdToConfirm]만큼 길게 눌러야 끝난다.
///
/// ## 왜 한 번 눌러서 끝내지 않나
///
/// **되돌릴 방법이 없다.** 달리는 중에 손가락이 미끄러져 끝나면 그때까지의
/// 기록이 요약으로 넘어가 버린다. 누르고 있는 동안 테두리가 차오르는 것을
/// 보여줘서, 끝난다는 것을 손을 떼기 전에 알린다.
class _HoldToFinish extends StatefulWidget {
  const _HoldToFinish({required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<_HoldToFinish> createState() => _HoldToFinishState();
}

class _HoldToFinishState extends State<_HoldToFinish>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold =
      AnimationController(vsync: this, duration: AppMotion.holdToConfirm)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onFinish();
        });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTapDown: (_) => _hold.forward(),
      // 손을 떼면 되돌아간다. 끝까지 눌러야만 끝난다.
      onTapUp: (_) => _hold.reverse(),
      onTapCancel: () => _hold.reverse(),
      child: AnimatedBuilder(
        animation: _hold,
        builder: (context, child) => Container(
          height: AppSizes.touchDefault,
          decoration: BoxDecoration(
            borderRadius: AppRadius.md,
            border: Border.all(
              color: Color.lerp(
                colors.borderDefault,
                colors.error,
                // 차오르는 정도를 테두리 색으로도 알린다 — 굵기만으로는
                // 얼마나 남았는지 읽기 어렵다.
                Curves.easeOut.transform(_hold.value),
              )!,
              width: 1 + _hold.value * 2,
            ),
          ),
          child: child,
        ),
        child: Center(
          child: Text(
            AppStrings.runFinishHold,
            style: AppTypography.body.copyWith(color: colors.error),
          ),
        ),
      ),
    );
  }
}
