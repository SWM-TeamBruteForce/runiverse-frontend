import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_pan.dart';
import 'package:runiverse/features/record_card/presentation/record_card_cell.dart';

/// 기록카드 작성 2 — 사진 (설계 6-3).
///
/// ## ⚠️ 사진은 선택이다
///
/// 한 장도 없이 `다음`을 누를 수 있다. 그래서 빈 상태가 **권유가 아니라
/// 괜찮다는 말**이다 — "추가해 보세요"로 쓰면 선택인 것이 숙제로 읽힌다.
///
/// ## ⚠️ 한 장씩 고르고, 자르지 않는다
///
/// `+`로 한 장씩 고른다 — 여러 장을 한꺼번에 고른 뒤 크롭을 다섯 번 연달아
/// 하게 만들지 않는다(설계 6-3). 고른 것은 **자르지 않고** 원본과 민 위치만
/// 초안에 담았다가 저장할 때 한 번에 자른다(프로필 커버와 같은 순서). 그래야
/// 작성 3까지 갔다 돌아와도 위치를 다시 고칠 수 있다.
///
/// ## ⚠️ 뒤로는 묻지 않는다
///
/// 버릴지 묻는 것은 **작성 1의 뒤로가기에서만** 한다(설계 7절). 여기서 또
/// 물으면 사진을 보러 들어왔다 나가는 사람이 화면마다 막힌다. 초안은 그대로
/// 남고, 돌아간 작성 1이 그 문을 지킨다.
class CardPhotoPage extends ConsumerStatefulWidget {
  const CardPhotoPage({this.cardId, this.card, super.key});

  /// 수정 중인 카드 번호. `null`이면 새 카드다.
  final int? cardId;

  /// 고치는 카드. **다음 화면으로 들고 가야 한다** — 공개범위 라우트가
  /// `extra`로 받아야 초안을 어느 번호로 가를지 안다.
  final RecordCard? card;

  @override
  ConsumerState<CardPhotoPage> createState() => _CardPhotoPageState();
}

class _CardPhotoPageState extends ConsumerState<CardPhotoPage> {
  final _pager = PageController();

  /// ⚠️ **장마다 새로 만들지 않는다.** 하나를 두고 `text`를 갈아 끼운다 —
  /// 장마다 만들면 2번째 장에 1번째 캡션이 남고, 고치면 엉뚱한 장에 붙는다.
  final _caption = TextEditingController();

  /// 지금 보고 있는 장. **사진 수가 줄면 함께 당겨진다.**
  var _page = 0;

  /// 고르기가 돌고 있나. 도는 동안 또 누르면 앨범이 두 번 열린다.
  var _picking = false;

  @override
  void initState() {
    super.initState();
    _caption.text = _captionAt(0);
  }

  @override
  void dispose() {
    _pager.dispose();
    _caption.dispose();
    super.dispose();
  }

  CardDraftController get _draft =>
      ref.read(cardDraftProvider(widget.cardId).notifier);

  List<CardPhotoDraft> get _photos =>
      ref.read(cardDraftProvider(widget.cardId)).photos;

  String _captionAt(int index) {
    final photos = _photos;
    return index >= 0 && index < photos.length ? photos[index].caption : '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final draft = ref.watch(cardDraftProvider(widget.cardId));

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          // 묻지 않는다. 초안은 그대로 남고 작성 1이 그 문을 지킨다.
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          AppStrings.recordCardPhotoTitle(
            draft.photos.length,
            CardDraft.maxPhotos,
          ),
          style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: draft.canProceed
                ? () => widget.card != null
                      ? context.push(
                          AppRoutes.recordCardEditPublishOf(widget.card!.id),
                          extra: widget.card,
                        )
                      : context.push(AppRoutes.recordCardNewPublish)
                : null,
            child: Text(AppStrings.recordCardComposeNext),
          ),
        ],
      ),
      body: SafeArea(
        child: draft.photos.isEmpty
            ? _empty(colors)
            : _filled(colors, draft.photos),
      ),
    );
  }

  /// 사진 없음. **괜찮다고 말하고 `+` 하나를 둔다.**
  Widget _empty(AppColorsV2 colors) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppStrings.recordCardPhotoEmpty,
            textAlign: TextAlign.center,
            style: AppTypographyV2.body18.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space4),
          _AddTile(onTap: _add, big: true),
        ],
      ),
    ),
  );

  Widget _filled(AppColorsV2 colors, List<CardPhotoDraft> photos) {
    // 지운 뒤 한 프레임 동안 옛 자리를 가리킬 수 있다. 그리기 전에 당긴다.
    final page = _page.clamp(0, photos.length - 1);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space2,
        AppSpacing.space4,
        AppSpacing.space8,
      ),
      children: [
        SizedBox(
          height: _previewHeight,
          child: Center(
            child: AspectRatio(
              aspectRatio: CardPhotoDraft.aspectRatio,
              child: ClipRRect(
                borderRadius: AppRadius.md,
                child: PageView.builder(
                  controller: _pager,
                  onPageChanged: _onPage,
                  itemCount: photos.length,
                  itemBuilder: (context, index) => Semantics(
                    label: AppStrings.recordCardPhotoSemantics(
                      index + 1,
                      photos.length,
                    ),
                    child: switch (photos[index]) {
                      // 이미 올린 사진은 **밀 수 없다** — 9:16으로 잘려
                      // 나갔으므로 틀 안에서 옮길 데가 없다.
                      final SavedPhoto saved => Image(
                        image: cardThumbnail(context, saved.url),
                        fit: BoxFit.cover,
                        // ⚠️ **서명이 만료되면 못 받는다.** 고치는 중에
                        // 화면이 터지면 쓰던 것을 통째로 잃는다 — 못 받은
                        // 자리만 말하고 나머지는 계속 고칠 수 있게 둔다.
                        errorBuilder: (context, _, _) =>
                            const UnreadablePhoto(),
                      ),
                      final PickedPhoto picked => CardPhotoPan(
                        photo: picked,
                        // 넘기는 중에는 끄지 않는다 — `PageView`가 가로
                        // 끌기를 먼저 가져가므로, 미는 사진에서는 장을 넘길
                        // 수 없다. 점을 눌러 넘기는 길을 아래에 둔다.
                        onAlign: ({alignX, alignY}) => _draft.setPhotoAlign(
                          index,
                          alignX: alignX,
                          alignY: alignY,
                        ),
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        // ⚠️ `+`는 다섯 장이 차도 **그대로 둔다.** 사라지면 왜 더 못 넣는지
        // 알 길이 없다 — 누르면 상한을 말한다(`_add`).
        _Dots(count: photos.length, current: page, onJump: _jump, onAdd: _add),
        const SizedBox(height: AppSpacing.space2),
        // ⚠️ **보고 있는 장이 밀리는 것일 때만 말한다.** 이미 올린 사진에
        // "밀어 보세요"라고 하면 거짓말이다 — 9:16으로 잘려 나가 옮길 데가 없다.
        if (photos[page] is PickedPhoto)
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
            photos[page].caption.characters.length,
            CardPhotoDraft.captionMaxLength,
          ),
          maxLines: 3,
          // 칸에서 막고 초안에서 한 번 더 자른다.
          inputFormatters: [
            LengthLimitingTextInputFormatter(CardPhotoDraft.captionMaxLength),
          ],
          onChanged: (text) => _draft.setCaption(page, text),
        ),
        const SizedBox(height: AppSpacing.space4),
        Center(
          child: TextButton(
            onPressed: () => _remove(page),
            child: Text(
              AppStrings.recordCardPhotoRemove,
              style: AppTypographyV2.body18.copyWith(color: colors.error),
            ),
          ),
        ),
      ],
    );
  }

  /// 9:16을 폭에 꽉 채우면 화면보다 높아져 캡션이 한 화면에 안 들어온다 —
  /// 작성 1의 경로 미리보기와 같은 값이다.
  static const _previewHeight = 320.0;

  void _onPage(int page) {
    setState(() => _page = page);
    _caption.text = _captionAt(page);
  }

  void _jump(int page) {
    _pager.jumpToPage(page);
    _onPage(page);
  }

  Future<void> _add() async {
    if (_picking) return;

    // ⚠️ **거절을 말한다.** 조용히 아무 일도 안 하면 고장으로 읽힌다.
    if (!ref.read(cardDraftProvider(widget.cardId)).canAddPhoto) {
      _say(AppStrings.recordCardPhotoLimit(CardDraft.maxPhotos));
      return;
    }

    _picking = true;
    final PickedImage? image;
    try {
      image = await ref.read(photoPickerProvider).pick();
    } on ProfileImageException catch (error) {
      if (mounted) _say(_messageOf(error.failure));
      return;
    } on Object {
      if (mounted) _say(AppStrings.recordCardPhotoPickFailed);
      return;
    } finally {
      _picking = false;
    }

    // ⚠️ **취소는 실패가 아니다.** 올릴 생각을 접었을 뿐인 사람에게
    // "못 가져왔다"고 하면 거짓말이다.
    if (image == null || !mounted) return;

    _draft.addPhoto(image);
    // 방금 넣은 장을 보여 준다 — 안 넘기면 무엇이 들어왔는지 모른다.
    final last = _photos.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jump(last);
    });
  }

  void _remove(int index) {
    _draft.removePhotoAt(index);
    final left = _photos.length;
    if (left == 0) {
      setState(() => _page = 0);
      _caption.text = '';
      return;
    }
    // ⚠️ 마지막 장을 지웠으면 **앞 장**을 본다. 그대로 두면 범위를 넘는 자리를
    // 그리려다 죽는다.
    final next = index.clamp(0, left - 1);
    setState(() => _page = next);
    _caption.text = _captionAt(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pager.hasClients) _pager.jumpToPage(next);
    });
  }

  /// `ProfileImageFailure`를 **카드 사진의 말**로 옮긴다. 프로필 문구를 그대로
  /// 쓰면 "프로필 사진"이라는 말이 카드 작성 화면에 나온다.
  String _messageOf(ProfileImageFailure failure) => switch (failure) {
    ProfileImageFailure.unsupportedFormat =>
      AppStrings.recordCardPhotoUnsupported,
    ProfileImageFailure.tooLarge => AppStrings.recordCardPhotoTooLarge,
    _ => AppStrings.recordCardPhotoPickFailed,
  };

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

/// 점 인디케이터 + `+`. 점을 눌러 장을 넘긴다 — 미는 사진 위에서는 가로
/// 끌기가 사진에 먹혀 넘길 수 없다.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.current,
    required this.onJump,
    required this.onAdd,
  });

  final int count;
  final int current;
  final ValueChanged<int> onJump;
  final VoidCallback onAdd;

  static const _size = 10.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space1),
            child: Semantics(
              button: true,
              selected: i == current,
              // ⚠️ 사진 자체와 **다른 말이어야 한다.** 같으면 스크린리더가
              // 한 장에 두 번 같은 이름을 읽고, 어느 쪽이 넘기는 버튼인지
              // 모른다.
              label: AppStrings.recordCardPhotoGoTo(i + 1, count),
              child: GestureDetector(
                onTap: () => onJump(i),
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == current ? colors.primary : colors.bgSurface,
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.space2),
          child: _AddTile(onTap: onAdd),
        ),
      ],
    );
  }
}

/// 사진 한 장 더. **아이콘뿐이라 `Tooltip`으로 이름을 준다.**
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap, this.big = false});

  final VoidCallback onTap;

  /// 빈 상태에서는 크게 둔다 — 그 화면의 유일한 할 일이다.
  final bool big;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppStrings.recordCardPhotoAdd,
    onPressed: onTap,
    iconSize: big ? 40 : 24,
    icon: Icon(LucideIcons.plus, color: context.appColorsV2.textPrimary),
  );
}
