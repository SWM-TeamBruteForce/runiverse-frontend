import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/domain/cover_crop.dart';

/// 커버 자르기 — **미리보기에 보이던 부분과 같은가.**
///
/// 미리보기는 `BoxFit.cover` + `Alignment(0, alignY)`로 그린다. 여기 셈이 그것과
/// 다르면 보던 것과 다른 그림이 올라간다.
void main() {
  // 9:16 세로 사진. 칸(412:200)에 맞추면 높이 524가 남는다.
  ({int left, int top, int width, int height}) portrait(double alignY) =>
      CoverCrop.rect(
        width: 1080,
        height: 1920,
        aspectRatio: CoverCrop.aspectRatio,
        alignY: alignY,
      );

  group('세로로 넘치는 사진', () {
    test('폭을 다 쓰고 칸 비율만큼 남긴다', () {
      final rect = portrait(0);

      expect(rect.width, 1080);
      expect(rect.height, 524);
    });

    test('가운데(0)면 위아래를 똑같이 덜어 낸다', () {
      expect(portrait(0).top, (1920 - 524) ~/ 2);
    });

    test('맨 위(-1)면 위에서 시작한다', () {
      expect(portrait(-1).top, 0);
    });

    test('맨 아래(1)면 아래에 붙는다', () {
      expect(portrait(1).top, 1920 - 524);
    });

    test('⚠️ 범위 밖의 값은 끝으로 붙인다', () {
      // 넘치면 사진 밖을 자르게 된다.
      expect(portrait(-3).top, 0);
      expect(portrait(3).top, 1920 - 524);
    });
  });

  group('칸보다 납작한 사진', () {
    test('⚠️ 위치와 상관없이 가운데를 남긴다', () {
      // 위아래만 옮긴다. 가로로 넘치는 사진은 옮길 것이 없다.
      final rect = CoverCrop.rect(
        width: 3000,
        height: 1000,
        aspectRatio: CoverCrop.aspectRatio,
        alignY: 1,
      );

      expect(rect.height, 1000);
      expect(rect.width, 2060);
      expect(rect.left, (3000 - 2060) ~/ 2);
      expect(rect.top, 0);
    });
  });

  test('칸과 같은 비율이면 그대로 둔다', () {
    final rect = CoverCrop.rect(
      width: 824,
      height: 400,
      aspectRatio: CoverCrop.aspectRatio,
      alignY: 0.5,
    );

    expect(rect, (left: 0, top: 0, width: 824, height: 400));
  });
}
