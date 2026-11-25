import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/card_face.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_pan.dart';

/// 작성 화면의 **사진 한 장** (설계 6-3).
///
/// 미리보기 · 캡션 · 대표 지정 · 지우기가 한 묶음이다. 어느 장을 보고 있는지,
/// 사진을 고르는 중인지 같은 **화면 상태는 들지 않는다** — 부르는 쪽이 든다.
///
/// ## ⚠️ 캡션 컨트롤러를 **장마다** 든다
///
/// 바깥 `PageView`는 이웃 장을 **함께 만들어** 둔다. 컨트롤러 하나를 돌려
/// 쓰면 한 장에 친 글자가 옆 장 칸에도 떠 있고, 고치면 엉뚱한 장에 붙는다.
///
/// ## ⚠️ 밀기와 장 넘기기는 서로 먹는다
///
/// [PickedPhoto] 위에서는 가로 끌기를 사진이 가져가 장이 넘어가지 않는다.
/// 넘기는 길은 부르는 쪽이 **점**으로 따로 둔다.
class CardPhotoSlide extends StatefulWidget {
  const CardPhotoSlide({
    required this.photo,
    required this.index,
    required this.total,
    required this.isCover,
    required this.onAlign,
    required this.onCaption,
    required this.onMakeCover,
    required this.onRemove,
    super.key,
  });

  final CardPhotoDraft photo;

  /// 0부터 센다. 이름표(`3장 중 2번째`)에 쓴다.
  final int index;

  /// 사진 수. **1이면 대표 이야기를 꺼내지 않는다** — 고를 것이 없다.
  final int total;

  /// 이 장이 대표인가.
  final bool isCover;

  /// 민 위치가 바뀌었다. **준 축만 바뀐다.**
  final void Function({double? alignX, double? alignY}) onAlign;

  final ValueChanged<String> onCaption;
  final VoidCallback onMakeCover;
  final VoidCallback onRemove;

  /// 9:16을 폭에 꽉 채우면 화면보다 높아져 캡션이 한 화면에 안 들어온다 —
  /// 작성 화면의 경로 미리보기와 같은 값이다.
  static const previewHeight = 320.0;

  @override
  State<CardPhotoSlide> createState() => _CardPhotoSlideState();
}

class _CardPhotoSlideState extends State<CardPhotoSlide> {
  late final _caption = TextEditingController(text: widget.photo.caption);

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final photo = widget.photo;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space2,
        AppSpacing.space4,
        AppSpacing.space8,
      ),
      children: [
        SizedBox(
          height: CardPhotoSlide.previewHeight,
          child: Center(
            child: AspectRatio(
              aspectRatio: CardPhotoDraft.aspectRatio,
              child: ClipRRect(
                borderRadius: AppRadius.md,
                child: Semantics(
                  label: AppStrings.recordCardPhotoSemantics(
                    widget.index + 1,
                    widget.total,
                  ),
                  child: switch (photo) {
                    // 이미 올린 사진은 **밀 수 없다** — 9:16으로 잘려 나갔으므로
                    // 틀 안에서 옮길 데가 없다.
                    final SavedPhoto saved => Image(
                      image: cardThumbnail(context, saved.url),
                      fit: BoxFit.cover,
                      // ⚠️ **서명이 만료되면 못 받는다.** 고치는 중에 화면이
                      // 터지면 쓰던 것을 통째로 잃는다 — 못 받은 자리만 말하고
                      // 나머지는 계속 고칠 수 있게 둔다.
                      errorBuilder: (context, _, _) => const UnreadablePhoto(),
                    ),
                    final PickedPhoto picked => CardPhotoPan(
                      photo: picked,
                      onAlign: widget.onAlign,
                    ),
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        // ⚠️ **미는 사진일 때만 말한다.** 이미 올린 사진에 "밀어 보세요"라고
        // 하면 거짓말이다.
        if (photo is PickedPhoto)
          Text(
            AppStrings.recordCardPhotoPanHint,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body20.copyWith(color: colors.textSecondary),
          ),
        const SizedBox(height: AppSpacing.space5),
        AppInputV2(
          controller: _caption,
          hint: AppStrings.recordCardPhotoCaptionHint,
          helper: AppStrings.recordCardPhotoCaptionNote,
          counter: AppStrings.recordCardPhotoCaptionCounter(
            photo.caption.characters.length,
            CardPhotoDraft.captionMaxLength,
          ),
          maxLines: 3,
          // 칸에서 막고 초안에서 한 번 더 자른다.
          inputFormatters: [
            LengthLimitingTextInputFormatter(CardPhotoDraft.captionMaxLength),
          ],
          onChanged: widget.onCaption,
        ),
        const SizedBox(height: AppSpacing.space4),
        // ⚠️ **한 장뿐이면 아무 말도 하지 않는다.** 고를 것이 없는데 "대표
        // 사진"이라고 적으면 무엇과 견준 말인지 알 수 없다.
        if (widget.total > 1)
          Center(
            // ⚠️ **이미 대표인 장에는 버튼을 세우지 않는다.** 눌러도 아무 일도
            // 없는 버튼은 고장으로 읽힌다(묶음 5의 음악 줄).
            child: widget.isCover
                ? Text(
                    AppStrings.recordCardPhotoCover,
                    style: AppTypographyV2.body18.copyWith(
                      color: colors.textSecondary,
                    ),
                  )
                : TextButton(
                    onPressed: widget.onMakeCover,
                    child: Text(
                      AppStrings.recordCardPhotoMakeCover,
                      style: AppTypographyV2.body18.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
          ),
        Center(
          child: TextButton(
            onPressed: widget.onRemove,
            child: Text(
              AppStrings.recordCardPhotoRemove,
              style: AppTypographyV2.body18.copyWith(color: colors.error),
            ),
          ),
        ),
      ],
    );
  }
}

/// **사진 한 장 더 넣는 장.** 사진 장들 뒤에 선다.
///
/// ## ⚠️ [first]일 때만 "안 넣어도 괜찮다"고 말한다
///
/// 사진은 선택이라 그 말이 **권유가 아니라 괜찮다는 말**이어야 한다(설계 6-3).
/// 이미 한 장 넣은 사람에게 되풀이하면 방금 한 일을 되묻는 꼴이다.
class CardAddPhotoSlide extends StatelessWidget {
  const CardAddPhotoSlide({
    required this.first,
    required this.onPick,
    super.key,
  });

  /// 사진이 한 장도 없나.
  final bool first;

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (first) ...[
              Text(
                AppStrings.recordCardPhotoEmpty,
                textAlign: TextAlign.center,
                style: AppTypographyV2.body18.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
            ],
            // ⚠️ **아이콘뿐이라 `Tooltip`으로 이름을 준다.**
            IconButton(
              tooltip: AppStrings.recordCardPhotoAdd,
              onPressed: onPick,
              iconSize: 40,
              icon: Icon(LucideIcons.plus, color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
