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
/// ## 축 방향은 값의 뜻을 따른다
///
/// 페이스는 **작을수록 빠르다.** 그대로 올리면 위로 솟은 봉우리가 "느렸던
/// 구간"이 되어, 사람이 그래프에서 기대하는 것과 반대로 읽힌다. 그래서
/// 페이스만 [inverted]로 뒤집어 **빠를수록 위**로 둔다. 케이던스는 클수록
/// 좋은 값이라 그대로 둔다.
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
    this.inverted = false,
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

  /// 작은 값을 위로 올릴 것인가. **페이스만 `true`다.**
  final bool inverted;

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
              // 값만 띄우면 "어디서" 그랬는지를 모른다. 같은 줄에 그 지점의
              // 거리를 붙인다 — x축 라벨은 솎아 그리므로 짚은 자리가 그 사이에
              // 있으면 읽을 수가 없다.
              readingAt: focused == null || focused >= widget.labels.length
                  ? null
                  : widget.labels[focused],
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
                          inverted: widget.inverted,
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
    required this.readingAt,
    required this.readingColor,
  });

  final String title;
  final String unit;
  final String? badge;
  final String? reading;

  /// 집은 값이 어느 지점인가. `8.51km`처럼 [reading] 옆에 흐리게 붙는다.
  final String? readingAt;
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
          if (reading != null) ...[
            Text(
              reading!,
              style: AppTypography.micro.copyWith(
                color: readingColor,
                fontWeight: FontWeight.w600,
                // 훑는 동안 자릿수가 바뀌면 글자가 좌우로 흔들린다.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (readingAt != null) ...[
              const SizedBox(width: AppSpacing.space2),
              Text(
                readingAt!,
                style: AppTypography.micro.copyWith(
                  color: colors.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
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

  /// 라벨 한 칸의 너비. 50m 표본은 `12.34km`처럼 소수 둘까지 적으므로
  /// `10km` 시절보다 넓어야 한다.
  static const _slot = 56.0;

  @override
  Widget build(BuildContext context) {
    // 다섯 개쯤으로 솎되 마지막 구간은 항상 남긴다 — 총 거리를 읽는 자리다.
    final step = (labels.length / 5).ceil().clamp(1, labels.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final span = width - inset * 2;
        final last = labels.length - 1;

        double centerOf(int i) =>
            inset + (last == 0 ? span / 2 : span * i / last);

        // ⚠️ **솎은 라벨이 마지막과 붙는 일이 있다.** 11점이면 3칸씩 골라
        // 0·3·6·9가 되는데 마지막 10을 항상 남기므로 9와 10이 겹쳐 찍힌다.
        // 마지막에서 한 칸 안에 든 것은 버린다 — 총 거리를 읽는 쪽이 우선이다.
        final shown = [
          for (var i = 0; i < labels.length; i++)
            if (i == last ||
                (i % step == 0 && centerOf(last) - centerOf(i) >= _slot))
              i,
        ];

        return Stack(
          children: [
            for (final i in shown)
              Positioned(
                // ⚠️ 양 끝에서 잘리지 않게 가둔다. 첫 라벨은 중심이 `inset`이라
                // 폭의 절반이 화면 밖으로 나간다.
                left: (centerOf(i) - _slot / 2).clamp(0.0, width - _slot),
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
    required this.inverted,
  });

  final List<double> values;
  final int? focused;
  final Color line;
  final Color grid;
  final double inset;

  /// 작은 값을 위로 올리는가. 페이스가 `true`다.
  final bool inverted;

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

    final ratio = (value - min) / (max - min);
    // 화면 좌표는 아래로 갈수록 크다. 보통은 큰 값이 위로 가야 하므로
    // 뒤집고(`1 - ratio`), 페이스는 **작을수록 빠르므로** 그대로 쓴다.
    return pad + (inverted ? ratio : 1 - ratio) * usable;
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

      // 선 아래를 채운다. 50m 단위로 점이 촘촘해지면 선 하나만으로는
      // 오르내림이 잘 안 읽힌다 — 면적이 있으면 형태가 먼저 보인다.
      //
      // 바닥까지 내려 닫는다. 값의 최솟값이 아니라 **그림 영역 바닥**이라야
      // 구간마다 채운 높이가 서로 비교된다.
      final fill = Path.from(path)
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [line.withValues(alpha: 0.28), line.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );

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
      old.focused != focused ||
      old.values != values ||
      old.line != line ||
      old.inverted != inverted;
}
