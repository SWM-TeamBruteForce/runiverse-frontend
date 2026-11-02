/// 커버 칸에 **보이는 부분**을 사진의 픽셀 자리로 낸다.
///
/// ## ⚠️ Flutter가 그리는 것과 같은 셈이어야 한다
///
/// 미리보기는 `BoxFit.cover`와 `Alignment(0, alignY)`로 그린다. 여기서 다르게
/// 자르면 **보던 것과 다른 그림이 올라간다.** 그래서 같은 셈을 한다 — 칸 비율에
/// 맞춰 넘치는 쪽을 덜어 내고, 넘친 만큼에 `(alignY + 1) / 2`를 곱한 자리에서
/// 시작한다.
///
/// 칸보다 납작한 사진(가로로 넘친다)은 **언제나 가운데다.** 위아래만 옮긴다.
abstract final class CoverCrop {
  const CoverCrop._();

  /// 커버 비율(시안 412×200). `ProfileCover`·`BackgroundPicker`와 같은 값이다.
  static const aspectRatio = 412 / 200;

  /// [width]×[height] 사진에서 [aspectRatio](폭/높이)만큼 남길 자리.
  ///
  /// [alignY]는 -1(맨 위)부터 1(맨 아래)까지다. 밖의 값은 끝으로 붙인다.
  static ({int left, int top, int width, int height}) rect({
    required int width,
    required int height,
    required double aspectRatio,
    required double alignY,
  }) {
    final align = alignY.clamp(-1.0, 1.0);
    if (width / height < aspectRatio) {
      // 세로로 넘친다. 폭을 다 쓰고 높이를 덜어 낸다.
      final cropHeight = (width / aspectRatio).round().clamp(1, height);
      final top = ((height - cropHeight) * (align + 1) / 2).round();
      return (left: 0, top: top, width: width, height: cropHeight);
    }
    // 가로로 넘치거나 꼭 맞는다. 높이를 다 쓰고 가운데를 남긴다.
    final cropWidth = (height * aspectRatio).round().clamp(1, width);
    final left = ((width - cropWidth) / 2).round();
    return (left: left, top: 0, width: cropWidth, height: height);
  }
}
