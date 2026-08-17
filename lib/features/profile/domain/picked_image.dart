import 'package:runiverse/features/profile/domain/profile_image_failure.dart';

/// 앨범에서 고른 사진 한 장.
///
/// ## 왜 이 값이 따로 있는가
///
/// [mimeType]과 [sizeBytes]는 **presigned URL의 서명에 그대로 들어간다.** 발급을
/// 요청할 때 쓴 값과 S3에 올릴 때 보내는 헤더가 1바이트라도 다르면 403이 온다.
/// 두 곳에서 따로 계산하면 언젠가 갈라지므로, **한 번 정해서 끝까지 들고 다닌다.**
///
/// ## 바이트를 담지 않는다
///
/// 10MB짜리를 도메인 객체에 얹으면 화면 상태에 그대로 남는다. 파일을 실제로 읽는
/// 것은 올리기 직전 한 번이면 되고, 그것은 `data` 계층의 일이다 —
/// `domain`은 순수 Dart라 `dart:io`를 볼 수 없다.
class PickedImage {
  const PickedImage._({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String path;

  /// `image/jpeg` · `image/png` · `image/webp` 중 하나. 서버가 이 셋만 받는다.
  final String mimeType;

  final int sizeBytes;

  /// 서버 상한과 같은 값(`@Max(10_485_760)`). 여기서 먼저 막는다.
  static const maxBytes = 10 * 1024 * 1024;

  /// 확장자로 [mimeType]을 정한다. **내용을 보지 않는다** —
  /// 매직 넘버를 읽으려면 파일을 열어야 하는데, 이름을 바꿔 넣은 파일은
  /// 어차피 서버가 업로드된 객체를 다시 검사해서 걸러낸다(`ChangeProfileImageHandler`).
  ///
  /// 조건에 맞지 않으면 [ProfileImageException]을 던진다.
  factory PickedImage.validated({
    required String path,
    required int sizeBytes,
  }) {
    final mimeType = _mimeTypeOf(path);
    if (mimeType == null) {
      throw const ProfileImageException(ProfileImageFailure.unsupportedFormat);
    }
    // 서버가 `@Min(1)`로 막는다. 0바이트 파일이 실제로 존재한다.
    if (sizeBytes < 1 || sizeBytes > maxBytes) {
      throw const ProfileImageException(ProfileImageFailure.tooLarge);
    }
    return PickedImage._(path: path, mimeType: mimeType, sizeBytes: sizeBytes);
  }

  /// 모르는 확장자면 `null`. 아이폰 기본인 `heic`가 여기 걸린다.
  static String? _mimeTypeOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    return switch (path.substring(dot + 1).toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
  }
}
