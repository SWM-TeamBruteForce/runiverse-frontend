import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/music_inputs.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';
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
/// ## ⚠️ 수정에서는 음악을 잃을 수 있다고 미리 알린다 (설계 6-6)
///
/// 저장을 누른 **뒤에** 말하면 이미 버려진 뒤다. 다이얼로그로 한 번 더 받지
/// 않는 이유는, 되돌릴 수 없는 일이 아니고(음악은 다시 만들어진다) 고칠
/// 때마다 확인을 받으면 공개범위 한 칸 바꾸는 일도 두 번 눌러야 한다.
///
/// ## ⚠️ 뒤로는 묻지 않는다
///
/// 작성 2와 같다 — 버릴지 묻는 것은 **작성 1의 뒤로가기에서만** 한다
/// (설계 7절).
class CardPublishPage extends ConsumerWidget {
  const CardPublishPage({this.cardId, this.onSaved, super.key});

  /// 수정 중인 카드 번호. `null`이면 새 카드다.
  final String? cardId;

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
              _Warning(AppStrings.recordCardPublishRouteWarning),
            ],
            // ⚠️ **수정에서만 선다.** 새 카드에는 아직 잃을 음악이 없다.
            if (_musicWarning(ref, draft) case final warning?) ...[
              const SizedBox(height: AppSpacing.space1),
              _Warning(warning),
            ],
            // ⚠️ **수정에서는 숨긴다.** 고치러 온 사람에게 "만듭니다"는 낡은
            // 말이다 — 음악은 이미 있거나 만들어지는 중이고, 그 카드에
            // 무슨 일이 생기는지는 위의 `_musicWarning`이 말한다.
            if (draft.editing == null) ...[
              const SizedBox(height: AppSpacing.space5),
              Divider(color: colors.bgSurface, height: 1),
              const SizedBox(height: AppSpacing.space5),
              const _MusicNote(),
            ],
          ],
        ),
      ),
    );
  }

  /// 저장하면 음악이 어떻게 되는지 알리는 한 줄. 없으면 `null`이다.
  ///
  /// | 음악 | AI 입력이 바뀜 | 줄 |
  /// |---|---|---|
  /// | 만드는 중 | 상관없다 | 만들던 것이 버려진다 |
  /// | 다 됐다 | 바뀜 | 처음부터 다시 만든다 |
  /// | 다 됐다 | 공개범위만 | **없다** — 음악은 그대로다 |
  /// | 없다 · 실패 | 상관없다 | **없다** — 잃을 음악이 없다 |
  ///
  /// ⚠️ **만드는 중에는 "공개범위만 바꾸면 그대로"가 거짓이다.** 백엔드가
  /// "생성 중 수정·삭제는 활성 요청을 무효화한다"고 적었다(설계 3절).
  String? _musicWarning(WidgetRef ref, CardDraft draft) {
    final editing = draft.editing;
    if (editing == null) return null;

    // ⚠️ 상태를 못 읽었거나 아직 받는 중이면 **아무 말도 하지 않는다.** 모르는
    // 것을 경고로 지어내지 않는다.
    if (ref.watch(cardMusicProvider(editing.id)) case CardMusicData(
      :final generation,
    )) {
      if (generation.isWorking) return AppStrings.recordCardMusicWorkingEdit;
      if (generation.status == MusicStatus.succeeded &&
          MusicInputs.ofDraft(draft) != MusicInputs.ofCard(editing)) {
        return AppStrings.recordCardMusicRegenerate;
      }
    }
    return null;
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

/// 경고 한 줄. **경로와 음악이 같은 모양을 쓴다** — 같은 성격의 말이 두
/// 모양이면 하나가 덜 중요해 보인다.
class _Warning extends StatelessWidget {
  const _Warning(this.message);

  final String message;

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
            message,
            style: AppTypographyV2.body20.copyWith(color: colors.warning),
          ),
        ),
      ],
    );
  }
}

/// 저장하면 음악이 만들어진다고 **알리는 줄.** 고를 것이 없다.
///
/// ## ⚠️ 스위치가 아니다
///
/// 서버는 카드를 확정할 때 **늘** 기본곡과 사진별 곡 생성을 요청한다(연동
/// 가이드 3절: "현재 API는 음악 생성을 항상 요청하므로"). 끌 수 있는 것처럼
/// 보여 주면 **끄고 저장한 사람이 음악이 만들어지는 것을 보게 된다.**
///
/// 그래도 글은 남긴다 — 지우면 저장하는 사람이 **모르는 사이에** AI가 회고와
/// 사진을 읽어 곡을 만든다. 고를 수 없는 것과 알리지 않는 것은 다르다.
class _MusicNote extends StatelessWidget {
  const _MusicNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.recordCardPublishMusicTitle,
          style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
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
