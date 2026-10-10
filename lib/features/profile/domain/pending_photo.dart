import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 화면이 들고 있는, **아직 서버에 보내지 않은** 사진 변경.
///
/// ## 왜 값으로 따로 두나
///
/// 예전에는 사진을 고르는 **즉시** 올라갔다. 저장 버튼은 꺼진 채였고 그냥
/// 나가도 이미 반영돼 있었다 — 버튼이 꺼져 있으면 **저장할 것이 없다**는
/// 뜻으로 읽히는데 실제로는 이미 저장된 뒤라, 되돌릴 방법이 없었다.
///
/// 이제 고른 것을 화면이 들고 있다가 저장할 때 보낸다. 그 "들고 있는 것"이
/// 이 값이다.
///
/// ## 플래그 두 개로 쪼개지 않는다
///
/// `PickedImage? picked` 와 `bool removed` 로 두면 **둘 다 참인 상태**가
/// 표현된다. 그런 일은 없어야 하는데 타입이 막아주지 않는다.
sealed class PendingPhoto {
  const PendingPhoto();
}

/// 앨범에서 새로 골랐다. 저장하면 [image]가 올라간다.
final class PhotoPicked extends PendingPhoto {
  const PhotoPicked(this.image);

  final PickedImage image;
}

/// 지우고 기본 이미지로 돌아가기로 했다.
final class PhotoRemoved extends PendingPhoto {
  const PhotoRemoved();
}
