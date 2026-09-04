import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/record/presentation/record_calendar.dart';
import 'package:runiverse/features/record/presentation/record_day_list.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';
import 'package:runiverse/features/record/presentation/record_week_chart.dart';

/// 기록 탭 (S21).
///
/// 위에서부터 **주간 바차트 → 월 캘린더 → 고른 날의 기록**이다.
///
/// ## ⚠️ 잔디도, 색 모자이크 캘린더도 아니다
///
/// 월 전체를 칠하면 러닝하지 않은 날이 결손으로 읽혀 잔디의 죄책감 문제를
/// 답습한다(디자인 시스템 v1.1 §5-5). **러닝한 날에만 점을 찍는다.**
///
/// ## ⚠️ 색이 아직 단색이다
///
/// 정본은 막대와 점을 "그날 획득한 러닝 컬러"로 칠하라고 적었지만, 그 색을
/// 만드는 규칙이 없고(`features/color/`가 비어 있다) 목록 API도 색을 주지
/// 않는다. 지금은 `primary` 하나로 그린다.
///
/// ## ⚠️ 데이터가 목이다
///
/// 19번(`GET /users/me/running-records`)이 `개발전`이라 붙일 서버가 없다.
/// `runRecordRepositoryProvider`가 `FakeRunRecordRepository`를 준다.
class RecordPage extends ConsumerWidget {
  const RecordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final state = ref.watch(recordControllerProvider);
    final controller = ref.read(recordControllerProvider.notifier);

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: switch (state) {
          RecordLoading() => const Center(child: CircularProgressIndicator()),
          RecordError() => _Error(onRetry: controller.load),
          RecordData() => _Loaded(data: state, controller: controller),
        },
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.data, required this.controller});

  final RecordData data;
  final RecordController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space8,
      ),
      children: [
        Text(
          AppStrings.tabRecord,
          style: AppTypography.h1.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.space4),

        RecordWeekChart(data: data, onSelect: controller.select),
        const SizedBox(height: AppSpacing.space4),

        RecordCalendar(
          data: data,
          onSelect: controller.select,
          onMoveMonth: controller.moveMonth,
        ),
        const SizedBox(height: AppSpacing.space5),

        // 달에 기록이 하나도 없으면 날짜별 목록 대신 한 줄로 알린다.
        if (data.monthSummary.isEmpty)
          _MonthEmpty()
        else
          RecordDayList(
            day: data.selectedDay,
            records: data.selectedRecords,
            // 러닝을 막 끝냈을 때와 **같은 화면**(S16)을 연다.
            onOpen: (record) =>
                context.push(AppRoutes.recordDetailOf(record.id)),
          ),
      ],
    );
  }
}

class _MonthEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space6),
      child: Column(
        children: [
          Icon(
            LucideIcons.footprints,
            size: AppSpacing.space7,
            color: colors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            AppStrings.recordMonthEmpty,
            style: AppTypography.body.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Padding(
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
      ),
    );
  }
}
