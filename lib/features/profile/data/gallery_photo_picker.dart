import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:runiverse/features/profile/domain/exif_stripper.dart';
import 'package:runiverse/features/profile/domain/image_transformer.dart';
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';

/// 기기 앨범에서 고른다.
///
/// ⚠️ `image_picker`의 `ImageSource`와 이 앱의 이름이 겹칠 수 있어 **접두사를 붙여
/// import**한다. 겹친 채로 두면 어느 쪽 타입인지 읽는 사람이 헷갈린다.
///
/// ## ⚠️ 순서가 전부다
///
/// ```
/// 고르기 → 회전 적용·축소(JPEG) → 메타데이터 제거 → 크기 측정 → 발급 요청
/// ```
///
/// | 자리 | 뒤집으면 |
/// |---|---|
/// | 회전이 **제거보다 먼저** | 회전 값이 EXIF와 함께 사라져 **사진이 눕는다** |
/// | 측정이 **둘 다 끝난 뒤** | 서명받은 크기와 올리는 바이트가 갈려 **403**이 된다 |
///
/// 아래 주석은 이 순서를 지키는 이유를 자리마다 다시 적는다. 한 줄만 옮겨도
/// 증상이 달라지는데, 두 증상 모두 **원인이 전혀 보이지 않는** 쪽이다.
///
/// ## `image_picker`의 축소 기능을 쓰지 않는다
///
/// `pickImage`에 `maxWidth`·`imageQuality`가 있지만 그쪽은 **회전을 픽셀에
/// 적용하지 않고**, 끝에 `ExifDataCopier`로 **GPS를 다시 붙인다**
/// (`image_picker_android`의 `ImageResizer.copyExif`). 둘 다 여기서 막으려는
/// 것이라 [ImageTransformer]로 따로 간다.
class GalleryPhotoPicker implements PhotoPicker {
  const GalleryPhotoPicker(this._transformer);

  final ImageTransformer _transformer;

  @override
  Future<PickedImage?> pick() async {
    final file = await picker.ImagePicker().pickImage(
      source: picker.ImageSource.gallery,
    );
    // 취소했다. 실패가 아니다.
    if (file == null) return null;

    return prepare(File(file.path));
  }

  /// 고른 파일을 **올릴 수 있는 한 장**으로 바꾼다.
  ///
  /// 앨범을 여는 것만 빼고 이 클래스가 하는 일 전부가 여기 있다. 앨범은
  /// 플랫폼 채널이라 테스트가 닿지 못하는데, **순서가 틀어지면 증상이 보이지
  /// 않는 자리**(사진이 눕거나 403)라 그물을 칠 곳이 필요하다.
  @visibleForTesting
  Future<PickedImage> prepare(File original) async {
    final path = await _prepared(original);

    // 조건에 맞지 않으면 여기서 던진다. 서버까지 보내고 400을 받는 것보다
    // 왕복 한 번을 아끼고, 무엇이 문제였는지 정확히 말해줄 수 있다.
    //
    // ⚠️ **바꾼 뒤의 파일을 잰다.** 서명은 이 크기로 받는다.
    return PickedImage.validated(
      path: path,
      sizeBytes: await File(path).length(),
    );
  }

  /// 올릴 파일을 만들고 그 경로를 돌려준다. **언제나 `.jpg`다.**
  ///
  /// 확장자가 곧 MIME 타입이다([PickedImage]). 원본 확장자를 물려주면
  /// JPEG 바이트에 `image/png` 서명을 받게 되고, S3가 403으로 돌려보낸다.
  ///
  /// ⚠️ **원본은 지운다.** 위치가 담긴 사본을 캐시에 남겨 둘 이유가 없다.
  /// 지우지 못해도 업로드는 계속한다 — 올릴 파일은 이미 깨끗하다.
  Future<String> _prepared(File original) async {
    // 1. 회전을 픽셀에 적용하고 줄인다. **메타데이터를 지우기 전이어야 한다** —
    //    회전 값은 EXIF에 있어서, 먼저 지우면 어느 쪽이 위였는지 알 수 없다.
    final transformed = await _transformer.toUploadJpeg(original.path);
    if (transformed == null) {
      // 알아보지 못했다. **원본으로 물러서지 않는다** — 누운 채로, 위치를 단
      // 채로 올라간다. 조용히 통과시키는 쪽이 더 나쁘다.
      throw const ProfileImageException(ProfileImageFailure.unsupportedFormat);
    }

    // 2. 메타데이터를 지운다. 변환기가 `keepExif: false`로 붙이지 않지만,
    //    위치는 한 번 새면 되돌릴 수 없어 보증을 두 겹으로 둔다.
    final Uint8List clean;
    try {
      clean = ExifStripper.strip(transformed);
    } on UnsupportedImageFormat {
      throw const ProfileImageException(ProfileImageFailure.unsupportedFormat);
    }

    final name = 'runiverse_profile_${DateTime.now().microsecondsSinceEpoch}';
    final copy = File('${Directory.systemTemp.path}/$name.jpg');
    await copy.writeAsBytes(clean, flush: true);

    try {
      await original.delete();
    } on Object {
      // 캐시 파일 하나가 남는 것뿐이다. 여기서 흐름을 멈출 이유가 없다.
    }

    return copy.path;
  }
}
