import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/widgets/profile_photo_image.dart';

/// 프로필 사진 캐시 — **같은 사진을 몇 번 내려받는가.**
///
/// 서버는 조회할 때마다 새 서명 URL을 준다. 경로는 같고 `?` 뒤만 달라지는데,
/// 캐시 키를 URL 전체로 두면 **같은 사진을 매번 다시 받는다.** 사진이 한참 뒤에
/// 뜨던 이유의 한 축이다.
void main() {
  const path = 'https://cdn.test/profile/abc.jpg';
  const signed = '$path?X-Amz-Date=20261014T030000Z&X-Amz-Signature=9f1c';
  const resigned = '$path?X-Amz-Date=20261014T040000Z&X-Amz-Signature=7b2e';

  group('캐시 키', () {
    test('⚠️ 서명이 바뀌어도 키는 같다', () {
      expect(
        ProfilePhotoImage.cacheKeyOf(signed),
        ProfilePhotoImage.cacheKeyOf(resigned),
      );
    });

    test('서명을 뗀 경로다', () {
      expect(ProfilePhotoImage.cacheKeyOf(signed), path);
    });

    test('⚠️ 다른 사람의 사진과는 갈린다', () {
      // 경로만 쓴다고 전부 한 칸에 몰아넣으면 남의 얼굴이 뜬다.
      expect(
        ProfilePhotoImage.cacheKeyOf('https://cdn.test/profile/zzz.jpg?a=1'),
        isNot(ProfilePhotoImage.cacheKeyOf(signed)),
      );
    });

    test('서명이 없는 주소도 그대로 쓴다', () {
      expect(ProfilePhotoImage.cacheKeyOf(path), path);
    });

    test('캐시에 넣을 때 쓰는 값이 그 키다', () async {
      // `cacheKeyOf`만 맞고 `obtainKey`가 URL을 돌려주면 아무것도 달라지지 않는다.
      final key = await const ProfilePhotoImage(
        signed,
      ).obtainKey(ImageConfiguration.empty);

      expect(key, path);
    });
  });

  group('같은 provider인가', () {
    test('⚠️ 주소가 바뀌면 다른 provider다', () {
      // 여기까지 같다고 하면, 처음 받기에 실패한 사진이 새 주소를 받아도
      // **영영 다시 시도하지 않는다.** 캐시 키와 기준이 달라야 하는 이유다.
      expect(
        const ProfilePhotoImage(signed),
        isNot(const ProfilePhotoImage(resigned)),
      );
    });

    test('같은 주소면 같은 provider다', () {
      expect(const ProfilePhotoImage(signed), const ProfilePhotoImage(signed));
    });
  });

  group('줄여서 디코딩', () {
    testWidgets('⚠️ 기기 픽셀 비를 곱한 너비로 감싼다', (tester) async {
      // 논리 픽셀을 그대로 주면 고해상도 기기에서 흐릿해진다.
      late ImageProvider<Object> provider;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 3),
          child: Builder(
            builder: (context) {
              provider = profilePhoto(context, signed, 88);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, 264);
    });

    testWidgets('안쪽은 캐시 키를 가진 그 provider다', (tester) async {
      late ImageProvider<Object> provider;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1),
          child: Builder(
            builder: (context) {
              provider = profilePhoto(context, signed, 28);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        (provider as ResizeImage).imageProvider,
        const ProfilePhotoImage(signed),
      );
    });
  });
}
