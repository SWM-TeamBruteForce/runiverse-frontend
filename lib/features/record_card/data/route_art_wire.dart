import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 서버가 보낸 `routeArt`를 [RouteArt]로. 달력(7-1)과 상세(8-1)가 같이 쓴다.
///
/// 모양은 **조각 배열의 배열**이고 점은 `[x, y]` 두 칸, 값은 `0~1`이다.
/// 달력은 최대 50점, 상세는 합쳐 200점쯤 온다(연동 가이드 2절).
///
/// ## ⚠️ y를 뒤집지 않는다
///
/// `normalizeRoute`는 위도를 받아 뒤집어 넣지만, 서버는 **이미 화면
/// 방향**(아래로 증가)으로 준다. 한 번 더 뒤집으면 경로가 상하로 거울이 된다.
///
/// ## ⚠️ 조각 사이를 잇지 않는다
///
/// 일시정지로 끊긴 자리가 직선으로 이어지면 **가 본 적 없는 길**이 생긴다.
/// 조각을 따로 담는 것이 그것을 막는다.
///
/// ## ⚠️ 깨진 점만 버린다
///
/// 한 점의 모양이 이상해도 **그 점만** 버린다. 경로 전체를 날리면 멀쩡한
/// 카드가 달력에서 점 하나로 주저앉는다.
RouteArt routeArtFrom(Object? wire) {
  if (wire is! List) return RouteArt.empty;

  final strokes = <List<RoutePoint>>[];
  for (final stroke in wire) {
    if (stroke is! List) continue;
    final points = <RoutePoint>[];
    for (final point in stroke) {
      if (point is! List || point.length < 2) continue;
      final x = point[0];
      final y = point[1];
      if (x is! num || y is! num) continue;
      points.add(RoutePoint(x.toDouble(), y.toDouble()));
    }
    // 빈 조각은 버린다 — 그릴 것이 없다.
    if (points.isNotEmpty) strokes.add(points);
  }

  // 가로/세로 비는 받은 점에서 되찾는다 — 서버가 주지 않는다.
  return RouteArt.fromNormalized(strokes);
}
