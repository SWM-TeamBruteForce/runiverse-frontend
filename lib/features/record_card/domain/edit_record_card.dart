import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';

/// 고친 뒤에 **남길 사진 하나.**
///
/// 이미 올라가 있던 것이면 [savedId]로 "그대로 둔다"고 말하고, 새로 고른
/// 것이면 [path]로 올릴 파일을 준다. **둘 중 하나만 찬다.**
class EditCardPhoto {
  /// 이미 올라가 있던 사진을 그대로 남긴다.
  const EditCardPhoto.saved({required this.savedId, this.caption})
    : file = null,
      thumbnail = null;

  /// 새로 올릴 사진. 9:16으로 **이미 잘린** 파일이다.
  const EditCardPhoto.added({
    required this.file,
    required this.thumbnail,
    this.caption,
  }) : savedId = null;

  /// `record_card_image_id`(UUID 문자열). 새 사진이면 `null`이다.
  final String? savedId;

  /// 올릴 파일. 이미 있던 사진이면 `null`이다.
  final PickedImage? file;

  /// 긴 변 320px의 작은 사본. 이미 있던 사진이면 `null`이고, **새 사진이면
  /// 반드시 있다** — 9-1·9-3이 크기를 요구한다.
  final PickedImage? thumbnail;

  /// 안 썼으면 `null`이다 — 서버의 `caption`도 nullable이다.
  final String? caption;
}

/// 고친 카드 하나.
///
/// ## ⚠️ **남길 사진 전체**를 싣는다
///
/// 바뀐 것만 보내지 않는다(사용자 결정 2026-11-19). 서버가 **차집합으로
/// 지우고**, 앱은 무엇이 바뀌었는지 추적하지 않는다 — 순서 바꾸기도 공짜다.
///
/// 그래서 **빈 목록은 "사진을 전부 지웠다"는 뜻**이지 "안 바꿨다"가 아니다.
///
/// ## ⚠️ 음악 설정도 없다
///
/// `RecordCard`에 음악 상태 필드가 없어(묶음 5) **이 카드가 음악을 켜고
/// 만들어졌는지 모른다.** 모르는 값을 지어내 보내면 사용자가 거절했던 생성이
/// 수정 한 번으로 켜진다 — 보내지 않으면 서버가 건드릴 일도 없다
/// (사용자 결정 2026-11-19).
///
/// ## ⚠️ 러닝 기록은 없다
///
/// 수정에서 바꿀 수 없다(설계 6-6) — `unique(running_record_id)` 때문에 카드
/// 있는 기록으로 옮기면 거절당하고, 바꾸면 지표·경로가 통째로 달라져 다른
/// 카드가 된다. 보내지 않으면 서버가 건드릴 일도 없다.
class EditRecordCard {
  const EditRecordCard({
    required this.cardId,
    required this.activity,
    required this.visibility,
    required this.reviewText,
    required this.photos,
  });

  final String cardId;
  final RecordCardActivity activity;
  final RecordCardVisibility visibility;
  final String reviewText;

  /// **남길 사진 전체.** 비어 있으면 전부 지운다는 뜻이다.
  final List<EditCardPhoto> photos;
}
