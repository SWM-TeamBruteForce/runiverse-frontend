import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record/domain/record_summary.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 한 주의 기록을 잇는 면적 그래프 — 시안 `158:3806`.
///
/// ## ⚠️ 막대에서 면적으로 바뀌었다
///
/// 옛 화면은 막대였고 **"안 뛴 날에 막대가 서지 않는다"**가 규칙이었다
/// (디자인 시스템 v1.1 §5-5, 잔디의 죄책감 문제). 그 제약은 **2026-10-04 에
/// 걷혔다** — 화면 정본이 Figma 시안으로 바뀌었고, 시안의 주간 기록은
/// 0인 날을 지나는 **연속 선**이다.
///
/// 지키려던 것(안 뛴 날이 **결손으로 읽히지 않을 것**)은 여전히 유효하다.
/// 면적 그래프에서는 **바닥선이 이어지는 것**이 그 자리를 대신한다 — 칸이
/// 비는 것이 아니라 선이 바닥을 지나간다.
///
/// ## ⚠️ 시안의 `173 spm` 툴팁은 만들지 않았다
///
/// 케이던스는 **목록 응답에 없다**(📅 기록 탭 연동 가이드 2장). 상세
/// (`averageCadenceSpm`)에만 있어서 하루치를 그릴 수가 없다. 그래서 이
/// 그래프는 **거리**를 그리고, 고른 날의 값도 거리로 말한다.
class RecordWeekChart extends StatelessWidget {
  const RecordWeekChart({
    required this.data,
    required this.onSelect,
    super.key,
  });

  final RecordData data;
  final ValueChanged<DateTime> onSelect;

  /// 시안 `158:3806`의 높이. 그림·요일 라벨까지 포함한다.
  static const _cardHeight = 272.0;

  /// 그림이 그려지는 띠. 시안의 격자선 위(85)와 아래(221) 사이다.
  static const _plotTop = 85.0;
  static const _plotBottom = 221.0;

  /// 요일 라벨 줄의 윗선.
  static const _labelTop = 233.0;

  /// 첫 점과 마지막 점이 카드 좌우에서 떨어진 거리. 시안은 42다.
  static const _sideInset = 42.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final days = data.weekDays;
    final meters = [
      for (final day in days)
        RecordSummary.of(data.weekByDay[day] ?? const []).totalMeters,
    ];
    final selected = days.indexWhere((day) => day == data.selectedDay);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.card,
      ),
      child: SizedBox(
        height: _cardHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final step = days.length <= 1
                ? 0.0
                : (width - _sideInset * 2) / (days.length - 1);

            return Stack(
              children: [
                Positioned(
                  left: AppSpacing.space6,
                  top: AppSpacing.space6,
                  child: Text(
                    AppStrings.recordWeekChartTitle,
                    style: AppTypographyV2.body12.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),

                Positioned.fill(
                  child: CustomPaint(
                    painter: _WeekPainter(
                      meters: meters,
                      selected: selected,
                      line: colors.primary,
                      grid: colors.borderDefault,
                      dot: colors.textStrong,
                      sideInset: _sideInset,
                      top: _plotTop,
                      bottom: _plotBottom,
                    ),
                  ),
                ),

                // 요일 라벨과 **누르는 자리**. 그림 위에 얹어 손가락이 닿게 한다.
                for (final (index, day) in days.indexed)
                  Positioned(
                    left: _sideInset + step * index - step / 2,
                    top: 0,
                    width: step <= 0 ? width : step,
                    height: _cardHeight,
                    child: _DayColumn(
                      label: AppStrings.recordWeekdayOf(day),
                      selected: index == selected,
                      labelTop: _labelTop,
                      onTap: () => onSelect(day),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 요일 한 칸. 글자는 아래에 두고 **칸 전체가 눌린다.**
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.label,
    required this.selected,
    required this.labelTop,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double labelTop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return GestureDetector(
      onTap: onTap,
      // 선이 얇아 빈 곳을 눌러도 잡히게 한다.
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Positioned(
            top: labelTop,
            left: 0,
            right: 0,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body18.copyWith(
                // 고른 날만 밝다. 시안은 전부 `#575757`이지만 **어느 날을
                // 골랐는지 알 길이 선 하나뿐**이라 글자도 함께 든다.
                color: selected ? colors.textStrong : colors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 격자선 · 면적 · 선 · 점을 그린다.
class _WeekPainter extends CustomPainter {
  const _WeekPainter({
    required this.meters,
    required this.selected,
    required this.line,
    required this.grid,
    required this.dot,
    required this.sideInset,
    required this.top,
    required this.bottom,
  });

  final List<int> meters;
  final int selected;
  final Color line;
  final Color grid;
  final Color dot;
  final double sideInset;
  final double top;
  final double bottom;

  /// 시안의 격자선 셋. 카드 높이에 대한 비율이다.
  static const _gridAt = [85.0, 153.0, 221.0];

  /// 점 반지름. 시안은 6px 사각형이라 지름 6이다.
  static const _dotRadius = 3.0;

  /// 고른 날의 점은 더 크다. 시안 `158:3846`이 8이다.
  static const _selectedRadius = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final y in _gridAt) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = grid
          ..strokeWidth = 0.6,
      );
    }

    if (meters.isEmpty) return;

    final peak = meters.fold(0, (a, b) => a > b ? a : b);
    final step = meters.length <= 1
        ? 0.0
        : (size.width - sideInset * 2) / (meters.length - 1);

    // ⚠️ **안 뛴 날도 점을 찍는다.** 건너뛰면 선이 끊겨 그 날이 통째로
    // 사라진 것처럼 보인다 — 결손으로 읽히지 않게 하려던 것이 그것이다.
    final points = [
      for (final (index, value) in meters.indexed)
        Offset(
          sideInset + step * index,
          // 기록이 하나도 없는 주는 전부 바닥이다. 0으로 나누지 않는다.
          peak <= 0 ? bottom : bottom - (bottom - top) * (value / peak),
        ),
    ];

    final stroke = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      stroke.lineTo(point.dx, point.dy);
    }

    final area = Path.from(stroke)
      ..lineTo(points.last.dx, bottom)
      ..lineTo(points.first.dx, bottom)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line, line.withValues(alpha: 0)],
        ).createShader(Rect.fromLTRB(0, top, size.width, bottom)),
    );

    canvas.drawPath(
      stroke,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    for (final (index, point) in points.indexed) {
      canvas.drawCircle(
        point,
        index == selected ? _selectedRadius : _dotRadius,
        Paint()..color = dot,
      );
    }

    // 고른 날을 지나는 세로선. 시안 `158:3840`.
    if (selected >= 0 && selected < points.length) {
      canvas.drawLine(
        Offset(points[selected].dx, top - 20),
        Offset(points[selected].dx, bottom),
        Paint()
          ..color = grid
          ..strokeWidth = 0.6,
      );
    }
  }

  @override
  bool shouldRepaint(_WeekPainter old) =>
      old.meters != meters || old.selected != selected;
}
