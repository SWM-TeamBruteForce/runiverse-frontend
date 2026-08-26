import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 출발 준비 — **GPS 첫 신호를 기다린다.**
///
/// ## 왜 이 화면이 있나
///
/// GPS는 앱을 켜자마자 위치를 알지 못한다. 실내에서는 위성을 잡는 데 수십 초가
/// 걸리고, 그 전에 출발하면 **초반 거리가 통째로 빠진다.** 사용자는 자기가 뛴
/// 만큼 기록이 안 나온 이유를 알 수 없다.
///
/// 그래서 신호를 받기 전에는 시작 버튼을 잠그고, **잠긴 이유를 글로 보여준다** —
/// 색만으로 알리지 않는다(정본 C9).
class RunPreparePage extends ConsumerStatefulWidget {
  const RunPreparePage({super.key});

  @override
  ConsumerState<RunPreparePage> createState() => _RunPreparePageState();
}

class _RunPreparePageState extends ConsumerState<RunPreparePage> {
  /// 위치를 쓸 수 있는가. `null`이면 아직 묻는 중이다.
  LocationAccess? _access;

  @override
  void initState() {
    super.initState();
    // ⚠️ `initState`에서 provider를 고치면 빌드 도중 상태가 바뀌어 죽는다.
    // 첫 프레임 뒤로 미룬다(`implementation-notes.md` §10-1).
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    final access = await ref
        .read(runSessionControllerProvider.notifier)
        .prepare();
    if (mounted) setState(() => _access = access);
  }

  void _start() {
    ref.read(runSessionControllerProvider.notifier).start();
    // `pushReplacement` — 준비 화면으로 되돌아올 자리를 남기지 않는다.
    // 달리는 중에 뒤로 가면 준비 화면이 나오는 것은 말이 안 된다.
    context.pushReplacement(AppRoutes.runSession);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = ref.watch(runSessionControllerProvider);
    final hasFix = state is RunPreparing && state.hasFix;
    final access = _access;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => _leave(context),
                tooltip: AppStrings.authBack,
                constraints: const BoxConstraints(
                  minWidth: AppSizes.touchDefault,
                  minHeight: AppSizes.touchDefault,
                ),
                icon: Icon(
                  LucideIcons.arrowLeft,
                  size: AppSpacing.space6,
                  color: colors.textSecondary,
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space5,
                ),
                child: access != null && access != LocationAccess.granted
                    ? _Blocked(access: access, onOpenSettings: _openSettings)
                    : _Waiting(hasFix: hasFix),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              child: AppButton(
                label: AppStrings.runStartCta,
                size: AppButtonSize.lg,
                // 신호를 받기 전에는 잠긴다. 이 잠금이 이 화면의 존재 이유다.
                onPressed: hasFix ? _start : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 준비를 그만두고 나간다. **구독을 반드시 끊는다** —
  /// 안 끊으면 홈으로 돌아가서도 GPS가 계속 돌아 배터리를 먹는다.
  void _leave(BuildContext context) {
    ref.read(runSessionControllerProvider.notifier).reset();
    context.pop();
  }

  Future<void> _openSettings() async {
    await ref.read(locationRepositoryProvider).openSettings();
  }
}

/// 신호를 기다리는 동안.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.hasFix});

  final bool hasFix;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 신호를 받으면 아이콘이 바뀐다. **색만 바꾸지 않는다.**
        AnimatedSwitcher(
          duration: AppMotion.base,
          child: Icon(
            hasFix ? LucideIcons.locateFixed : LucideIcons.locate,
            key: ValueKey(hasFix),
            size: AppSpacing.space10,
            color: hasFix ? colors.success : colors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.space5),

        Text(
          hasFix ? AppStrings.runFixReady : AppStrings.runWaitingFix,
          style: AppTypography.h2.copyWith(color: colors.textPrimary),
        ),
        if (!hasFix) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            AppStrings.runWaitingFixWhy,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// 위치를 쓸 수 없다. **왜 막혔는지와 어디로 가야 하는지**를 함께 말한다.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.access, required this.onOpenSettings});

  final LocationAccess access;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          LucideIcons.mapPinOff,
          size: AppSpacing.space10,
          color: colors.textTertiary,
        ),
        const SizedBox(height: AppSpacing.space5),
        Text(
          access == LocationAccess.serviceDisabled
              ? AppStrings.runServiceDisabled
              : AppStrings.runPermissionTitle,
          textAlign: TextAlign.center,
          style: AppTypography.h3.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          AppStrings.runPermissionBody,
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space5),
        AppButton(
          label: AppStrings.runPermissionOpenSettings,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.md,
          expand: false,
          onPressed: onOpenSettings,
        ),
      ],
    );
  }
}
