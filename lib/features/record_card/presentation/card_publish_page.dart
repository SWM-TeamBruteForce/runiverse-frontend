import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_save_provider.dart';
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
  const CardPublishPage({this.cardId, this.onSaved, super.key});

  /// 수정 중인 카드 번호. `null`이면 새 카드다.
  final int? cardId;

  /// 만든 카드를 어디로 보낼까. **라우트를 아는 쪽이 정한다**(다음 Task) —
  /// 여기서 `context.push`를 부르면 이 화면이 라우터에 매여 테스트가 무거워진다.
  final void Function(RecordCard card)? onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final draft = ref.watch(cardDraftProvider(cardId));
    final controller = ref.read(cardDraftProvider(cardId).notifier);
    final save = ref.watch(cardSaveProvider(cardId));
    final saving = save is CardSaveSaving;

    return PopScope(
      // ⚠️ **머리의 뒤로만 막으면 안 된다.** 안드로이드 하드웨어·제스처 뒤로와
      // iOS 스와이프는 그대로 빠져나가고, 저장이 끝나면 **걷힌 화면**의
      // context로 라우터를 불러 죽는다. 만들어진 카드를 아무도 받지 못한 채
      // 초안만 비워진다. 두 뒤로가 같은 문을 쓰게 한다.
      canPop: !saving,
      child: _body(context, ref, colors, draft, controller, saving: saving),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AppColorsV2 colors,
    CardDraft draft,
    CardDraftController controller, {
    required bool saving,
  }) {
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          // 도는 동안 나가면 만들어진 카드를 아무도 안 받는다.
          onPressed: saving ? null : () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          AppStrings.recordCardPublishTitle,
          style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          if (saving)
            // ⚠️ **버튼을 진행 표시로 바꾼다.** `onPressed: null`만 두면
            // 눌리지 않는 이유가 안 보여, 사용자가 계속 누른다.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.space4),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: draft.canProceed ? () => _save(context, ref) : null,
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
              onChanged: saving ? null : controller.setMusicEnabled,
            ),
          ],
        ),
      ),
    );
  }

  /// 저장하고, 만들어졌으면 [onSaved]에 넘긴다.
  ///
  /// ## ⚠️ 실패하면 화면에 머문다
  ///
  /// 초안은 그대로 남아 있다(`CardSaveController.save`). 나가 버리면 쓴 글을
  /// 다시 쓸 길이 없다 — 초안은 영속화하지 않는다.
  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final card = await ref.read(cardSaveProvider(cardId).notifier).save();

    // ⚠️ **기다리는 동안 화면이 걷혔을 수 있다.** 죽은 context로 라우터를
    // 부르면 "deactivated widget" 으로 죽는다.
    if (!context.mounted) return;

    if (card == null) {
      // ⚠️ **`null`이 전부 실패는 아니다.** 저장이 이미 돌고 있어 두 번째
      // 호출이 그냥 돌아온 경우에도 `null`이다 — 그때 실패를 띄우면 저장은
      // 됐는데 "저장하지 못했어요"를 본 직후 상세로 떨어진다. 상태가
      // 실패라고 말할 때만 말한다.
      if (ref.read(cardSaveProvider(cardId)) is CardSaveFailed) {
        messenger.showSnackBar(
          const SnackBar(content: Text(AppStrings.recordCardPublishSaveFailed)),
        );
      }
      return;
    }
    onSaved?.call(card);
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

  /// `null`이면 저장이 도는 중이다 — 바꿔도 이미 보낸 값에 반영되지 않는다.
  final ValueChanged<bool>? onChanged;

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
