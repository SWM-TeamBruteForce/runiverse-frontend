import 'package:flutter/material.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 배경 없이 달린 모양만 긋는다.
///
/// ## ⚠️ 지도 위젯을 쓰지 않는다
///
/// `RunMapView`(`flutter_naver_map`)를 쓰면 ① `NAVER_MAP_CLIENT_ID`가 없는
/// 빌드에서 지도 대신 안내가 뜨고 ② 지도 제스처가 사진 페이저의 좌우 밀기를
/// 빼앗는다. 선만 그으면 둘 다 없다.
///
/// 진짜 지도가 필요하면 러닝 결과 화면(S16)에 이미 있다.
class RouteArtView extends StatelessWidget {
  const RouteArtView({
    required this.art,
    required this.color,
    this.strokeWidth = 2,
    this.padding = 0,
    super.key,
  });

  final RouteArt art;
  final Color color;
  final double strokeWidth;

  /// 선이 모서리에 닿지 않게 들이는 간격.
  final double padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RouteArtPainter(
      art: art,
      color: color,
      strokeWidth: strokeWidth,
      padding: padding,
    ),
    // 칸을 꽉 채운다. 크기는 부모가 정한다.
    size: Size.infinite,
  );
}

class _RouteArtPainter extends CustomPainter {
  const _RouteArtPainter({
    required this.art,
    required this.color,
    required this.strokeWidth,
    required this.padding,
  });

  final RouteArt art;
  final Color color;
  final double strokeWidth;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    if (art.isEmpty || size.isEmpty) return;

    final strokes = fitRoute(
      art,
      width: size.width,
      height: size.height,
      padding: padding + strokeWidth / 2,
    );

    final brush = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = Path();
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;

      // ⚠️ **조각마다 새로 시작한다.** 이어 붙이면 일시정지로 끊긴 자리가
      // 직선으로 메워져 가 본 적 없는 길이 생긴다.
      if (stroke.length == 1) {
        // 한 점짜리 조각은 선이 안 그려진다. 작은 점으로 남긴다.
        canvas.drawCircle(
          Offset(stroke.single.x, stroke.single.y),
          strokeWidth / 2,
          Paint()..color = color,
        );
        continue;
      }

      path.moveTo(stroke.first.x, stroke.first.y);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.x, point.y);
      }
    }

    canvas.drawPath(path, brush);
  }

  @override
  bool shouldRepaint(_RouteArtPainter old) =>
      !identical(old.art, art) ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.padding != padding;
}
