import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/empty_state_card.dart';
import 'package:runiverse/features/home/domain/greeting.dart';
import 'package:runiverse/features/home/presentation/home_hero.dart';

/// 홈 (S05).
///
/// 상단 히어로 + 하단 카드 스택 구조다. **히어로가 매칭 상태를 전담**하고
/// 4상태(기본 · 대기 · 확정 · 실패)로 갈린다. 그래서 홈에서는 글로벌 스티키
/// 배너를 띄우지 않는다 — 중복이다.
///
/// 지금은 매칭 기능이 없어 **기본 상태 하나뿐**이다.
///
/// 매칭 상태가 생기면 홈이 그것을 소유하지 않는다. 스티키 배너와 같은 provider를
/// 구독해야 하고, 탭을 옮겨도 살아있어야 한다(`docs/implementation-notes.md` §5-1).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space8,
          ),
          children: [
            HomeHero(
              greeting: _greetingText(GreetingRule.of(DateTime.now())),
              onMatch: () => _notReady(context, AppStrings.homeMatchComingSoon),
              onSolo: () => _notReady(context, AppStrings.homeSoloPending),
            ),
            const SizedBox(height: AppSpacing.space7),

            _SectionLabel(AppStrings.homeSectionCompetition),
            const SizedBox(height: AppSpacing.space3),
            const EmptyStateCard(
              icon: LucideIcons.trophy,
              message: AppStrings.homeEmptyCompetition,
            ),
            const SizedBox(height: AppSpacing.space6),

            _SectionLabel(AppStrings.homeSectionRecentRun),
            const SizedBox(height: AppSpacing.space3),
            const EmptyStateCard(
              icon: LucideIcons.footprints,
              message: AppStrings.homeEmptyRecentRun,
              hint: AppStrings.homeEmptyRecentRunHint,
            ),
          ],
        ),
      ),
      backgroundColor: colors.bgBase,
    );
  }

  /// 시간대 → 문구. 판정은 [GreetingRule]이 하고 여기서는 문구만 고른다.
  static String _greetingText(Greeting greeting) => switch (greeting) {
    Greeting.morning => AppStrings.homeGreetingMorning,
    Greeting.afternoon => AppStrings.homeGreetingAfternoon,
    Greeting.evening => AppStrings.homeGreetingEvening,
    Greeting.night => AppStrings.homeGreetingNight,
  };

  /// 아직 없는 화면으로 가는 버튼. 누르면 이유를 말한다.
  void _notReady(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 카드 묶음 위에 붙는 라벨. 무엇이 아니라 **무엇의 목록**인지 알려준다.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.caption.copyWith(
        color: context.appColors.textTertiary,
      ),
    );
  }
}
