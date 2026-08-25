import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
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
}) {
  return showModalBottomSheet<RunStopAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.appColors.bgScrim,
    // 실수로 닫히면 안 된다. 멈춘 상태가 화면에 드러나야 한다.
    isDismissible: false,
    builder: (context) => _StopSheet(metrics: metrics),
  );
}

class _StopSheet extends StatelessWidget {
  const _StopSheet({required this.metrics});

  final RunMetrics metrics;

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
            const SizedBox(height: AppSpacing.space6),

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

  static String _elapsedText(Duration elapsed) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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

/// 2초 길게 눌러야 끝난다.
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
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
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
