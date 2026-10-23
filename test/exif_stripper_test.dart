import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/domain/exif_stripper.dart';

/// EXIF 제거 — **위치가 새어 나가지 않는가.**
///
/// 프로필 사진 URL은 인증 없이 공개다. 갤러리 원본에는 촬영 위치가 담겨 있고,
/// presigned 업로드라 서버가 중간에서 못 지운다. 여기서 못 지우면 그대로 나간다.
///
/// 실제 사진 대신 **최소한의 컨테이너를 손으로 만든다.** 바이너리 픽스처를
/// 저장소에 넣으면 무엇을 검증하는지 읽히지 않는다.
void main() {
  group('JPEG', () {
    test('⚠️ APP1(EXIF)을 들어낸다', () {
      final stripped = ExifStripper.strip(
        _jpeg([
          _segment(0xE1, _exifPayload),
          _segment(0xDB, [1, 2, 3]),
        ]),
      );

      expect(_hasMarker(stripped, 0xE1), isFalse);
    });

    test('그림 데이터와 다른 마커는 남는다', () {
      final stripped = ExifStripper.strip(
        _jpeg([
          _segment(0xE1, _exifPayload),
          _segment(0xDB, [1, 2, 3]),
        ]),
      );

      // 양자화 테이블(DQT)이 없으면 그려지지 않는다.
      expect(_hasMarker(stripped, 0xDB), isTrue);
      // SOS 뒤 그림 데이터가 그대로 붙어 있다.
      expect(stripped.sublist(stripped.length - 4), [0xAA, 0xBB, 0xFF, 0xD9]);
    });

    test('APP0(JFIF)과 주석도 함께 지운다', () {
      // 위치가 담길 수 있는 자리를 전부 지운다. 그림에는 쓰이지 않는다.
      final stripped = ExifStripper.strip(
        _jpeg([
          _segment(0xE0, [1, 2]),
          _segment(0xFE, [3, 4]),
          _segment(0xDB, [5]),
        ]),
      );

      expect(_hasMarker(stripped, 0xE0), isFalse);
      expect(_hasMarker(stripped, 0xFE), isFalse);
      expect(_hasMarker(stripped, 0xDB), isTrue);
    });

    test('지울 것이 없으면 그림은 그대로다', () {
      final original = _jpeg([
        _segment(0xDB, [1, 2, 3]),
      ]);

      expect(ExifStripper.strip(original), original);
    });

    test('⚠️ 잘린 파일은 던진다', () {
      // 조용히 통과시키면 원본이 그대로 올라간다.
      expect(
        () => ExifStripper.strip(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1])),
        throwsA(isA<UnsupportedImageFormat>()),
      );
    });
  });

  group('PNG', () {
    test('⚠️ eXIf 청크를 들어낸다', () {
      final stripped = ExifStripper.strip(
        _png([
          _pngChunk('IHDR', [1, 2, 3]),
          _pngChunk('eXIf', _exifPayload),
          _pngChunk('IDAT', [9]),
          _pngChunk('IEND', const []),
        ]),
      );

      expect(_containsTag(stripped, 'eXIf'), isFalse);
      expect(_containsTag(stripped, 'IHDR'), isTrue);
      expect(_containsTag(stripped, 'IDAT'), isTrue);
      expect(_containsTag(stripped, 'IEND'), isTrue);
    });

    test('텍스트 청크도 지운다', () {
      // 편집기를 거치면 위치가 텍스트로 남기도 한다.
      final stripped = ExifStripper.strip(
        _png([
          _pngChunk('IHDR', [1]),
          _pngChunk('tEXt', [2]),
          _pngChunk('iTXt', [3]),
          _pngChunk('IEND', const []),
        ]),
      );

      expect(_containsTag(stripped, 'tEXt'), isFalse);
      expect(_containsTag(stripped, 'iTXt'), isFalse);
    });

    test('지울 것이 없으면 그대로다', () {
      final original = _png([
        _pngChunk('IHDR', [1]),
        _pngChunk('IEND', const []),
      ]);

      expect(ExifStripper.strip(original), original);
    });
  });

  group('WebP', () {
    test('⚠️ EXIF 청크를 들어낸다', () {
      final stripped = ExifStripper.strip(
        _webp([
          _riffChunk('VP8 ', [1, 2, 3, 4]),
          _riffChunk('EXIF', _exifPayload),
        ]),
      );

      expect(_containsTag(stripped, 'EXIF'), isFalse);
      expect(_containsTag(stripped, 'VP8 '), isTrue);
    });

    test('⚠️ RIFF 크기를 다시 적는다', () {
      // 크기를 그대로 두면 파일이 깨진 것으로 읽힌다.
      final stripped = ExifStripper.strip(
        _webp([
          _riffChunk('VP8 ', [1, 2, 3, 4]),
          _riffChunk('EXIF', _exifPayload),
        ]),
      );

      final declared =
          stripped[4] |
          (stripped[5] << 8) |
          (stripped[6] << 16) |
          (stripped[7] << 24);
      expect(declared, stripped.length - 8);
    });

    test('XMP도 지운다', () {
      final stripped = ExifStripper.strip(
        _webp([
          _riffChunk('VP8 ', [1, 2]),
          _riffChunk('XMP ', [3, 4]),
        ]),
      );

      expect(_containsTag(stripped, 'XMP '), isFalse);
    });
  });

  test('⚠️ 모르는 형식은 던진다', () {
    // 통과시키면 지우지 못한 채로 올라간다.
    expect(
      () => ExifStripper.strip(Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7])),
      throwsA(isA<UnsupportedImageFormat>()),
    );
  });
}

// ── 픽스처 ──────────────────────────────────────────────────

/// `Exif\0\0` 머리와 아무 값. 내용은 보지 않으므로 길이만 맞으면 된다.
const _exifPayload = [0x45, 0x78, 0x69, 0x66, 0, 0, 0x11, 0x22];

/// 마커 하나. 길이 필드는 자기 자신 2바이트를 포함한다.
List<int> _segment(int marker, List<int> payload) => [
  0xFF,
  marker,
  ((payload.length + 2) >> 8) & 0xFF,
  (payload.length + 2) & 0xFF,
  ...payload,
];

/// SOI + 세그먼트들 + SOS + 그림 데이터 + EOI.
Uint8List _jpeg(List<List<int>> segments) => Uint8List.fromList([
  0xFF,
  0xD8,
  for (final segment in segments) ...segment,
  ...[0xFF, 0xDA, 0x00, 0x02],
  ...[0xAA, 0xBB],
  ...[0xFF, 0xD9],
]);

List<int> _pngChunk(String tag, List<int> data) => [
  (data.length >> 24) & 0xFF,
  (data.length >> 16) & 0xFF,
  (data.length >> 8) & 0xFF,
  data.length & 0xFF,
  ...tag.codeUnits,
  ...data,
  // CRC는 검사하지 않는다. 자리만 채운다.
  0, 0, 0, 0,
];

Uint8List _png(List<List<int>> chunks) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  for (final chunk in chunks) ...chunk,
]);

List<int> _riffChunk(String tag, List<int> data) => [
  ...tag.codeUnits,
  data.length & 0xFF,
  (data.length >> 8) & 0xFF,
  (data.length >> 16) & 0xFF,
  (data.length >> 24) & 0xFF,
  ...data,
  // 홀수면 채움 1바이트.
  if (data.length.isOdd) 0,
];

Uint8List _webp(List<List<int>> chunks) {
  final body = [for (final chunk in chunks) ...chunk];
  final size = 4 + body.length;
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    size & 0xFF,
    (size >> 8) & 0xFF,
    (size >> 16) & 0xFF,
    (size >> 24) & 0xFF,
    ...'WEBP'.codeUnits,
    ...body,
  ]);
}

// ── 확인 도구 ────────────────────────────────────────────────

/// SOS 앞에서 [marker] 세그먼트를 만나는가.
bool _hasMarker(Uint8List bytes, int marker) {
  var i = 2;
  while (i + 3 < bytes.length) {
    if (bytes[i + 1] == 0xDA) return false;
    if (bytes[i + 1] == marker) return true;
    i += 2 + ((bytes[i + 2] << 8) | bytes[i + 3]);
  }
  return false;
}

bool _containsTag(Uint8List bytes, String tag) {
  final needle = tag.codeUnits;
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
