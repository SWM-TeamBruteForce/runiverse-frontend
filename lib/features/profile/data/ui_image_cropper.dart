import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:runiverse/features/profile/domain/cover_crop.dart';
import 'package:runiverse/features/profile/domain/exif_stripper.dart';
import 'package:runiverse/features/profile/domain/image_cropper.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';

/// `dart:ui`로 자르는 [ImageCropper].
///
/// ## 통째로 펼쳐도 된다
///
/// 받는 것은 원본이 아니라 `GalleryPhotoPicker`가 이미 줄인 JPEG(짧은 변
/// 1080)다. 1080×1920이면 펼쳐도 약 8MB라, `ImageTransformer`가 경계하는
/// 190MB와는 다르다.
///
/// ## ⚠️ 순서는 고를 때와 같다
///
/// ```
/// 자르기 → JPEG로 저장 → 메타데이터 제거 → 크기 측정
/// ```
///
/// `dart:ui`는 PNG로만 내보낸다. 올리는 것은 언제나 JPEG여야 해서
/// (`CompressedImageTransformer`) 한 번 더 바꾼다. 측정은 맨 끝이다 — 서명은
/// 이 크기로 받는다.
///
/// ## ⚠️ 받은 파일을 지우지 않는다
///
/// 저장이 실패하면 화면은 같은 [PickedImage]를 들고 있다가 다시 보낸다. 여기서
/// 지우면 **다시 누른 저장이 읽을 파일이 없다.** 위치 정보는 고를 때 이미
/// 걷어 냈다.
class UiImageCropper implements ImageCropper {
  const UiImageCropper();

  @override
  Future<PickedImage> crop(
    PickedImage image, {
    required double aspectRatio,
    required double alignY,
  }) async {
    try {
      final path = await _cropped(
        image.path,
        aspectRatio: aspectRatio,
        alignY: alignY,
      );
      // ⚠️ **잘라 낸 파일을 잰다.** 서명은 이 크기로 받는다.
      return PickedImage.validated(
        path: path,
        sizeBytes: await File(path).length(),
      );
    } on ProfileImageException {
      rethrow;
    } on FileSystemException {
      // 고른 파일이 사라졌다 — 오래 백그라운드에 두면 OS가 임시 폴더를 비운다.
      // **형식 탓이 아니다.** 형식이라고 하면 다른 사진을 고르게 된다. 올리는
      // 자리(`HttpProfileImageRepository.upload`)와 같은 실패로 말한다.
      throw const ProfileImageException(ProfileImageFailure.upload);
    } on Object {
      // 파일을 못 읽었거나 디코더가 거절했다. 자르지 않은 채로 물러서지 않는다.
      throw const ProfileImageException(ProfileImageFailure.unsupportedFormat);
    }
  }

  @override
  Future<void> discard(PickedImage cropped) async {
    try {
      await File(cropped.path).delete();
    } on Object {
      // 임시 파일 하나가 남는 것뿐이다.
    }
  }

  Future<String> _cropped(
    String path, {
    required double aspectRatio,
    required double alignY,
  }) async {
    // 1. 자른다. 크기는 그대로다 — 줄이는 일은 고를 때 끝났다.
    final (:png, :width, :height) = await _croppedPng(
      path,
      aspectRatio: aspectRatio,
      alignY: alignY,
    );

    // 2. JPEG로 바꾼다. `minWidth`·`minHeight`를 자른 크기로 준다 — 플러그인은
    //    이 값보다 작게 줄이지 않으므로 크기가 그대로 남는다.
    final jpeg = await FlutterImageCompress.compressWithList(
      png.buffer.asUint8List(),
      minWidth: width,
      minHeight: height,
      quality: 85,
      autoCorrectionAngle: false,
      keepExif: false,
      format: CompressFormat.jpeg,
    );

    // 3. 메타데이터를 지운다. PNG에서 왔으니 붙을 것이 없지만, 고를 때와 같은
    //    보증을 둔다.
    final Uint8List clean = ExifStripper.strip(jpeg);

    final name = 'runiverse_cover_${DateTime.now().microsecondsSinceEpoch}';
    final copy = File('${Directory.systemTemp.path}/$name.jpg');
    await copy.writeAsBytes(clean, flush: true);
    return copy.path;
  }

  /// 커버 칸만큼 잘라 낸 PNG와 그 크기.
  ///
  /// ⚠️ **실패해도 네이티브 자원을 놓는다.** 저장은 다시 누를 수 있어서, 놓지
  /// 않으면 실패할 때마다 사진 한 장 크기의 메모리가 쌓인다.
  Future<({ByteData png, int width, int height})> _croppedPng(
    String path, {
    required double aspectRatio,
    required double alignY,
  }) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    final ui.Image source;
    try {
      source = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }

    try {
      final rect = CoverCrop.rect(
        width: source.width,
        height: source.height,
        aspectRatio: aspectRatio,
        alignY: alignY,
      );

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        source,
        ui.Rect.fromLTWH(
          rect.left.toDouble(),
          rect.top.toDouble(),
          rect.width.toDouble(),
          rect.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, rect.width.toDouble(), rect.height.toDouble()),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final ui.Image cropped;
      try {
        cropped = await picture.toImage(rect.width, rect.height);
      } finally {
        picture.dispose();
      }

      try {
        final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) {
          throw const ProfileImageException(
            ProfileImageFailure.unsupportedFormat,
          );
        }
        return (png: png, width: rect.width, height: rect.height);
      } finally {
        cropped.dispose();
      }
    } finally {
      source.dispose();
    }
  }
}
