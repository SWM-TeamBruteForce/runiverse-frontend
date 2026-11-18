import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/visibility_label.dart';

/// 기록카드 작성 3 — 공개범위 · 음악 (설계 6-4).
///
/// ## ⚠️ 경고가 공개범위에 매여 있다
///
/// 경로 경고는 `전체 공개`·`친구 공개`에서만 뜬다. 늘 띄우면 나만 보기로 바꾼
/// 사람에게 거짓말이 되고, 아예 안 띄우면 집이나 직장 근처가 드러나는 것을
/// 모르고 공개한다.
///
/// ## ⚠️ 뒤로는 묻지 않는다
///
/// 작성 2와 같다 — 버릴지 묻는 것은 **작성 1의 뒤로가기에서만** 한다
/// (설계 7절).
class CardPublishPage extends ConsumerWidget {
  const CardPublishPage({this.cardId, super.key});

  /// 수정 중인 카드 번호. `null`이면 새 카드다.
  final int? cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final draft = ref.watch(cardDraftProvider(cardId));
    final controller = ref.read(cardDraftProvider(cardId).notifier);

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          AppStrings.recordCardPublishTitle,
          style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            // ⚠️ **아직 아무것도 만들지 않는다.** 자르기·썸네일·저장이 다음
            // Task다. 이 묶음은 저장이 붙은 뒤에야 PR로 나간다.
            onPressed: draft.canProceed ? () {} : null,
            child: Text(AppStrings.recordCardPublishSave),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space2,
            AppSpacing.space4,
            AppSpacing.space8,
          ),
          children: [
            Text(
              AppStrings.recordCardPublishVisibilitySection,
              style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.space2),
            for (final visibility in RecordCardVisibility.values) ...[
              _VisibilityTile(
                visibility: visibility,
                selected: visibility == draft.visibility,
                onTap: () => controller.setVisibility(visibility),
              ),
              const SizedBox(height: AppSpacing.space2),
            ],
            if (recordCardVisibilityShowsRoute(draft.visibility)) ...[
              const SizedBox(height: AppSpacing.space1),
              _RouteWarning(),
            ],
            const SizedBox(height: AppSpacing.space5),
            Divider(color: colors.bgSurface, height: 1),
            const SizedBox(height: AppSpacing.space5),
            _MusicToggle(
              enabled: draft.musicEnabled,
              onChanged: controller.setMusicEnabled,
            ),
          ],
        ),
      ),
    );
  }
}

/// 공개범위 한 줄. **이름과 "누구에게 보이는지"를 함께 둔다** — 이름만으로는
/// `친구 공개`와 `나만 보기`의 차이를 짐작해야 한다.
class _VisibilityTile extends StatelessWidget {
  const _VisibilityTile({
    required this.visibility,
    required this.selected,
    required this.onTap,
  });

  final RecordCardVisibility visibility;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Semantics(
      button: true,
      // ⚠️ **고른 것을 읽히게 한다.** 글자 라벨이 있어도 무엇이 켜졌는지는
      // 테두리 색뿐이라, 이것 없이는 스크린리더가 셋을 구별하지 못한다.
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.space4),
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: AppRadius.md,
            border: Border.all(
              color: selected ? colors.primary : colors.bgSurface,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? LucideIcons.circleDot : LucideIcons.circle,
                size: 20,
                color: selected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.space3),
              Text(
                recordCardVisibilityLabel(visibility),
                style: AppTypographyV2.body18.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Text(
                  recordCardVisibilityBody(visibility),
                  textAlign: TextAlign.right,
                  style: AppTypographyV2.body20.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 공개하면 경로가 보인다는 한 줄.
class _RouteWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.triangleAlert, size: 16, color: colors.warning),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: Text(
            AppStrings.recordCardPublishRouteWarning,
            style: AppTypographyV2.body20.copyWith(color: colors.warning),
          ),
        ),
      ],
    );
  }
}

/// AI 음악을 만들까. **기본은 켜짐**이고, 무엇을 얼마나 만드는지 아래에 둔다.
class _MusicToggle extends StatelessWidget {
  const _MusicToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.recordCardPublishMusicTitle,
                style: AppTypographyV2.body07.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            Switch(value: enabled, onChanged: onChanged),
          ],
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          AppStrings.recordCardPublishMusicBody,
          style: AppTypographyV2.body20.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}
