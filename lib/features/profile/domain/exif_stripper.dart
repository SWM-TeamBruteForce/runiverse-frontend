import 'dart:typed_data';

/// 이미지에서 메타데이터를 걷어낸다.
///
/// ## 왜 필요한가
///
/// 프로필 사진 URL은 **인증 없이 공개**다. 갤러리 원본을 그대로 올리면 촬영
/// 위치 GPS가 EXIF에 담겨 함께 올라간다. presigned 업로드라 서버가 중간에서
/// 지울 수 없어, **앱이 올리기 전에 지우는 것이 유일한 지점**이다.
///
/// ## 다시 인코딩하지 않는다
///
/// 디코딩 후 재인코딩하면 EXIF가 통째로 사라지지만, 10MB 사진을 풀면 메모리가
/// 크게 뛰고 화질도 변한다. 여기서는 **컨테이너만 걸어가며 메타데이터 구간을
/// 들어낸다.** 픽셀 바이트는 그대로다.
///
/// ## ⚠️ 못 읽으면 던진다
///
/// 형식을 알아보지 못했을 때 원본을 그대로 통과시키면 막으려던 GPS가 그대로
/// 나간다. **조용히 통과시키는 쪽이 더 나쁘다.**
abstract final class ExifStripper {
  const ExifStripper._();

  /// [bytes]에서 메타데이터를 뺀 새 바이트.
  ///
  /// 뺄 것이 없으면 [bytes]를 그대로 돌려준다.
  /// 형식을 알아보지 못하면 [UnsupportedImageFormat]을 던진다.
  static Uint8List strip(Uint8List bytes) {
    if (_isJpeg(bytes)) return _stripJpeg(bytes);
    if (_isPng(bytes)) return _stripPng(bytes);
    if (_isWebp(bytes)) return _stripWebp(bytes);
    throw const UnsupportedImageFormat();
  }

  // ── 알아보기 ──────────────────────────────────────────────

  static bool _isJpeg(Uint8List b) =>
      b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8;

  static const _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  static bool _isPng(Uint8List b) {
    if (b.length < _pngMagic.length) return false;
    for (var i = 0; i < _pngMagic.length; i++) {
      if (b[i] != _pngMagic[i]) return false;
    }
    return true;
  }

  static bool _isWebp(Uint8List b) =>
      b.length >= 12 && _tagAt(b, 0) == 'RIFF' && _tagAt(b, 8) == 'WEBP';

  // ── JPEG ─────────────────────────────────────────────────

  /// APP0~APP15와 COM을 들어낸다.
  ///
  /// EXIF는 APP1(`FFE1`)에 있지만 XMP도 APP1, IPTC는 APP13에 온다. 위치가
  /// 담길 수 있는 자리를 전부 지우는 편이 안전하고, 이 구간들은 그림을
  /// 그리는 데 쓰이지 않는다.
  ///
  /// ⚠️ **JFIF(APP0)도 함께 지운다.** 해상도 정보뿐이라 없어도 그려진다.
  ///
  /// `FFDA`(SOS)를 만나면 그 뒤는 압축된 그림 데이터라 그대로 붙인다 —
  /// 여기서부터는 마커처럼 보이는 바이트가 실제 마커가 아니다.
  static Uint8List _stripJpeg(Uint8List bytes) {
    final out = BytesBuilder(copy: false)..add([0xFF, 0xD8]);
    var i = 2;

    while (i + 3 < bytes.length) {
      if (bytes[i] != 0xFF) throw const UnsupportedImageFormat();

      final marker = bytes[i + 1];

      // 채움 바이트. 마커 앞에 0xFF가 여러 개 올 수 있다.
      if (marker == 0xFF) {
        i++;
        continue;
      }

      // SOS부터 끝까지는 그림 데이터다. 더 걷지 않는다.
      if (marker == 0xDA) {
        out.add(Uint8List.sublistView(bytes, i));
        return out.toBytes();
      }

      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      // 길이는 자기 자신 2바이트를 포함한다. 2보다 작으면 깨진 파일이다.
      if (length < 2 || i + 2 + length > bytes.length) {
        throw const UnsupportedImageFormat();
      }

      final isMetadata = (marker >= 0xE0 && marker <= 0xEF) || marker == 0xFE;
      if (!isMetadata) {
        out.add(Uint8List.sublistView(bytes, i, i + 2 + length));
      }
      i += 2 + length;
    }

    throw const UnsupportedImageFormat();
  }

  // ── PNG ──────────────────────────────────────────────────

  /// `eXIf`·`tEXt`·`iTXt`·`zTXt` 청크를 들어낸다.
  ///
  /// 카메라 PNG는 드물지만 편집기를 거치면 위치가 텍스트 청크로 남기도 한다.
  static const _pngDropped = {'eXIf', 'tEXt', 'iTXt', 'zTXt'};

  static Uint8List _stripPng(Uint8List bytes) {
    final out = BytesBuilder(copy: false)..add(_pngMagic);
    var i = _pngMagic.length;

    while (i + 8 <= bytes.length) {
      final length = _uint32BigEndian(bytes, i);
      // 길이 4 + 태그 4 + 데이터 + CRC 4.
      final end = i + 12 + length;
      if (end > bytes.length) throw const UnsupportedImageFormat();

      final tag = _tagAt(bytes, i + 4);
      if (!_pngDropped.contains(tag)) {
        out.add(Uint8List.sublistView(bytes, i, end));
      }
      i = end;

      // IEND 뒤에는 아무것도 없다.
      if (tag == 'IEND') return out.toBytes();
    }

    throw const UnsupportedImageFormat();
  }

  // ── WebP ─────────────────────────────────────────────────

  /// `EXIF`·`XMP ` 청크를 들어낸다.
  ///
  /// ⚠️ **RIFF 헤더의 크기를 다시 적어야 한다.** 청크만 빼고 크기를 그대로
  /// 두면 파일이 깨진 것으로 읽힌다.
  static const _webpDropped = {'EXIF', 'XMP '};

  static Uint8List _stripWebp(Uint8List bytes) {
    final body = BytesBuilder(copy: false);
    // RIFF(4) + 크기(4) + WEBP(4) 다음부터 청크가 이어진다.
    var i = 12;

    while (i + 8 <= bytes.length) {
      final size = _uint32LittleEndian(bytes, i + 4);
      // 청크는 짝수 경계에 맞춰 채움 1바이트가 붙는다.
      final padded = size + (size.isOdd ? 1 : 0);
      final end = i + 8 + padded;
      if (end > bytes.length) throw const UnsupportedImageFormat();

      final tag = _tagAt(bytes, i);
      if (!_webpDropped.contains(tag)) {
        body.add(Uint8List.sublistView(bytes, i, end));
      }
      i = end;
    }

    final chunks = body.toBytes();
    final out = Uint8List(12 + chunks.length);
    out.setRange(0, 12, bytes);
    // 크기는 이 필드 뒤부터 끝까지다 — `WEBP` 4바이트가 포함된다.
    _writeUint32LittleEndian(out, 4, 4 + chunks.length);
    out.setRange(12, out.length, chunks);
    return out;
  }

  // ── 읽기 도구 ─────────────────────────────────────────────

  static String _tagAt(Uint8List b, int at) =>
      String.fromCharCodes(b, at, at + 4);

  static int _uint32BigEndian(Uint8List b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static int _uint32LittleEndian(Uint8List b, int at) =>
      b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

  static void _writeUint32LittleEndian(Uint8List b, int at, int value) {
    b[at] = value & 0xFF;
    b[at + 1] = (value >> 8) & 0xFF;
    b[at + 2] = (value >> 16) & 0xFF;
    b[at + 3] = (value >> 24) & 0xFF;
  }
}

/// 알아보지 못한 이미지. **원본을 그대로 올리지 않기 위해 던진다.**
class UnsupportedImageFormat implements Exception {
  const UnsupportedImageFormat();

  @override
  String toString() => 'UnsupportedImageFormat';
}
