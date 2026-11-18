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
    test('⚠️ alignY는 아무것도 바꾸지 않는다', () {
      // 높이를 다 쓰므로 위아래로 옮길 것이 없다. 좌우는 [alignX]가 고른다.
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

  /// 9:16 틀 — 기록카드 사진이다.
  ///
  /// ## ⚠️ 여기서는 **좌우로** 밀어야 한다
  ///
  /// 커버(412:200)는 가로로 넓어 사진이 위아래로 넘쳤다. 9:16은 세로로 길어
  /// **4:3이든 3:4든 실제 사진은 거의 다 좌우로 넘친다** — [alignY]로는 손댈
  /// 데가 없다. 그래서 [CoverCrop.rect]가 [alignX]를 받는다.
  group('9:16 틀에서 가로로 넘치는 사진', () {
    // 1600×900을 9:16에 앉히면 폭 506만 남고 1094가 넘친다.
    ({int left, int top, int width, int height}) landscape(double alignX) =>
        CoverCrop.rect(
          width: 1600,
          height: 900,
          aspectRatio: 9 / 16,
          alignX: alignX,
          alignY: 0,
        );

    test('높이를 다 쓰고 9:16만큼 남긴다', () {
      final rect = landscape(0);

      expect(rect.width, 506);
      expect(rect.height, 900);
      expect(rect.top, 0);
    });

    test('왼쪽 끝(-1)이면 왼쪽에서 시작한다', () {
      expect(landscape(-1).left, 0);
    });

    test('오른쪽 끝(1)이면 오른쪽에 붙는다', () {
      expect(landscape(1).left, 1600 - 506);
    });

    test('⚠️ 기본값은 오늘의 가운데와 같은 값이다', () {
      // 프로필 커버와 워치 사진이 이 기본값으로 돈다. 달라지면 두 화면이
      // 조용히 다른 데를 자른다.
      final byDefault = CoverCrop.rect(
        width: 1600,
        height: 900,
        aspectRatio: 9 / 16,
        alignY: 0,
      );

      expect(byDefault.left, ((1600 - 506) / 2).round());
      expect(byDefault.left, landscape(0).left);
    });

    test('⚠️ 범위 밖의 값은 끝으로 붙인다', () {
      expect(landscape(-9).left, 0);
      expect(landscape(9).left, 1600 - 506);
    });
  });

  test('9:16 틀에서 세로로 넘치는 사진은 alignX를 무시한다', () {
    // 900×1900은 9:16(0.5625)보다 홀쭉하다 — 폭을 다 쓰므로 좌우로 옮길 것이
    // 없다. 스크린숏이 이 꼴이다.
    final rect = CoverCrop.rect(
      width: 900,
      height: 1900,
      aspectRatio: 9 / 16,
      alignX: 1,
      alignY: 0,
    );

    expect(rect.left, 0);
    expect(rect.width, 900);
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
