import 'dart:math' as math;

import 'package:runiverse/features/session/domain/geo_point.dart';

/// 선 아트의 점 하나. **`0~1`로 정규화된 값**이다.
///
/// ⚠️ `dart:ui`의 `Offset`을 쓰지 않는다 — `domain/`은 순수 Dart만 둔다
/// (CLAUDE.md). 그려 넣는 일은 `presentation/`이 한다.
class RoutePoint {
  const RoutePoint(this.x, this.y);

  /// 왼쪽이 `0`, 오른쪽이 `1`.
  final double x;

  /// **위가 `0`, 아래가 `1`이다.** 위도와 반대 방향이라 [normalizeRoute]가
  /// 뒤집어 넣는다.
  final double y;

  @override
  String toString() =>
      'RoutePoint(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// 지도 없이 그릴 달린 모양.
///
/// ## ⚠️ 배경이 없다
///
/// 기록카드는 경로를 지도 위에 긋지 않는다. **배경을 지우고 선만 남긴다.**
/// 그래야 공개한 카드에서도 그 선이 어디인지 알기 어렵고, 지도 패키지를 타지
/// 않아 키 없는 빌드에서도 그려진다
/// (`docs/specs/2026-11-16-record-card-design.md` 3절).
class RouteArt {
  const RouteArt({required this.strokes, required this.aspect});

  /// **서버가 `0~1`로 정규화해 보낸 경로.** 비는 받은 점에서 되찾는다.
  ///
  /// ## ⚠️ 서버가 비를 주지 않는다
  ///
  /// 응답에 가로/세로 비 필드가 없다(연동 가이드 2절). 그대로 상자에 늘려
  /// 그리면 모양이 찌그러진다 — [aspect]가 막으려던 바로 그것이다.
  ///
  /// **받은 점들의 바운딩 박스를 재면 두 경우가 한 규칙으로 덮인다.**
  ///
  /// | 서버가 한 일 | 짧은 축의 폭 | 이 함수가 내는 값 |
  /// |---|---|---|
  /// | 비를 보존해 정규화 | `1`보다 작다 | **실제 비** — 정확하다 |
  /// | 축마다 따로 늘림 | `1`에 닿는다 | `1.0` — 어차피 쓸 기본값 |
  ///
  /// 어느 쪽인지 **몰라도 되고, `1.0`보다 나쁠 수가 없다.** 그래서 백엔드 답을
  /// 기다리지 않는다.
  ///
  /// ## ⚠️ 서버는 `cos(위도)`를 곱하지 않는다 — **고치지 않기로 했다**
  ///
  /// 2026-11-24 기기에서 쟀다. 동서 360m · 남북 72m 코스(실측 비 `5.0`)를
  /// 저장하고 받은 값이 `xSpan=1.000 · ySpan=0.167 · aspect=5.99`였다. 도
  /// 단위로 그냥 잰 비가 `6.27`이고 실측이 `5.0`이니, **도를 그대로 쓴
  /// 쪽**이다(차이 4%는 서버가 10m로 리샘플하며 앞을 다듬은 몫이다).
  ///
  /// 그래서 한국에서 경로가 **동서로 약 1.26배 늘어난 채** 선다
  /// (cos 37.5° ≈ 0.793). **앱이 고칠 수 없다** — 응답에 좌표도 위도도 없고,
  /// 그게 루트 아트의 설계 의도다(설계 3절 — 어디를 뛰었는지 알기 어렵게).
  ///
  /// 사용자가 **보정 없이 가기로 정했다**(2026-11-24). 지도가 아니라 그림이고,
  /// 늘어난 비율이 일정해 카드끼리 견줄 때는 어긋나지 않는다. 다시 묻지 말 것.
  ///
  /// ## ⚠️ 조각마다 재지 않는다
  ///
  /// 전 조각을 **합쳐서** 잰다. 조각별로 재면 한 카드의 경로가 조각마다 다른
  /// 비로 그려져 모양이 어긋난다.
  factory RouteArt.fromNormalized(List<List<RoutePoint>> strokes) {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var seen = false;

    for (final stroke in strokes) {
      for (final point in stroke) {
        seen = true;
        if (point.x < minX) minX = point.x;
        if (point.x > maxX) maxX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.y > maxY) maxY = point.y;
      }
    }

    if (!seen) return empty;

    final width = maxX - minX;
    final height = maxY - minY;
    // ⚠️ **정규화 값이라 `_eps`를 쓰지 않는다.** 그쪽은 위경도 도 단위다.
    final flatX = width < _normalizedEps;
    final flatY = height < _normalizedEps;

    return RouteArt(
      strokes: strokes,
      // 한 점으로 뭉친 경로(트레드밀)는 `1.0`이다 — 0으로 나누지 않는다.
      aspect: flatX && flatY
          ? 1.0
          : flatY
          ? _flatAspect
          : flatX
          ? 1 / _flatAspect
          : width / height,
    );
  }

  /// 그릴 것이 없는 경로.
  static const empty = RouteArt(strokes: [], aspect: 1);

  /// 끊긴 데마다 갈라진 조각들. **조각 사이를 이으면 안 된다** — 일시정지로
  /// 끊긴 자리가 직선으로 이어져 가 본 적 없는 길이 생긴다.
  final List<List<RoutePoint>> strokes;

  /// 실세계 **가로/세로** 비. `cos(위도)` 보정이 끝난 값이다.
  ///
  /// [strokes]는 축마다 따로 `0~1`로 늘려 놓은 값이라 그 자체로는 모양을
  /// 모른다. 이 값이 있어야 [fitRoute]가 찌그러뜨리지 않고 앉힌다.
  final double aspect;

  bool get isEmpty => strokes.every((stroke) => stroke.isEmpty);

  bool get isNotEmpty => !isEmpty;
}

/// 한 축이 0에 가까운지 보는 기준. 위경도 도 단위다.
const _eps = 1e-9;

/// 같은 기준이지만 **이미 `0~1`로 정규화된 값**에 쓴다.
///
/// ⚠️ `_eps`(`1e-9`)를 그대로 쓰면 안 된다. 그쪽은 위경도 도 단위라, 정규화
/// 좌표에서는 거의 모든 경로가 "납작하지 않다"로 읽힌다.
const _normalizedEps = 1e-6;

/// 한 축이 납작할 때 쓰는 비. `100:1`이면 눈에는 선으로 보인다.
///
/// 0을 그대로 두면 [fitRoute]가 0으로 나눈다.
const _flatAspect = 100.0;

/// 위경도 조각들을 `0~1`로 옮긴다.
///
/// ## ⚠️ 경도에 `cos(위도)`를 곱한다
///
/// 경도 1도의 실제 거리는 위도 1도의 `cos(위도)`배다. 서울(37.5°)이면 약
/// **0.79배**라, 보정 없이 그리면 **동서로 1.26배 늘어난** 경로가 나온다.
///
/// ## ⚠️ 한 점으로 뭉친 경로를 견딘다
///
/// 트레드밀이나 GPS를 못 받은 러닝은 폭과 높이가 둘 다 0이다. 그대로 나누면
/// `NaN`이 되어 아무것도 안 그려진다. 그런 축은 **가운데(`0.5`)로 모은다.**
///
/// 빈 조각은 버린다 — 그릴 것이 없다.
RouteArt normalizeRoute(List<List<GeoPoint>> track) {
  var minLat = double.infinity;
  var maxLat = double.negativeInfinity;
  var minLon = double.infinity;
  var maxLon = double.negativeInfinity;
  var seen = false;

  for (final stroke in track) {
    for (final point in stroke) {
      seen = true;
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    }
  }

  if (!seen) return RouteArt.empty;

  final cosLat = math.cos((minLat + maxLat) / 2 * math.pi / 180);
  final realWidth = (maxLon - minLon) * cosLat;
  final realHeight = maxLat - minLat;

  final flatX = realWidth < _eps;
  final flatY = realHeight < _eps;

  final aspect = flatX && flatY
      ? 1.0
      : flatY
      ? _flatAspect
      : flatX
      ? 1 / _flatAspect
      : realWidth / realHeight;

  return RouteArt(
    strokes: [
      for (final stroke in track)
        if (stroke.isNotEmpty)
          [
            for (final point in stroke)
              RoutePoint(
                flatX ? 0.5 : (point.longitude - minLon) * cosLat / realWidth,
                // 위도는 위로 갈수록 커지고 화면 y는 아래로 갈수록 커진다.
                flatY ? 0.5 : 1 - (point.latitude - minLat) / realHeight,
              ),
          ],
    ],
    aspect: aspect,
  );
}

/// `0~1` 경로를 [width]×[height] 상자 안에 **가로세로 비를 지키며** 앉힌다.
///
/// 반환 좌표는 **픽셀**이다. 남는 쪽은 가운데로 민다.
///
/// [padding]이 상자보다 커도 터지지 않는다 — 폭이 0인 상자가 될 뿐이다.
List<List<RoutePoint>> fitRoute(
  RouteArt art, {
  required double width,
  required double height,
  required double padding,
}) {
  if (art.isEmpty) return const [];

  final boxWidth = math.max(width - padding * 2, 0.0);
  final boxHeight = math.max(height - padding * 2, 0.0);

  // 상자보다 납작한 경로는 가로에, 길쭉한 경로는 세로에 맞춘다.
  final boxAspect = boxHeight < _eps ? double.infinity : boxWidth / boxHeight;
  final fitByWidth = art.aspect >= boxAspect;

  final drawWidth = fitByWidth ? boxWidth : boxHeight * art.aspect;
  final drawHeight = fitByWidth
      ? (art.aspect <= 0 ? boxHeight : boxWidth / art.aspect)
      : boxHeight;

  final left = padding + (boxWidth - drawWidth) / 2;
  final top = padding + (boxHeight - drawHeight) / 2;

  return [
    for (final stroke in art.strokes)
      [
        for (final point in stroke)
          RoutePoint(left + point.x * drawWidth, top + point.y * drawHeight),
      ],
  ];
}
