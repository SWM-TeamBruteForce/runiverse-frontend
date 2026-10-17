import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/data/gallery_photo_picker.dart';
import 'package:runiverse/features/profile/domain/image_transformer.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';

/// 앨범에서 고른 사진을 **올릴 수 있는 한 장으로 바꾸는 자리.**
///
/// 여기서 틀어지면 둘 중 하나가 되는데, 둘 다 **원인이 보이지 않는** 쪽이다.
///
/// | 틀어진 것 | 증상 |
/// |---|---|
/// | 회전을 메타데이터 제거 **뒤에** 하면 | 사진이 누워서 올라간다. 되돌릴 방법이 없다 |
/// | 크기를 바꾸기 **전에** 재면 | S3가 403. 서명과 실제 바이트가 다르다 |
///
/// 앨범을 여는 것은 플랫폼 채널이라 여기서 못 부른다. 그 한 줄을 뺀 나머지
/// 전부가 `prepare`에 있다.
void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('picker_test');
  });

  tearDown(() async {
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  /// 고른 셈 치는 원본 파일.
  Future<File> original({String name = 'IMG_0001.heic', int size = 5600000}) {
    final file = File('${workspace.path}/$name');
    return file.writeAsBytes(Uint8List(size), flush: true);
  }

  test('⚠️ 바꾼 뒤의 크기를 잰다', () async {
    // 서명은 이 값으로 받는다. 원본(5.6MB)으로 받으면 올릴 때 403이다.
    final transformer = _FakeTransformer(jpegOf(1234));
    final picked = await GalleryPhotoPicker(
      transformer,
    ).prepare(await original());

    expect(picked.sizeBytes, isNot(5600000));
    expect(picked.sizeBytes, await File(picked.path).length());
  });

  test('⚠️ 회전을 적용한 뒤에 메타데이터를 지운다', () async {
    // 순서가 뒤집히면 회전 값이 EXIF와 함께 사라져 **사진이 눕는다.**
    // 변환기에 넘어온 것이 원본 경로여야 그 순서다.
    final transformer = _FakeTransformer(jpegOf(100));
    final source = await original();

    await GalleryPhotoPicker(transformer).prepare(source);

    expect(transformer.received, source.path);
  });

  test('⚠️ 변환기가 붙여 보낸 EXIF도 지운다', () async {
    // `keepExif: false`를 믿지 않는다. 다시 저장할 때 EXIF를 그대로 붙이는
    // 구현이 실제로 있다(`image_picker`의 `ExifDataCopier`가 GPS를 복사한다).
    // 프로필 사진 URL은 인증 없이 공개라 한 번 새면 되돌릴 수 없다.
    final withGps = jpegOf(0, segments: [_segment(0xE1, _gpsPayload)]);
    final picked = await GalleryPhotoPicker(
      _FakeTransformer(withGps),
    ).prepare(await original());

    final uploaded = await File(picked.path).readAsBytes();
    expect(_hasMarker(uploaded, 0xE1), isFalse);
    expect(_contains(uploaded, _gpsPayload), isFalse);
  });

  test('언제나 jpg로 내보낸다', () async {
    // 확장자가 곧 MIME 타입이다. JPEG 바이트에 `image/png` 서명을 받으면 403이다.
    final picked = await GalleryPhotoPicker(
      _FakeTransformer(jpegOf(10)),
    ).prepare(await original(name: 'shot.png'));

    expect(picked.path, endsWith('.jpg'));
    expect(picked.mimeType, 'image/jpeg');
  });

  test('HEIC도 올라간다 — 네이티브가 읽어 JPEG로 내보낸다', () async {
    // 전에는 확장자만 보고 고르는 자리에서 막았다.
    final picked = await GalleryPhotoPicker(
      _FakeTransformer(jpegOf(10)),
    ).prepare(await original(name: 'IMG_0002.HEIC'));

    expect(picked.mimeType, 'image/jpeg');
  });

  test('10MB가 넘는 원본도 올라간다 — 줄여서 올린다', () async {
    final picked = await GalleryPhotoPicker(
      _FakeTransformer(jpegOf(300000)),
    ).prepare(await original(size: 12 * 1024 * 1024));

    expect(picked.sizeBytes, lessThan(10 * 1024 * 1024));
  });

  test('⚠️ 못 알아본 사진은 원본으로 물러서지 않는다', () async {
    // 물러서면 누운 채로, 위치를 단 채로 올라간다.
    final source = await original();

    expect(
      () => GalleryPhotoPicker(_FakeTransformer(null)).prepare(source),
      throwsA(
        isA<ProfileImageException>().having(
          (e) => e.failure,
          'failure',
          ProfileImageFailure.unsupportedFormat,
        ),
      ),
    );
  });

  test('원본은 지운다 — 위치가 담긴 사본을 남기지 않는다', () async {
    final source = await original();

    await GalleryPhotoPicker(_FakeTransformer(jpegOf(10))).prepare(source);

    expect(source.existsSync(), isFalse);
  });
}

/// 변환기가 돌려줄 바이트를 정해 두는 가짜.
class _FakeTransformer implements ImageTransformer {
  _FakeTransformer(this.result);

  /// `null`이면 알아보지 못한 것이다.
  final Uint8List? result;

  /// 무엇을 받았는가. **원본 경로여야 한다** — 지우기 전이라는 뜻이다.
  String? received;

  @override
  Future<Uint8List?> toUploadJpeg(
    String path, {
    int shortEdge = 1080,
    int quality = 85,
  }) async {
    received = path;
    return result;
  }
}

/// 세그먼트 + 그림 데이터로 [padding]바이트쯤 되는 JPEG.
Uint8List jpegOf(int padding, {List<List<int>> segments = const []}) =>
    Uint8List.fromList([
      0xFF,
      0xD8,
      for (final segment in segments) ...segment,
      ...[0xFF, 0xDA, 0x00, 0x02],
      ...List.filled(padding, 0x11),
      ...[0xFF, 0xD9],
    ]);

/// 위치가 담긴 EXIF인 셈 친다.
const _gpsPayload = [0x45, 0x78, 0x69, 0x66, 0, 0, 0x37, 0x50, 0x12, 0x70];

List<int> _segment(int marker, List<int> payload) => [
  0xFF,
  marker,
  ((payload.length + 2) >> 8) & 0xFF,
  (payload.length + 2) & 0xFF,
  ...payload,
];

bool _hasMarker(Uint8List bytes, int marker) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0xFF && bytes[i + 1] == marker) return true;
    // SOS 뒤는 그림 데이터라 마커처럼 보이는 바이트가 마커가 아니다.
    if (bytes[i] == 0xFF && bytes[i + 1] == 0xDA) return false;
  }
  return false;
}

bool _contains(Uint8List bytes, List<int> needle) {
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    var hit = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}
