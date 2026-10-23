import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';

/// 고른 사진을 받아들일지 판단하는 규칙.
///
/// 여기서 정한 [PickedImage.mimeType]·[PickedImage.sizeBytes]가 **presigned URL의
/// 서명에 그대로 들어간다.** 값이 어긋나면 S3가 403을 주는데, 그때는 이미 요청이
/// 세 번 나간 뒤라 원인이 보이지 않는다. 그래서 여기서 잠근다.
void main() {
  ProfileImageFailure? failureOf(String path, {int size = 1024}) {
    try {
      PickedImage.validated(path: path, sizeBytes: size);
      return null;
    } on ProfileImageException catch (error) {
      return error.failure;
    }
  }

  group('형식', () {
    test('jpg · jpeg · png · webp를 받는다', () {
      expect(
        PickedImage.validated(path: '/a/b.jpg', sizeBytes: 10).mimeType,
        'image/jpeg',
      );
      expect(
        PickedImage.validated(path: '/a/b.jpeg', sizeBytes: 10).mimeType,
        'image/jpeg',
      );
      expect(
        PickedImage.validated(path: '/a/b.png', sizeBytes: 10).mimeType,
        'image/png',
      );
      expect(
        PickedImage.validated(path: '/a/b.webp', sizeBytes: 10).mimeType,
        'image/webp',
      );
    });

    test('대소문자를 가리지 않는다', () {
      // 안드로이드 갤러리가 `.JPG`로 주는 기기가 있다. 여기서 걸리면
      // 멀쩡한 사진이 "올릴 수 없는 형식"이 된다.
      expect(
        PickedImage.validated(path: '/a/IMG_0001.JPG', sizeBytes: 10).mimeType,
        'image/jpeg',
      );
    });

    test('⚠️ heic는 거절한다', () {
      // 아이폰 기본 형식이다. 서버가 셋만 받으므로 여기서 막지 않으면
      // 400을 받고 나서야 알게 된다.
      expect(failureOf('/a/b.heic'), ProfileImageFailure.unsupportedFormat);
    });

    test('gif와 확장자 없는 파일도 거절한다', () {
      expect(failureOf('/a/b.gif'), ProfileImageFailure.unsupportedFormat);
      expect(failureOf('/a/noext'), ProfileImageFailure.unsupportedFormat);
    });

    test('⚠️ 경로에 점이 있어도 마지막 점만 본다', () {
      // `/storage/emulated/0/My.Photos/x.png` 같은 경로가 실제로 온다.
      // 첫 점을 보면 `Photos/x.png`가 확장자가 되어 멀쩡한 png가 거절된다.
      expect(
        PickedImage.validated(
          path: '/storage/My.Photos/x.png',
          sizeBytes: 10,
        ).mimeType,
        'image/png',
      );
    });
  });

  group('크기', () {
    test('10MB까지 받는다', () {
      expect(
        PickedImage.validated(
          path: '/a/b.png',
          sizeBytes: PickedImage.maxBytes,
        ).sizeBytes,
        PickedImage.maxBytes,
      );
    });

    test('10MB를 1바이트라도 넘으면 거절한다', () {
      // 서버의 `@Max(10_485_760)`과 같은 경계를 쓴다. 어긋나면 앱은 통과시키고
      // 서버가 거절하는 값이 생긴다.
      expect(
        failureOf('/a/b.png', size: PickedImage.maxBytes + 1),
        ProfileImageFailure.tooLarge,
      );
    });

    test('⚠️ 0바이트도 거절한다', () {
      // 서버가 `@Min(1)`로 막는다. 빈 파일은 실제로 존재한다 —
      // 다운로드가 끊긴 자리에 껍데기만 남은 경우다.
      expect(failureOf('/a/b.png', size: 0), ProfileImageFailure.tooLarge);
    });
  });
}
