import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/stat_row.dart';
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
    final colors = context.appColorsV2;
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
    final colors = context.appColorsV2;

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
          style: AppTypographyV2.heading05.copyWith(color: colors.textStrong),
        ),
        const SizedBox(height: AppSpacing.space6),

        // ⚠️ **카드 밖이다.** 시안(`158:3796`)이 세 수치를 차트 카드에서 빼
        // 화면 맨 위에 둔다 — 카드를 안 봐도 이번 주가 어땠는지 읽힌다.
        StatRowV2(
          stats: [
            Stat(
              label: AppStrings.recordWeekDistance,
              value: AppStrings.recordSummaryDistanceText(
                data.weekSummary.totalKm,
              ),
            ),
            Stat(
              label: AppStrings.recordWeekTime,
              value: AppStrings.recordDurationText(
                data.weekSummary.totalDuration,
              ),
            ),
            Stat(
              label: AppStrings.recordWeekElevation,
              // ⚠️ 하나라도 모르면 `RecordSummary`가 통째로 `null`을 준다 —
              // 아는 것만 더하면 실제보다 작은 값이 확정값처럼 보인다.
              value: AppStrings.recordElevationText(
                data.weekSummary.elevationGainMeters,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),

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
                context.push(AppRoutes.recordDetailOf(record.runningRoomId)),
          ),
      ],
    );
  }
}

class _MonthEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

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
            style: AppTypographyV2.body07.copyWith(color: colors.textTertiary),
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
    final colors = context.appColorsV2;

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
              style: AppTypographyV2.body07.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
            AppButtonV2(
              label: AppStrings.recordRetry,
              variant: AppButtonV2Variant.secondary,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
