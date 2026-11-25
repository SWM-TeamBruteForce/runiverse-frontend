// `.characters`가 여기서 온다 — `package:flutter/widgets.dart`가 `characters`를
// 재수출한다. 그 패키지를 직접 적으면 `depend_on_referenced_packages`가 뜬다
// (pubspec에 없는 전이 의존이다). 저장소의 다른 자리도 같은 방식이다.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 쓰다 만 기록카드. **인자는 카드 번호이고, `null`이 새 카드다.**
///
/// ## ⚠️ 수정은 카드별로 따로 둔다
///
/// 새 카드를 쓰던 중에 남의 카드 수정으로 들어가도 섞이지 않아야 한다
/// (설계 7절). family 인자가 그것을 가른다.
///
/// ## ⚠️ `autoDispose`를 붙이지 않는다
///
/// 작성 화면에서 공개범위로 라우트를 넘나든다. 붙이면 **그 순간 작성 화면의
/// 구독이 끊겨 쓴 것이 사라진다**(`docs/implementation-notes.md` §5-1). 이
/// 저장소의 수동 provider는 기본이 keepAlive라, 붙이지 않는 것이 곧 명시다.
///
/// 수명(설계 7절):
///
/// | 언제 | 어떻게 |
/// |---|---|
/// | 저장 성공 | [CardDraftController.clear] |
/// | 작성 화면에서 뒤로 | 쓴 것이 있으면 확인을 받고 [CardDraftController.clear] |
/// | 앱을 죽였다 켬 | **사라진다.** 영속화하지 않는다 |
final cardDraftProvider =
    NotifierProvider.family<CardDraftController, CardDraft, String?>(
      CardDraftController.new,
    );

class CardDraftController extends Notifier<CardDraft> {
  CardDraftController(this.cardId);

  /// 수정 중인 카드의 번호. **`null`이면 새 카드다.**
  final String? cardId;

  @override
  CardDraft build() => const CardDraft();

  /// 러닝 기록을 고른다.
  ///
  /// ⚠️ **다른 기록을 고르면 경로를 비운다.** 안 비우면 앞 기록의 선 아트가
  /// 이 카드에 그려진다. 같은 기록을 다시 누른 것은 비울 이유가 없다 —
  /// 버리면 상세 조회가 또 나간다.
  void pickRecord(RunRecord record) {
    final sameRecord = state.record?.id == record.id;
    state = state.copyWith(record: record, clearRoute: !sameRecord);
  }

  /// 고른 기록의 경로. **못 받았으면 `null`을 넣는다.**
  void setRoute(RouteArt? route) => state = route == null
      ? state.copyWith(clearRoute: true)
      : state.copyWith(route: route);

  void setActivity(RecordCardActivity activity) =>
      state = state.copyWith(activity: activity);

  /// 회고. **[CardDraft.reviewMaxLength]에서 자른다.**
  ///
  /// 입력 칸도 같은 수에서 막지만, 여기서 한 번 더 자른다 — 붙여넣기나 다른
  /// 경로로 긴 글이 들어오면 저장에서 거절당하고 쓴 글을 잃는다.
  void setReview(String text) =>
      state = state.copyWith(reviewText: _cut(text, CardDraft.reviewMaxLength));

  /// 사진 한 장을 끝에 붙인다.
  ///
  /// ⚠️ **상한에 닿으면 아무 일도 하지 않는다.** 던지지 않는 쪽을 골랐다 —
  /// 거절을 말하는 것은 화면의 일이고, 여기서 던지면 부르는 자리마다 `try`가
  /// 붙는다. 화면은 부르기 전에 [CardDraft.canAddPhoto]를 본다.
  void addPhoto(PickedImage image) {
    if (!state.canAddPhoto) return;
    state = state.copyWith(
      photos: [
        ...state.photos,
        PickedPhoto(image: image),
      ],
    );
  }

  /// [index] 자리의 사진을 뺀다. 나머지 순서는 그대로다.
  void removePhotoAt(int index) => _withPhoto(index, (photos) {
    photos.removeAt(index);
  });

  /// [index] 자리의 사진을 **대표로 올린다** — 목록 맨 앞으로 옮기고 나머지
  /// 순서는 그대로 둔다.
  ///
  /// ## ⚠️ 대표는 따로 두는 깃발이 아니라 **순서**다
  ///
  /// 달력 칸과 프로필 그리드가 `RecordCard.thumbnailUrl`(= **첫 사진**)을
  /// 얼굴로 쓴다. 깃발을 따로 두면 초안·저장·수정·카드·가짜에 필드가 하나씩
  /// 늘고, **서버에 그 컬럼이 없어** 답이 오기 전까지 가짜에서만 사는 값이
  /// 된다. 순서로 두면 썸네일 규칙을 한 글자도 건드리지 않는다
  /// (사용자 결정 2026-11-22).
  ///
  /// 대신 **포토북 넘기는 순서도 함께 바뀐다** — 대표가 첫 사진이 된다. 알고
  /// 고른 비용이다.
  ///
  /// ⚠️ **사진만 옮기지 않는다.** 캡션과 밀어 둔 위치가 사진에 붙어 있어
  /// ([CardPhotoDraft]) 통째로 간다 — 자리만 바꾸면 **남의 한마디가 붙는다.**
  ///
  /// ⚠️ **이미 맨 앞이거나 범위 밖이면 아무 일도 하지 않는다.** 같은 값을
  /// 새로 쓰면 듣고 있는 화면이 헛 그려진다.
  void makeCover(int index) {
    if (index <= 0 || index >= state.photos.length) return;
    final photos = [...state.photos];
    photos.insert(0, photos.removeAt(index));
    state = state.copyWith(photos: photos);
  }

  /// [index] 자리의 캡션. **[CardPhotoDraft.captionMaxLength]에서 자른다.**
  void setCaption(int index, String text) => _withPhoto(index, (photos) {
    photos[index] = photos[index].withCaption(
      _cut(text, CardPhotoDraft.captionMaxLength),
    );
  });

  /// [index] 자리의 사진을 민 위치. **주지 않은 축은 그대로 둔다.**
  ///
  /// ⚠️ **이미 올린 사진이면 아무 일도 하지 않는다.** 9:16으로 잘려 나갔으므로
  /// 틀 안에서 옮길 데가 없다. 화면도 그 장에는 끌기를 달지 않지만, 늦게 온
  /// 콜백이 여기로 올 수 있다.
  void setPhotoAlign(int index, {double? alignX, double? alignY}) =>
      _withPhoto(index, (photos) {
        final photo = photos[index];
        if (photo is! PickedPhoto) return;
        photos[index] = photo.withAlign(alignX: alignX, alignY: alignY);
      });

  void setVisibility(RecordCardVisibility visibility) =>
      state = state.copyWith(visibility: visibility);

  /// 고른 기록을 푼다. **경로도 함께 비운다** — 기록 없는 경로는 뜻이 없다.
  ///
  /// 유형과 회고는 남긴다. 날짜를 잘못 골라 되돌리는 사람의 글을 버리지 않는다.
  void clearRecord() =>
      state = state.copyWith(clearRecord: true, clearRoute: true);

  /// 카드 값을 초안에 **한 번만** 뿌린다 (설계 6-6).
  ///
  /// ## ⚠️ 이미 손댄 초안은 건드리지 않는다
  ///
  /// 화면이 들어올 때마다 부른다. 안 막으면 공개범위 화면에 갔다 돌아올
  /// 때마다 다시 뿌려 **고친 것이 되돌아간다.**
  void seed(RecordCard card) {
    if (state.isDirty) return;
    state = CardDraft.fromCard(card);
  }

  /// 고친 것을 버리고 **카드 값으로 되돌린다.**
  ///
  /// ⚠️ [clear]가 아니다 — 그것은 `editing`까지 지워, 화면이 여전히 수정
  /// 모드인데 고칠 카드가 없는 상태를 만든다(저장 버튼이 영원히 꺼진다).
  void restore(RecordCard card) => state = CardDraft.fromCard(card);

  void clear() => state = const CardDraft();

  /// 사진 목록을 고친다. **[index]가 범위를 넘으면 아무 일도 하지 않는다.**
  ///
  /// ⚠️ 화면이 지운 뒤 늦게 온 콜백이 있다 — 캡션 칸의 `onChanged`나 미리보기의
  /// 끌기가 한 프레임 늦게 도착한다. 던지면 **작성 중에 앱이 죽는다.**
  void _withPhoto(int index, void Function(List<CardPhotoDraft>) change) {
    if (index < 0 || index >= state.photos.length) return;
    final photos = [...state.photos];
    change(photos);
    state = state.copyWith(photos: photos);
  }

  /// **grapheme으로 센다.** code unit으로 자르면 이모지 경계에서 서로게이트
  /// 쌍이 갈라져 서버로 `U+FFFD`가 간다.
  static String _cut(String text, int max) {
    final characters = text.characters;
    return characters.length > max ? characters.take(max).toString() : text;
  }
}
