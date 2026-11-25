import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/record_card/presentation/activity_filter.dart';
import 'package:runiverse/features/record_card/presentation/record_card_calendar.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

/// 기록카드 탭.
///
/// 위에서부터 **유형 필터 → 월 달력**이다. 달력은 최신 달이 위고, 오므리면
/// 분기 보기로 작아진다.
///
/// ## ⚠️ 빈 상태와 "필터로 0장"은 다르다
///
/// 카드를 한 장도 안 쓴 사람에게만 안내를 띄운다. 필터를 걸어 0장이 된 사람에게
/// 띄우면 **필터 때문인 줄 모른다.** `RecordCardData.hasAnyCard`가 둘을 가른다.
///
/// ## ⚠️ 달력은 빈 상태에서도 남는다
///
/// 안내만 띄우고 달력을 치우면 이 탭이 무엇을 하는 곳인지 알 수 없다.
class RecordCardPage extends ConsumerWidget {
  const RecordCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final state = ref.watch(recordCardControllerProvider);
    final controller = ref.read(recordCardControllerProvider.notifier);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        // 다른 탭(기록)과 같은 머리: 왼쪽 정렬 heading05. iOS 기본(가운데 정렬)과
        // 스크롤될 때 바탕을 칠하는 것을 끈다.
        centerTitle: false,
        scrolledUnderElevation: 0,
        title: Text(
          AppStrings.recordCardTabTitle,
          style: AppTypographyV2.heading05.copyWith(color: colors.textStrong),
        ),
        actions: [
          // ⚠️ **라벨 없는 아이콘이라 읽을 말을 붙인다**(CLAUDE.md). 여기서는
          // `tooltip`이 그 일을 한다 — `Tooltip`이 `SemanticsProperties.tooltip`
          // 을 심어 스크린리더가 읽는다. 탭 바 아이콘이 `Semantics(label:)`을
          // 쓰는 이유는 그쪽에 툴팁이 없기 때문이다.
          //
          // 보기 전환은 다음 묶음이 이 머리에 더한다.
          IconButton(
            icon: const Icon(LucideIcons.pencil),
            tooltip: AppStrings.recordCardEmptyAction,
            onPressed: () => context.push(
              AppRoutes.recordCardNewOn(ref.read(recordCardClockProvider)()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (state) {
          RecordCardLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
          RecordCardError() => _Error(onRetry: controller.load),
          RecordCardData() => _Body(data: state, controller: controller),
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.controller});

  final RecordCardData data;
  final RecordCardController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: AppSpacing.space2),
      ActivityFilter(selected: data.filter, onChanged: controller.setFilter),
      const SizedBox(height: AppSpacing.space2),
      // ⚠️ 카드가 한 장도 없을 때만. 필터로 0장이 된 것은 여기 해당하지 않는다.
      if (!data.hasAnyCard) const _Empty(),
      Expanded(
        child: RecordCardCalendar(
          data: data,
          // ⚠️ **번호만 넘긴다.** 달력이 든 것은 칸을 그릴 만큼이고, 상세는
          // 경로·지표·파티원·음악까지 필요하다 — 8-1이 그것을 준다.
          onOpen: (card) => context.push(AppRoutes.recordCardDetailOf(card.id)),
          // ⚠️ **뛴 날만 불린다.** 안 뛴 날은 칸이 아예 눌리지 않는다
          // (`RecordCardCalendar`). 그래서 여기서 기록 유무를 또 보지 않는다.
          onEmptyDay: (day) => context.push(AppRoutes.recordCardNewOn(day)),
          onZoom: controller.setZoom,
          onLoadOlder: controller.loadOlder,
        ),
      ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space3,
        AppSpacing.space4,
        AppSpacing.space2,
      ),
      child: Column(
        children: [
          Text(
            AppStrings.recordCardEmptyTitle,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body07.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space3),
          // ⚠️ 안내만 두면 **어디서 쓰는지 알 수 없다.** 탭 머리의 아이콘은
          // 라벨이 없어, 카드가 한 장도 없는 사람에게는 이 버튼이 유일하게
          // 읽히는 입구다.
          _NewCardButton(),
        ],
      ),
    );
  }
}

class _NewCardButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => AppButtonV2(
    label: AppStrings.recordCardEmptyAction,
    expand: false,
    onPressed: () => context.push(
      AppRoutes.recordCardNewOn(ref.read(recordCardClockProvider)()),
    ),
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
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
              AppStrings.recordCardError,
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
