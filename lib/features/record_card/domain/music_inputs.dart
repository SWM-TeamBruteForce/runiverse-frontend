import 'package:runiverse/features/record_card/domain/card_draft.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';

/// AI가 음악을 만들 때 **읽는 것**만 모은 것.
///
/// ## ⚠️ 이것이 달라지면 전곡이 다시 만들어진다
///
/// 백엔드가 "사진·캡션·회고·유형이 바뀌면 전곡 재생성"으로 못 박았다
/// (설계 3절). **공개범위는 세지 않는다** — AI 입력이 아니라서, 바꿔도 음악은
/// 그대로다(6-6). 러닝 기록도 세지 않는다 — 수정에서 바꿀 수 없다.
///
/// ## ⚠️ 왜 값 객체 하나인가
///
/// "바뀌었나"를 **두 곳**에서 묻는다 — 작성 3이 경고를 띄울 때(초안 ↔ 카드)와
/// 저장소가 생성을 되돌릴 때(수정 요청 ↔ 카드). 두 번 적으면 한쪽만 고쳐져
/// **경고는 뜨는데 음악은 그대로**거나 그 반대가 된다.
class MusicInputs {
  const MusicInputs({
    required this.activity,
    required this.reviewText,
    required this.photos,
  });

  /// 카드가 지금 들고 있는 값.
  factory MusicInputs.ofCard(RecordCard card) => MusicInputs(
    activity: card.activity,
    reviewText: card.reviewText,
    photos: [for (final photo in card.photos) _saved(photo.id, photo.caption)],
  );

  /// 쓰고 있는 초안의 값.
  factory MusicInputs.ofDraft(CardDraft draft) => MusicInputs(
    activity: draft.activity,
    reviewText: draft.reviewText,
    photos: [
      for (final photo in draft.photos)
        switch (photo) {
          SavedPhoto(:final id) => _saved(id, photo.caption),
          PickedPhoto(:final image) => _added(image.path, photo.caption),
        },
    ],
  );

  /// 보내려는 수정 요청의 값.
  factory MusicInputs.ofEdit(EditRecordCard card) => MusicInputs(
    activity: card.activity,
    reviewText: card.reviewText,
    photos: [
      for (final photo in card.photos)
        if (photo.savedId case final savedId?)
          _saved(savedId, photo.caption)
        else
          _added(photo.path!, photo.caption),
    ],
  );

  final RecordCardActivity? activity;

  final String reviewText;

  /// 사진 하나를 **"무엇인가 + 한마디"**로 줄인 것. **순서도 센다** — 순서를
  /// 바꾸면 1번 사진의 곡과 2번의 곡이 바뀌어야 하므로 재생성이 맞다.
  ///
  /// ⚠️ 이미 올린 것은 `s<번호>|<캡션>`, 새로 고른 것은 `n<경로>|<캡션>`이다.
  /// **접두사가 갈라서** 번호 `12`와 경로 `12`가 같은 것으로 읽히지 않는다.
  final List<String> photos;

  static String _saved(int id, String? caption) => 's$id|${caption ?? ''}';

  static String _added(String path, String? caption) =>
      'n$path|${caption ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is MusicInputs &&
      other.activity == activity &&
      other.reviewText == reviewText &&
      _sameOrder(other.photos, photos);

  @override
  int get hashCode => Object.hash(activity, reviewText, Object.hashAll(photos));

  /// 같은 것이 같은 순서로 들었나.
  ///
  /// ⚠️ **`listEquals`를 못 쓴다.** 그것은 `package:flutter/foundation.dart`에
  /// 있고 `domain/`은 순수 Dart만 쓴다(CLAUDE.md).
  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
