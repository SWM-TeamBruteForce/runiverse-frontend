import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record/presentation/run_result_view.dart';

/// 기록 탭에서 지난 기록 하나를 연다. **S16과 같은 화면**이다.
///
/// 종료 직후(S15 → S16)는 이미 손에 든 [RunDetail]을 그대로 넘기지만,
/// 여기서는 번호밖에 없으므로 먼저 읽어 와야 한다. 그 차이만 이 페이지가
/// 흡수하고, 그림은 [RunResultView] 하나가 그린다.
///
/// ## ⚠️ 지금은 목이다
///
/// 20번(`GET /running-records/{id}`)이 `개발전`이라
/// `FakeRunRecordRepository`가 구간을 만들어 준다 — 케이던스는 지어낸 값이라
/// 차트에 `예시` 꼬리표가 붙는다. 서버가 열리면 provider 한 줄만 바꾼다.
class RecordDetailPage extends ConsumerWidget {
  const RecordDetailPage({required this.recordId, super.key});

  final int recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(runDetailProvider(recordId));

    return detail.when(
      data: (value) => RunResultView(detail: value),
      loading: () => const _Frame(child: CircularProgressIndicator()),
      error: (_, _) => _Frame(
        child: _Failed(
          onRetry: () => ref.invalidate(runDetailProvider(recordId)),
        ),
      ),
    );
  }
}

/// 불러오는 동안에도 나가는 길이 있어야 한다.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: AppStrings.runResultBack,
          icon: Icon(LucideIcons.chevronLeft, color: colors.textPrimary),
        ),
        title: Text(
          AppStrings.runResultTitle,
          style: AppTypography.h3.copyWith(color: colors.textPrimary),
        ),
      ),
      body: Center(child: child),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: AppSpacing.space7,
            color: colors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            AppStrings.recordError,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space4),
          AppButton(
            label: AppStrings.recordRetry,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.md,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
