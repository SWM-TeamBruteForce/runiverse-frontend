import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/record_card/data/compressed_card_thumbnail_maker.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/card_thumbnail_maker.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

final cardThumbnailMakerProvider = Provider<CardThumbnailMaker>(
  (ref) => const CompressedCardThumbnailMaker(),
);

/// 저장이 어디까지 갔나.
///
/// `record_card_state.dart`와 같은 꼴의 sealed union이다 — freezed 미도입이라
/// 손으로 쓴다.
sealed class CardSaveState {
  const CardSaveState();
}

/// 아직 안 눌렀거나, 눌러서 끝났다.
class CardSaveIdle extends CardSaveState {
  const CardSaveIdle();
}

/// 도는 중. **버튼이 다시 눌리지 않아야 한다.**
class CardSaveSaving extends CardSaveState {
  const CardSaveSaving();
}

/// 못 만들었다. **초안은 그대로 남아 있다.**
class CardSaveFailed extends CardSaveState {
  const CardSaveFailed(this.failure);

  final RecordCardFailure failure;
}

/// 초안을 카드로 만든다. **인자는 카드 번호이고, `null`이 새 카드다** —
/// `cardDraftProvider`와 같은 열쇠다.
final cardSaveProvider =
    NotifierProvider.family<CardSaveController, CardSaveState, int?>(
      CardSaveController.new,
    );

class CardSaveController extends Notifier<CardSaveState> {
  CardSaveController(this.cardId);

  final int? cardId;

  @override
  CardSaveState build() => const CardSaveIdle();

  /// 사진을 자르고 썸네일을 만든 뒤 카드를 만든다.
  ///
  /// 만들었으면 카드, 못 만들었으면 `null`이다 — 부르는 쪽은 `null`이면
  /// **화면에 머문다.**
  ///
  /// ## ⚠️ 실패하면 초안을 비우지 않는다
  ///
  /// 초안은 영속화하지 않아(설계 7절) 비우면 **쓴 회고까지 되돌릴 길이
  /// 없다.** 사진 파일이 사라진 것은 사진만의 문제인데 글까지 잃으면 안 된다.
  Future<RecordCard?> save() async {
    // ⚠️ **두 번 누르면 카드가 둘 생긴다.** 서버의
    // `unique(running_record_id)`가 뒤늦게 터진다.
    if (state is CardSaveSaving) return null;

    final draft = ref.read(cardDraftProvider(cardId));
    // 저장할 수 없는 것을 보내지 않는다. 화면도 버튼을 닫아 두지만, 여기가
    // 마지막 문이다.
    if (!draft.canProceed) return null;

    state = const CardSaveSaving();

    final cropper = ref.read(imageCropperProvider);
    final cropped = <PickedImage>[];
    try {
      final photos = <NewCardPhoto>[];
      for (final photo in draft.photos) {
        final one = await cropper.crop(
          photo.image,
          aspectRatio: CardPhotoDraft.aspectRatio,
          alignX: photo.alignX,
          alignY: photo.alignY,
        );
        cropped.add(one);
        photos.add(
          NewCardPhoto(
            path: one.path,
            thumbnailPath: await _thumbnail(one.path),
            // 안 쓴 캡션은 빈 문자열이 아니라 `null`이다 — 서버의
            // `caption`도 nullable이다.
            caption: photo.caption.isEmpty ? null : photo.caption,
          ),
        );
      }

      final card = await ref
          .read(recordCardRepositoryProvider)
          .create(
            NewRecordCard(
              record: draft.record!,
              // ⚠️ 경로가 없는 러닝(트레드밀)은 **빈 선 아트**다.
              // `RecordCard.route`는 null을 받지 못한다.
              route: draft.route ?? RouteArt.empty,
              activity: draft.activity!,
              visibility: draft.visibility,
              reviewText: draft.reviewText,
              photos: photos,
              musicEnabled: draft.musicEnabled,
            ),
          );

      ref.read(cardDraftProvider(cardId).notifier).clear();
      state = const CardSaveIdle();
      return card;
    } on RecordCardException catch (error) {
      state = CardSaveFailed(error.failure);
      return null;
    } on ProfileImageException {
      // 자르지 못했다 — 고른 파일이 사라졌거나 디코더가 거절했다. 서버가
      // 거절한 것이 아니므로 `network`가 아니라 "다시 해 보라"는 쪽으로 둔다.
      state = const CardSaveFailed(RecordCardFailure.invalidRequest);
      return null;
    } on Object {
      // 썸네일 플러그인이 터지는 등 생각 못 한 실패다. **삼키지 않는다** —
      // 삼키면 버튼이 영원히 도는 것으로 보인다.
      state = const CardSaveFailed(RecordCardFailure.server);
      return null;
    } finally {
      // ⚠️ **성공이든 실패든 치운다.** 저장할 때마다 새로 자르므로 남겨 둘
      // 이유가 없고, 안 치우면 임시 폴더에 쌓인다.
      for (final one in cropped) {
        await cropper.discard(one);
      }
    }
  }

  /// 썸네일. **못 만들어도 저장을 멈추지 않는다.**
  Future<String?> _thumbnail(String croppedPath) async {
    try {
      return await ref.read(cardThumbnailMakerProvider).make(croppedPath);
    } on Object {
      // 약속은 `null`인데 던지는 구현이 있을 수 있다. 달력이 원본을 쓴다.
      return null;
    }
  }
}
