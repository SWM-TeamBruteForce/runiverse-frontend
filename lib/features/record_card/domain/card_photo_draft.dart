import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 카드에 붙이려고 고른 사진 한 장. **아직 자르지 않았다.**
///
/// ## ⚠️ 자르는 일은 저장할 때 한 번에 한다
///
/// 여기 담는 것은 **고른 원본 경로 + 밀어 둔 위치**다. 프로필 커버와 같은
/// 순서다(`PendingPhoto`) — 자르면 바이트가 바뀌어 되돌릴 수 없으므로, 사용자가
/// 작성 화면 사이를 오가며 위치를 다시 고칠 수 있게 끝까지 원본을 들고 있다.
///
/// ## ⚠️ 틀은 9:16이고 **좌우로** 민다
///
/// [aspectRatio]가 세로로 길어 4:3이든 3:4든 실제 사진은 거의 다 좌우로
/// 넘친다. 그래서 [alignX]가 주로 쓰이고 [alignY]는 스크린숏처럼 홀쭉한
/// 사진에서만 쓰인다. 어느 축이 쓰이는지는 `CoverCrop.rect`가 고른다.
class CardPhotoDraft {
  const CardPhotoDraft({
    required this.image,
    this.caption = '',
    this.alignX = 0,
    this.alignY = 0,
  });

  /// 고른 원본. 10MB 상한과 형식 검사는 [PickedImage]가 이미 했다.
  final PickedImage image;

  /// 이 사진에 붙인 한마디. **AI가 사진 음악을 만들 때 읽는다**(설계 6-3).
  /// 선택이라 빈 문자열이 "안 썼다"다.
  final String caption;

  /// 가로 위치. -1 왼쪽 · 0 가운데 · 1 오른쪽.
  final double alignX;

  /// 세로 위치. -1 위 · 0 가운데 · 1 아래.
  final double alignY;

  /// 캡션 상한. 설계 6-3이 정한 값이다.
  ///
  /// ⚠️ **grapheme으로 센다.** code unit으로 자르면 이모지 경계에서 서로게이트
  /// 쌍이 갈라져 서버로 `U+FFFD`가 간다.
  static const captionMaxLength = 100;

  /// 사진 틀. 카드 상세의 페이저와 같은 비율이다.
  static const aspectRatio = 9 / 16;

  CardPhotoDraft copyWith({String? caption, double? alignX, double? alignY}) =>
      CardPhotoDraft(
        image: image,
        caption: caption ?? this.caption,
        alignX: alignX ?? this.alignX,
        alignY: alignY ?? this.alignY,
      );
}
