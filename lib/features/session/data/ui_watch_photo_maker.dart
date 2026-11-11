import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:runiverse/features/profile/domain/cover_crop.dart';
import 'package:runiverse/features/session/domain/watch_photo_maker.dart';

/// `dart:ui`로 자르는 [WatchPhotoMaker]. 순서는 `UiImageCropper`와 같다.
///
/// ```
/// 받기 → 짧은 변 64로 풀기 → 가운데 정사각 → PNG → JPEG → base64
/// ```
///
/// 폰 사진 원이 `BoxFit.cover`로 가운데를 보여 주니 워치도 가운데를 자른다.
///
/// ## ⚠️ 사진은 아무것도 붙지 않은 [Dio]로 받는다
///
/// 서명 주소에 `Authorization`이 얹히면 S3가 403을 준다
/// (`HttpProfileImageRepository._uploadDio`와 같은 이유).
class UiWatchPhotoMaker implements WatchPhotoMaker {
  UiWatchPhotoMaker({Dio? dio}) : _dio = dio ?? Dio(_options);

  /// 워치가 받는 한 변. 정본은 워치 레포 `docs/phone-communication.md`의 `photos`다.
  ///
  /// 워치 화면의 사진(지름 약 50px)보다 조금 크게 잡는다. 128이면 사진 셋이 실린
  /// SYNCED가 애플워치 한 메시지 한도(64KB)를 넘을 수 있다.
  static const side = 64;

  /// `dio`의 기본값은 무제한 대기다. 카운트다운 30초 안에 끝나야 쓸모가 있다.
  static BaseOptions get _options => BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    responseType: ResponseType.bytes,
  );

  final Dio _dio;

  @override
  Future<String> jpegBase64(String url) async {
    final response = await _dio.get<List<int>>(url);
    final body = response.data;
    if (body == null || body.isEmpty) throw StateError('사진 본문이 비었다');

    // `dart:ui`는 PNG로만 내보낸다. 워치는 JPEG를 받아 한 번 더 바꾼다.
    final png = await _squarePng(Uint8List.fromList(body));
    final jpeg = await FlutterImageCompress.compressWithList(
      png,
      minWidth: side,
      minHeight: side,
      quality: 85,
      autoCorrectionAngle: false,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    return base64Encode(jpeg);
  }

  /// 가운데 정사각을 [side]×[side]로 그린 PNG.
  ///
  /// ⚠️ **실패해도 네이티브 자원을 놓는다.** 사진 한 장 크기의 메모리가 쌓인다.
  Future<Uint8List> _squarePng(Uint8List bytes) async {
    final source = await _decoded(bytes);
    try {
      final rect = CoverCrop.rect(
        width: source.width,
        height: source.height,
        aspectRatio: 1,
        alignY: 0,
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
        ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final ui.Image square;
      try {
        square = await picture.toImage(side, side);
      } finally {
        picture.dispose();
      }

      try {
        final png = await square.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw StateError('PNG로 못 바꿨다');
        return png.buffer.asUint8List();
      } finally {
        square.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  /// 짧은 변을 [side]로 줄여 푼다. 긴 변은 비율대로 따라온다 — 원본(짧은 변
  /// 1080)을 통째로 펼치지 않는다. 이미 작으면 키우지 않고 캔버스에서 늘린다.
  ///
  /// ⚠️ `instantiateImageCodecWithSize` 를 쓰지 않는다. 형식을 못 읽으면 버퍼를
  /// 놓지 않고 던진다(Flutter 3.44.8 `painting.dart` — `ImageDescriptor.encoded`
  /// 가 `try` 밖이다). 깨진 사진은 SYNC 마다 다시 받는다. 버퍼·설명자는 프레임을
  /// 꺼낸 뒤에 놓는다 — 설명자가 버퍼 메모리를 따로 잡아 둘의 순서는 상관없다.
  Future<ui.Image> _decoded(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final short = min(descriptor.width, descriptor.height);
        final wide = descriptor.width >= descriptor.height;
        final codec = await descriptor.instantiateCodec(
          targetWidth: short > side && !wide ? side : null,
          targetHeight: short > side && wide ? side : null,
        );
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}
