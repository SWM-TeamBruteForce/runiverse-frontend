import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';

/// 구간별 꺾은선 하나. Figma `47:90`(페이스)·`47:152`(케이던스)가 같은 모양이다.
///
/// ## 왜 차트 패키지를 쓰지 않았나
///
/// 라이브러리가 대신해 줄 일이 **격자 3줄과 선 하나**뿐이다. x축 라벨도 안내문도
/// Figma에서 이미 차트 밖 프레임이고, 제일 까다로운 스크러버는 어차피 직접
/// 짜야 한다 — `fl_chart`의 터치 모델은 "가장 가까운 점"이라 "누른 채 훑기"와
/// 미묘하게 다르다. 의존성을 하나 늘리는 값이 그만큼 되지 않는다.
///
/// ## 값을 뒤집지 않는다
///
/// 페이스는 **작을수록 빠른데** 이 차트는 값을 그대로 올린다. 즉 위로 솟은
/// 봉우리가 "느렸던 구간"이다. 러닝 앱마다 관례가 갈리는 자리라 Figma에 없는
/// 규칙을 지어내지 않았다 — 뒤집는 게 맞다면 [_LinePainter]의 `_y` 한 줄이다.
class SplitLineChart extends StatefulWidget {
  const SplitLineChart({
    required this.title,
    required this.unit,
    required this.values,
    required this.labels,
    required this.format,
    required this.color,
    required this.hint,
    this.badge,
    super.key,
  });

  /// `구간별 페이스`처럼 카드 왼쪽 위에 붙는 이름.
  final String title;

  /// 제목 옆의 단위. `/km` `spm`.
  final String unit;

  /// 구간마다의 값. 세로축이 이걸 그린다.
  final List<double> values;

  /// [values]와 같은 길이의 x축 라벨. `1km` `2km` …
  final List<String> labels;

  /// 스크러버가 집은 값을 사람이 읽는 말로. 페이스면 `5'28"`이다.
  final String Function(double value) format;

  /// 선 색. 정본은 **그 러너의 오늘 색**이라고 적었지만 아직 그 색이 없다.
  final Color color;

  /// 카드 맨 아래 안내문. 밀 수 있다는 것을 아무도 스스로 알아채지 못한다.
  final String hint;

  /// 값이 진짜가 아닐 때 붙이는 꼬리표. 케이던스가 `예시`를 단다.
  ///
  /// **비워두면 안 붙는다.** 가짜 값을 진짜처럼 보이게 두지 않으려고 만든
  /// 자리라, 지어낸 값을 그릴 때는 반드시 채운다.
  final String? badge;

  @override
  State<SplitLineChart> createState() => _SplitLineChartState();
}

class _SplitLineChartState extends State<SplitLineChart> {
  /// 지금 손가락이 집고 있는 구간. 떼면 `null`이다.
  int? _focused;

  /// 꺾은선의 좌우 여백. 양 끝 점이 카드 모서리에 잘리지 않게 둔다.
  static const _inset = AppSpacing.space4;

  /// Figma `47:94`. 카드 높이가 아니라 그림 영역의 높이다.
  static const _plotHeight = 132.0;

  void _focus(double dx, double width) {
    final span = width - _inset * 2;
    final ratio = span <= 0 ? 0.0 : ((dx - _inset) / span).clamp(0.0, 1.0);
    final next = (ratio * (widget.values.length - 1)).round();
    if (next != _focused) setState(() => _focused = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final focused = _focused;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.borderDefault),
        borderRadius: AppRadius.lg,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space3,
          AppSpacing.space3,
          AppSpacing.space3,
          AppSpacing.space2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Title(
              title: widget.title,
              unit: widget.unit,
              badge: widget.badge,
              // 손가락이 집은 값은 제목 줄 오른쪽에 띄운다. 선 옆에 붙이면
              // 그 손가락이 가린다.
              reading: focused == null
                  ? null
                  : widget.format(widget.values[focused]),
              readingColor: widget.color,
            ),
            const SizedBox(height: AppSpacing.space2),

            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  // 탭도 받는다. 짧게 눌러 본 사람에게 아무 반응이 없으면
                  // 밀어야 한다는 걸 알 길이 없다.
                  onTapDown: (d) => _focus(d.localPosition.dx, width),
                  onHorizontalDragStart: (d) =>
                      _focus(d.localPosition.dx, width),
                  onHorizontalDragUpdate: (d) =>
                      _focus(d.localPosition.dx, width),
                  onHorizontalDragEnd: (_) => setState(() => _focused = null),
                  onTapUp: (_) => setState(() => _focused = null),
                  onTapCancel: () => setState(() => _focused = null),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CustomPaint(
                        size: const Size.fromHeight(_plotHeight),
                        painter: _LinePainter(
                          values: widget.values,
                          focused: focused,
                          line: widget.color,
                          grid: colors.borderDefault,
                          inset: _inset,
                        ),
                      ),
                      SizedBox(
                        height: AppSpacing.space4,
                        child: _Labels(
                          labels: widget.labels,
                          inset: _inset,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: AppSpacing.space1),
            Text(
              widget.hint,
              textAlign: TextAlign.center,
              style: AppTypography.micro.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.title,
    required this.unit,
    required this.badge,
    required this.reading,
    required this.readingColor,
  });

  final String title;
  final String unit;
  final String? badge;
  final String? reading;
  final Color readingColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = badge;

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.space1),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.micro.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.space1),
          Text(
            unit,
            style: AppTypography.micro.copyWith(color: colors.textTertiary),
          ),
          if (label != null) ...[
            const SizedBox(width: AppSpacing.space2),
            _Badge(label: label),
          ],
          const Spacer(),
          if (reading != null)
            Text(
              reading!,
              style: AppTypography.micro.copyWith(
                color: readingColor,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// 값이 지어낸 것임을 화면에서 밝히는 꼬리표.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderStrong),
        borderRadius: AppRadius.sm,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space1,
          vertical: AppSpacing.space0,
        ),
        child: Text(
          label,
          style: AppTypography.micro.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }
}

/// x축 라벨. 점 위치에 가운데를 맞춰 놓는다.
///
/// 구간이 많아지면 **일부만 남긴다.** 10km를 달리면 라벨 10개가 356px 안에
/// 겹쳐 붙어 아무것도 못 읽는다.
class _Labels extends StatelessWidget {
  const _Labels({
    required this.labels,
    required this.inset,
    required this.color,
  });

  final List<String> labels;
  final double inset;
  final Color color;

  /// 라벨 한 칸의 너비. `10km`가 들어가고도 남는다.
  static const _slot = 44.0;

  @override
  Widget build(BuildContext context) {
    // 다섯 개쯤으로 솎되 마지막 구간은 항상 남긴다 — 총 거리를 읽는 자리다.
    final step = (labels.length / 5).ceil().clamp(1, labels.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        final span = constraints.maxWidth - inset * 2;
        final last = labels.length - 1;

        return Stack(
          children: [
            for (var i = 0; i < labels.length; i++)
              if (i % step == 0 || i == last)
                Positioned(
                  left:
                      inset +
                      (last == 0 ? span / 2 : span * i / last) -
                      _slot / 2,
                  top: AppSpacing.space0,
                  width: _slot,
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: AppTypography.micro.copyWith(color: color),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.values,
    required this.focused,
    required this.line,
    required this.grid,
    required this.inset,
  });

  final List<double> values;
  final int? focused;
  final Color line;
  final Color grid;
  final double inset;

  /// 위아래 여백 비율. 선이 카드 천장과 바닥에 닿으면 값의 크기를 못 읽는다.
  static const _padRatio = 0.15;

  double _x(int i, Size size) {
    final span = size.width - inset * 2;
    if (values.length == 1) return inset + span / 2;
    return inset + span * i / (values.length - 1);
  }

  double _y(double value, Size size) {
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final pad = size.height * _padRatio;
    final usable = size.height - pad * 2;

    // 값이 전부 같으면 나눌 폭이 없다. 가운데에 눕힌다.
    if (max - min < 0.000001) return size.height / 2;
    return pad + (1 - (value - min) / (max - min)) * usable;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(_x(i, size), _y(values[i], size)),
    ];

    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawCircle(points.first, 3, Paint()..color = line);
    } else {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    final index = focused;
    if (index == null || index >= points.length) return;

    // 세로 기준선은 손가락이 아니라 **그 구간의 점**에 선다. 손가락 위치에
    // 그대로 두면 어느 구간을 읽는 중인지 흔들린다.
    final at = points[index];
    canvas.drawLine(
      Offset(at.dx, 0),
      Offset(at.dx, size.height),
      Paint()
        ..color = line.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(at, 4, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.focused != focused || old.values != values || old.line != line;
}
