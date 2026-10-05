import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 러닝 중 하단 조작 — 시안 `158:3493` · `158:3545`.
///
/// 왼쪽이 종료(■), 오른쪽이 일시정지(❚❚)다.
///
/// ## ⚠️ 종료는 길게 눌러야 한다
///
/// 시안은 그냥 버튼 둘인데, **달리는 중에 손가락이 스치면 기록이 끝난다.**
/// `docs/implementation-notes.md` §4가 "한 번 누르면 끝나는 것은
/// hold-to-end(2초)나 2단계 확인"을 요구한다. 모양은 시안을 따르고 누르는
/// 방식만 길게 누르기로 둔다.
///
/// 누르고 있는 동안 버튼이 차오른다. 얼마나 더 눌러야 하는지 보이지 않으면
/// **눌리지 않는 버튼**으로 읽힌다.
///
/// ## ⚠️ 패널티 안내를 잃지 않는다
///
/// 예전에는 `중지` → 시트 안에 이 안내가 있었다. 시트를 없애면서 **누르고
/// 있는 동안** 띄운다 — 그만둘지 망설이는 바로 그 순간이고, 달리는 내내
/// 띄우면 읽지 않게 된다.
class RunControls extends StatefulWidget {
  const RunControls({
    required this.paused,
    required this.enabled,
    required this.onPauseToggle,
    required this.onFinish,
    this.penaltyRemainingKm,
    super.key,
  });

  /// 지금 멈춰 있는가. 오른쪽 버튼의 글리프를 가른다.
  final bool paused;

  /// 누를 수 있는가. 준비 중이거나 이미 끝났으면 `false`다.
  final bool enabled;

  final VoidCallback onPauseToggle;

  /// 길게 누르기가 끝까지 찼을 때.
  final VoidCallback onFinish;

  /// 목표까지 남은 거리. **`null`이면 안내하지 않는다** — 솔로이거나 이미
  /// 목표를 채운 경우다.
  final double? penaltyRemainingKm;

  @override
  State<RunControls> createState() => _RunControlsState();
}

class _RunControlsState extends State<RunControls>
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

  bool get _holding => _hold.value > 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final remaining = widget.penaltyRemainingKm;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space5),
      child: Column(
        children: [
          // 누르고 있는 동안에만 뜬다.
          AnimatedBuilder(
            animation: _hold,
            builder: (context, _) {
              if (!_holding || remaining == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space3),
                child: Column(
                  children: [
                    Text(
                      AppStrings.runFinishPenaltyNotice,
                      textAlign: TextAlign.center,
                      style: AppTypographyV2.body15.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space1),
                    Text(
                      AppStrings.runFinishRemaining(remaining),
                      textAlign: TextAlign.center,
                      style: AppTypographyV2.body15.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          Row(
            children: [
              Expanded(
                child: _FinishButton(hold: _hold, controls: widget),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: _PauseButton(
                  paused: widget.paused,
                  onTap: widget.enabled ? widget.onPauseToggle : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 왼쪽 — 길게 눌러 끝낸다. 누르는 동안 브랜드색이 차오른다.
class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.hold, required this.controls});

  final AnimationController hold;
  final RunControls controls;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final enabled = controls.enabled;

    return Semantics(
      button: true,
      enabled: enabled,
      label: AppStrings.runFinishHold,
      child: GestureDetector(
        onTapDown: enabled ? (_) => hold.forward() : null,
        // 손을 떼면 되돌아간다. **그 자리에서 멈추면** 다음에 조금만 눌러도
        // 끝나 버린다.
        onTapUp: (_) => hold.reverse(),
        onTapCancel: hold.reverse,
        child: AnimatedBuilder(
          animation: hold,
          builder: (context, _) => Container(
            height: AppSizes.touchRunning,
            decoration: BoxDecoration(
              color: enabled ? colors.primary : colors.bgSurface,
              borderRadius: AppRadius.lg,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 차오르는 띠. 왼쪽에서 오른쪽으로 민다.
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: hold.value,
                    child: ColoredBox(
                      color: colors.bgInverse,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                // ⚠️ **`AppIcons.stop` 을 쓰지 않는다.** 시안 세트의 그 글리프는
                // `assets/icons/stop.svg` 를 열어 보면 **막대 둘**이다 — 오른쪽
                // 일시정지와 똑같이 보여 두 버튼을 구분할 수 없었다.
                // 기기에서 나란히 놓고서야 드러났다.
                //
                // 네모는 아이콘이라기보다 도형이라 직접 그린다. 디자이너가
                // 사각형 글리프를 주면 갈아끼운다.
                Container(
                  width: AppSpacing.space4,
                  height: AppSpacing.space4,
                  decoration: BoxDecoration(
                    color: enabled ? colors.textOnPrimary : colors.textDisabled,
                    // ⚠️ **모서리를 깎지 않는다.** 16 짜리 상자에
                    // `AppRadius.sm`(8) 을 주면 완전히 둥글어져 **동그라미가
                    // 된다** — 기기에서 보고 알았다. 이 크기에 맞는 반경
                    // 토큰이 없어 각진 네모로 둔다.
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 오른쪽 — 멈추고 다시 간다. **길게 누르지 않는다** — 되돌릴 수 있는 것이다.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.paused, required this.onTap});

  final bool paused;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: paused ? AppStrings.runResumeCta : AppStrings.runPauseCta,
      child: Material(
        color: colors.bgSurface,
        borderRadius: AppRadius.lg,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.lg,
          child: SizedBox(
            height: AppSizes.touchRunning,
            child: Center(
              // ⚠️ 시안 아이콘 33개에 재생·일시정지가 없다. 디자이너 것이
              // 오면 갈아끼운다 — 휠 시트의 휴지통(#138)과 같은 상황이다.
              child: Icon(
                paused ? LucideIcons.play : LucideIcons.pause,
                size: AppSpacing.space5,
                color: onTap == null ? colors.textDisabled : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
