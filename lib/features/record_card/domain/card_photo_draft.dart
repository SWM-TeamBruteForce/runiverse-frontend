import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 초안에 담긴 사진 한 장. **둘 중 하나다.**
///
/// ## ⚠️ 왜 갈라야 하나
///
/// 수정은 작성 2를 그대로 다시 쓴다(설계 6-6). 그런데 이미 만든 카드의 사진은
/// **올라간 주소**이고, 방금 고른 사진은 **기기 안 파일**이다. 한 종류만 담으면
/// **3장짜리 카드가 0장으로 열린다.**
///
/// 갈라 두면 저장이 할 일도 갈린다 — [SavedPhoto]는 번호만 돌려보내고,
/// [PickedPhoto]만 자르고 올린다.
sealed class CardPhotoDraft {
  const CardPhotoDraft({required this.caption});

  /// 이 사진에 붙인 한마디. **AI가 사진 음악을 만들 때 읽는다**(설계 6-3).
  /// 선택이라 빈 문자열이 "안 썼다"다.
  final String caption;

  /// 캡션 상한. 설계 6-3이 정한 값이다.
  ///
  /// ⚠️ **grapheme으로 센다.** code unit으로 자르면 이모지 경계에서 서로게이트
  /// 쌍이 갈라져 서버로 `U+FFFD`가 간다.
  static const captionMaxLength = 100;

  /// 사진 틀. 카드 상세의 페이저와 같은 비율이다.
  static const aspectRatio = 9 / 16;

  /// 캡션만 바꾼 같은 종류의 사진.
  ///
  /// ⚠️ **종류가 섞이면 안 된다.** 섞이면 저장이 올린 사진을 새 사진으로 보고
  /// **이미 잘린 것을 또 자른다** — 9:16을 또 자르면 그림이 좁아진다.
  CardPhotoDraft withCaption(String caption);
}

/// 이미 올라가 있는 사진. **다시 자르지 않는다.**
///
/// ⚠️ **밀 수 없다.** 올릴 때 9:16으로 잘려 나갔으므로 틀 안에서 옮길 데가
/// 없다. 끌기를 달면 아무 일도 일어나지 않는 제스처가 된다.
class SavedPhoto extends CardPhotoDraft {
  const SavedPhoto({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    super.caption = '',
  });

  /// `record_card_image_id`. 수정할 때 **이 번호로 "남긴다"고 말한다.**
  final int id;

  /// 원본 열람 주소. 9:16으로 잘린 결과다.
  final String url;

  /// 작은 쪽. 없으면 [url]을 쓴다.
  final String? thumbnailUrl;

  @override
  SavedPhoto withCaption(String caption) => SavedPhoto(
    id: id,
    url: url,
    thumbnailUrl: thumbnailUrl,
    caption: caption,
  );
}

/// 방금 고른 사진. **저장할 때 자른다.**
///
/// ## ⚠️ 자르는 일은 저장할 때 한 번에 한다
///
/// 담는 것은 **고른 원본 경로 + 밀어 둔 위치**다. 프로필 커버와 같은 순서다
/// (`PendingPhoto`) — 자르면 바이트가 바뀌어 되돌릴 수 없으므로, 사용자가 작성
/// 화면 사이를 오가며 위치를 다시 고칠 수 있게 끝까지 원본을 들고 있다.
///
/// ## ⚠️ 틀은 9:16이고 **좌우로** 민다
///
/// [CardPhotoDraft.aspectRatio]가 세로로 길어 4:3이든 3:4든 실제 사진은 거의 다
/// 좌우로 넘친다. 그래서 [alignX]가 주로 쓰이고 [alignY]는 스크린숏처럼 홀쭉한
/// 사진에서만 쓰인다. 어느 축이 쓰이는지는 `CoverCrop.rect`가 고른다.
class PickedPhoto extends CardPhotoDraft {
  const PickedPhoto({
    required this.image,
    super.caption = '',
    this.alignX = 0,
    this.alignY = 0,
  });

  /// 고른 원본. 10MB 상한과 형식 검사는 [PickedImage]가 이미 했다.
  final PickedImage image;

  /// 가로 위치. -1 왼쪽 · 0 가운데 · 1 오른쪽.
  final double alignX;

  /// 세로 위치. -1 위 · 0 가운데 · 1 아래.
  final double alignY;

  @override
  PickedPhoto withCaption(String caption) => PickedPhoto(
    image: image,
    caption: caption,
    alignX: alignX,
    alignY: alignY,
  );

  /// **주지 않은 축은 그대로 둔다.**
  PickedPhoto withAlign({double? alignX, double? alignY}) => PickedPhoto(
    image: image,
    caption: caption,
    alignX: alignX ?? this.alignX,
    alignY: alignY ?? this.alignY,
  );
}
