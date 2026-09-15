import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart' as picker;
import 'package:runiverse/features/profile/domain/exif_stripper.dart';
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';

/// 기기 앨범에서 고른다.
///
/// ⚠️ `image_picker`의 `ImageSource`와 이 앱의 이름이 겹칠 수 있어 **접두사를 붙여
/// import**한다. 겹친 채로 두면 어느 쪽 타입인지 읽는 사람이 헷갈린다.
///
/// ## 크기를 줄이지 않는다
///
/// `pickImage`에는 `maxWidth`·`imageQuality`가 있다. 쓰지 않는 이유는 그것이
/// **파일 크기를 바꾸기 때문**이다. 줄인 뒤의 크기를 다시 재서 서명을 받아야 하는데,
/// 재는 시점과 올리는 시점 사이에 값이 갈리면 403이 되고 원인이 보이지 않는다.
/// 10MB를 넘는 사진은 [PickedImage.validated]가 여기서 막는다.
///
/// ## ⚠️ EXIF는 크기를 재기 **전에** 지운다
///
/// 프로필 사진 URL은 인증 없이 공개인데 갤러리 원본에는 촬영 위치가 담겨 있다.
/// presigned 업로드라 서버가 중간에서 못 지운다.
///
/// 지우면 파일이 작아진다. **크기를 잰 뒤에 지우면** 서명받은 크기와 실제로
/// 올리는 바이트가 갈려 403이 나고, 위 주석이 말하는 바로 그 함정에 빠진다.
class GalleryPhotoPicker implements PhotoPicker {
  const GalleryPhotoPicker();

  @override
  Future<PickedImage?> pick() async {
    final file = await picker.ImagePicker().pickImage(
      source: picker.ImageSource.gallery,
    );
    // 취소했다. 실패가 아니다.
    if (file == null) return null;

    final path = await _withoutMetadata(File(file.path));

    // 조건에 맞지 않으면 여기서 던진다. 서버까지 보내고 400을 받는 것보다
    // 왕복 한 번을 아끼고, 무엇이 문제였는지 정확히 말해줄 수 있다.
    return PickedImage.validated(
      path: path,
      sizeBytes: await File(path).length(),
    );
  }

  /// 메타데이터를 뺀 사본을 만들고 그 경로를 돌려준다.
  ///
  /// 확장자를 유지한다 — [PickedImage]가 확장자로 MIME 타입을 정한다.
  ///
  /// ⚠️ **원본은 지운다.** 위치가 담긴 사본을 캐시에 남겨 둘 이유가 없다.
  /// 지우지 못해도 업로드는 계속한다 — 올릴 파일은 이미 깨끗하다.
  Future<String> _withoutMetadata(File original) async {
    final bytes = await original.readAsBytes();

    final Uint8List stripped;
    try {
      stripped = ExifStripper.strip(bytes);
    } on UnsupportedImageFormat {
      // ⚠️ 원본을 그대로 올리지 않는다. 못 지웠다는 것은 위치가 남아 있을 수
      // 있다는 뜻이고, 조용히 통과시키면 막으려던 것이 그대로 나간다.
      throw const ProfileImageException(ProfileImageFailure.unsupportedFormat);
    }

    final dot = original.path.lastIndexOf('.');
    final extension = dot < 0 ? '' : original.path.substring(dot);
    final name = 'runiverse_profile_${DateTime.now().microsecondsSinceEpoch}';
    final copy = File('${Directory.systemTemp.path}/$name$extension');
    await copy.writeAsBytes(stripped, flush: true);

    try {
      await original.delete();
    } on Object {
      // 캐시 파일 하나가 남는 것뿐이다. 여기서 러닝을 멈출 이유가 없다.
    }

    return copy.path;
  }
}
