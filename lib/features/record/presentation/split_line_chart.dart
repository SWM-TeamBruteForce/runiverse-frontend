import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record/presentation/split_axis.dart';

/// 손가락이 가리키는 구간.
///
/// [dx]는 **거터를 포함한 카드 기준**이고 [plotWidth]는 그림 영역의 너비다.
///
/// ⚠️ **[gutter]만큼 빼지 않으면 집는 구간이 통째로 밀린다.** 손가락은 첫 점을
/// 가리키는데 두 번째가 집히는 식이라, 말풍선에 그럴듯한 값이 떠서 **틀렸다는
/// 것이 화면에 드러나지 않는다.**
///
/// 위젯이 아니라 함수로 둔 이유도 그것이다 — 말풍선은 캔버스에 그려 위젯
/// 트리에 남지 않으므로, 이 계산을 테스트로 잡으려면 꺼내 놓아야 한다.
@visibleForTesting
int focusedSplitOf({
  required double dx,
  required double plotWidth,
  required double gutter,
  required double inset,
  required int count,
}) {
  if (count <= 1) return 0;
  final span = plotWidth - inset * 2;
  final ratio = span <= 0
      ? 0.0
      : ((dx - gutter - inset) / span).clamp(0.0, 1.0);
  return (ratio * (count - 1)).round();
}

/// 끊기지 않고 이어지는 토막들로 나눈다. 빈 자리(`null`)가 경계다.
///
/// ## ⚠️ 빈 자리를 건너뛰어 이으면 안 된다
///
/// 모르는 구간을 가로지르는 직선은 **그 구간을 잰 것처럼 보인다.** 경로를
/// 30m 넘게 벌어진 자리에서 끊는 것(`RouteSegments`)과 같은 판단이다.
///
/// 위젯이 아니라 함수로 둔 이유는 [focusedSplitOf]와 같다 — 선은 캔버스에
/// 그려 위젯 트리에 남지 않아서, 이어 그었는지 끊어 그었는지를 **화면에서는
/// 확인할 수 없다.**
@visibleForTesting
List<List<Offset>> lineRunsOf(List<Offset?> points) {
  final runs = <List<Offset>>[];
  var run = <Offset>[];
  for (final point in points) {
    if (point == null) {
      if (run.isNotEmpty) runs.add(run);
      run = <Offset>[];
      continue;
    }
    run.add(point);
  }
  if (run.isNotEmpty) runs.add(run);
  return runs;
}

/// 두 선이 각각 누구 것인지 알리는 이름표.
///
/// 칩으로 고른 사람의 선이 겹쳐 그려지는데, **색만으로는 어느 쪽이 나인지
/// 알 수 없다.** 위쪽 러너 칩이 같은 색을 쓰지만 화면을 내려오면서 눈에서
/// 멀어진다 — 그래프 자리에서 한 번 더 말해 준다(시안 `158:3680`).
class ChartLegend {
  const ChartLegend({required this.mine, required this.other});

  /// 내 선의 이름. 시안은 닉네임을 쓴다.
  final String mine;

  /// 겹쳐 그린 선의 이름. 고른 파티원의 닉네임이다.
  final String other;

  @override
  bool operator ==(Object other) =>
      other is ChartLegend && other.mine == mine && other.other == this.other;

  @override
  int get hashCode => Object.hash(mine, other);
}

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
///
/// ## 격자선은 값을 갖는다
///
/// 전에는 선 셋을 `높이 × i/4`에 그렸다. 데이터와 아무 관계가 없어서 **모양만
/// 보이고 크기를 못 읽었다** — 들쭉날쭉이 10초 차이인지 2분 차이인지 집어보기
/// 전에는 알 수 없었다. 지금은 [SplitAxis]가 잡은 최고·중간·최저에 긋고
/// 왼쪽 거터에 그 값을 적는다.
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
    this.filled = false,
    this.showPoints = false,
    this.secondary,
    this.secondaryColor,
    this.axisTicks,
    this.legend,
    super.key,
  });

  /// 두 선의 이름표. **비교 중일 때만 넘긴다** — 혼자면 설명할 것이 없다.
  final ChartLegend? legend;

  /// x축에 라벨을 찍을 자리. `null`이면 **개수로 솎는다**(전체의 1/5마다).
  ///
  /// ## ⚠️ 개수로 솎으면 어중간한 거리가 나온다
  ///
  /// 50m 표본은 3km가 점 60개라 12개마다 찍히는데, 그러면 첫 점부터 세어
  /// `0.05 · 0.65 · 1.25km`가 된다. 읽는 사람이 쓰는 자는 **거리**지 점 번호가
  /// 아니다. 그래서 부르는 쪽이 `0.5km`처럼 딱 떨어지는 자리를 골라 넘긴다.
  ///
  /// 구간 번호가 곧 거리인 1km 그래프(`1km` `2km` …)는 넘기지 않는다 —
  /// 개수로 솎아도 어차피 딱 떨어진다.
  ///
  /// **마지막 점은 여기에 없어도 늘 찍힌다** — 총 거리를 읽는 자리다.
  final List<int>? axisTicks;

  /// 겹쳐 그릴 두 번째 선(파티원). [values]와 같은 자리가 같은 구간이다.
  /// 더 짧으면 거기까지만 그린다 — 먼저 끝난 사람은 뒤 구간이 없다.
  ///
  /// [values]와 마찬가지로 **모르는 구간은 `null`**이다.
  final List<double?>? secondary;

  /// 두 번째 선의 색. 그 러너의 레인 색이다.
  final Color? secondaryColor;

  /// `구간별 페이스`처럼 카드 왼쪽 위에 붙는 이름.
  final String title;

  /// 제목 옆의 단위. `/km` `spm`.
  final String unit;

  /// 구간마다의 값. 세로축이 이걸 그린다.
  ///
  /// ## ⚠️ 모르는 구간은 `null`이다 — 0이 아니다
  ///
  /// 케이던스는 걸음 표본이 모자라면 그 구간을 모른다. 0으로 바꿔 그리면
  /// **선이 바닥까지 떨어져 "그때 멈췄다"로 읽힌다.** 모르는 것과 0인 것은
  /// 다른 말이라, 여기서는 선을 끊는다.
  final List<double?> values;

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

  /// 선 아래를 채울 것인가. **50m 상세만 `true`다.**
  ///
  /// 점이 촘촘할 때는 선 하나로 오르내림이 잘 안 읽혀 면적이 형태를 먼저
  /// 보여 준다. 1km 그래프는 점이 몇 개뿐이라 채우면 오히려 뭉개진다.
  final bool filled;

  /// 구간마다 `o`를 찍을 것인가. **1km 그래프만 `true`다.**
  ///
  /// 선만 있으면 **멈출 수 있는 자리가 몇 개인지 보이지 않는다.** 점을 찍으면
  /// 밀어서 짚을 곳이 눈에 들어온다. 50m 상세는 점이 수십 개라 찍는 순간
  /// 선이 뭉개져 끈다.
  ///
  /// ⚠️ **내 선에만 찍는다.** 비교 중에 둘 다 찍으면 132px 안이 빽빽해진다.
  final bool showPoints;

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

  /// 세로 눈금 값이 들어가는 왼쪽 자리.
  ///
  /// ⚠️ **`space8`(40)로는 모자란다.** `10'05"`처럼 여섯 글자가 되면 앞자리가
  /// 잘려 `0'05"`로 읽히는데, 숫자가 틀리게 보이는 쪽이 그림이 8px 좁아지는
  /// 것보다 나쁘다.
  static const _gutter = AppSpacing.space9;

  void _focus(double dx, double plotWidth) {
    final next = focusedSplitOf(
      dx: dx,
      plotWidth: plotWidth,
      gutter: _gutter,
      inset: _inset,
      count: widget.values.length,
    );
    if (next != _focused) setState(() => _focused = next);
  }

  /// 집은 자리의 값. 두 번째 선이 있으면 `5'28" · 5'40"`처럼 나란히 적는다.
  ///
  /// 모르는 구간은 `--`다. 선이 끊긴 자리를 짚었을 때 **직전 값이 그대로
  /// 떠 있으면** 그 구간을 아는 것으로 읽힌다.
  String _readingAt(int index) {
    String read(double? value) =>
        value == null ? AppStrings.runUnavailable : widget.format(value);

    final mine = read(widget.values[index]);
    final other = widget.secondary;
    if (other == null || index >= other.length) return mine;
    return '$mine · ${read(other[index])}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
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
              legend: widget.legend,
              mineColor: widget.color,
              otherColor: widget.secondaryColor ?? colors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.space2),

            LayoutBuilder(
              builder: (context, constraints) {
                final plotWidth = constraints.maxWidth - _gutter;
                // ⚠️ **자는 한 벌이다.** 격자선은 캔버스가, 눈금 값은 위젯이
                // 그리므로 각자 계산하면 선과 숫자가 어긋난다.
                final axis = SplitAxis.of(
                  widget.values,
                  secondary: widget.secondary,
                  inverted: widget.inverted,
                );

                return GestureDetector(
                  // 탭도 받는다. 짧게 눌러 본 사람에게 아무 반응이 없으면
                  // 밀어야 한다는 걸 알 길이 없다.
                  onTapDown: (d) => _focus(d.localPosition.dx, plotWidth),
                  onHorizontalDragStart: (d) =>
                      _focus(d.localPosition.dx, plotWidth),
                  onHorizontalDragUpdate: (d) =>
                      _focus(d.localPosition.dx, plotWidth),
                  onHorizontalDragEnd: (_) => setState(() => _focused = null),
                  onTapUp: (_) => setState(() => _focused = null),
                  onTapCancel: () => setState(() => _focused = null),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        // 거터 글자는 저마다 제 높이에 놓인다. 늘이지 않는다.
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: _gutter,
                            height: _plotHeight,
                            child: _YLabels(
                              axis: axis,
                              format: widget.format,
                              height: _plotHeight,
                              color: colors.textTertiary,
                            ),
                          ),
                          Expanded(
                            child: CustomPaint(
                              size: const Size.fromHeight(_plotHeight),
                              painter: _LinePainter(
                                axis: axis,
                                values: widget.values,
                                focused: focused,
                                line: widget.color,
                                grid: colors.borderDefault,
                                inset: _inset,
                                filled: widget.filled,
                                showPoints: widget.showPoints,
                                surface: colors.bgSurface,
                                secondary: widget.secondary,
                                secondaryLine:
                                    widget.secondaryColor ??
                                    colors.textTertiary,
                                // ⚠️ 집은 값은 **그 점 바로 위**에 띄운다.
                                // 제목 줄 오른쪽에 두면 눈이 그래프와 카드
                                // 모서리를 오가야 해서 훑는 동안 안 읽힌다.
                                reading: focused == null
                                    ? null
                                    : _readingAt(focused),
                                // 값만으로는 "어디서" 그랬는지 모른다. x축
                                // 라벨은 솎아 그리므로 짚은 자리가 그 사이면
                                // 읽을 수 없다.
                                readingAt:
                                    focused == null ||
                                        focused >= widget.labels.length
                                    ? null
                                    : widget.labels[focused],
                                bubble: colors.bgElevated,
                                bubbleBorder: colors.borderStrong,
                                readingColor: colors.textPrimary,
                                readingAtColor: colors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // x축 라벨도 거터만큼 비켜 선다. 안 비키면 점과 라벨이
                      // 어긋나 어느 구간인지 잘못 읽힌다.
                      Padding(
                        padding: const EdgeInsets.only(left: _gutter),
                        child: SizedBox(
                          height: AppSpacing.space4,
                          child: _Labels(
                            labels: widget.labels,
                            ticks: widget.axisTicks,
                            inset: _inset,
                            color: colors.textTertiary,
                          ),
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
              style: AppTypographyV2.body18.copyWith(
                color: colors.textTertiary,
              ),
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
    required this.legend,
    required this.mineColor,
    required this.otherColor,
  });

  final String title;
  final String unit;
  final String? badge;
  final ChartLegend? legend;
  final Color mineColor;
  final Color otherColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final label = badge;
    final names = legend;

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.space1),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypographyV2.body18.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.space1),
          Text(
            unit,
            style: AppTypographyV2.body18.copyWith(color: colors.textTertiary),
          ),
          if (label != null) ...[
            const SizedBox(width: AppSpacing.space2),
            _Badge(label: label),
          ],
          if (names != null) ...[
            const Spacer(),
            // 시안(`158:3680`)은 이름표를 제목 줄 오른쪽 끝에 둔다.
            _LegendChip(name: names.mine, color: mineColor),
            const SizedBox(width: AppSpacing.space2),
            _LegendChip(name: names.other, color: otherColor),
          ],
        ],
      ),
    );
  }
}

/// 색 칩 하나 — 동그라미 하나와 이름.
///
/// 선 토막이 아니라 **칩**으로 둔다. 1.5px 선은 12px 글자 옆에서 거의 보이지
/// 않아 어느 색인지 가려내지 못한다. 시안(`158:3680`)은 네모지만 **위쪽 러너
/// 칩과 같은 동그라미**로 맞춘다 — 같은 색을 두 자리에서 다른 모양으로
/// 보이면 같은 사람을 가리키는 표시로 읽히지 않는다.
class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.name, required this.color});

  final String name;
  final Color color;

  /// 러너 칩의 점과 같은 8이다.
  static const _dot = AppSpacing.space2;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _dot,
          height: _dot,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.space1),
        // 닉네임은 최대 16자다. 제목과 다투지 않게 줄인다.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.space10),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypographyV2.body18.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// 값이 지어낸 것임을 화면에서 밝히는 꼬리표.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

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
          style: AppTypographyV2.body18.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }
}

/// 세로 눈금 값. 격자선과 **같은 높이에** 오른쪽 맞춤으로 적는다.
///
/// 캔버스가 아니라 위젯으로 그린다. 글자가 위젯 트리에 남아야
/// 스크린리더가 읽고 테스트가 찾는다 — x축 라벨(`_Labels`)과 같은 판단이다.
/// 높이는 [SplitAxis]가 정하므로 격자선과 어긋날 자리가 없다.
class _YLabels extends StatelessWidget {
  const _YLabels({
    required this.axis,
    required this.format,
    required this.height,
    required this.color,
  });

  final SplitAxis axis;
  final String Function(double value) format;
  final double height;
  final Color color;

  /// 글자 한 줄이 차지하는 높이. 본문 12px에 줄간격 1.24라 14.88이고,
  /// 4pt 스케일에서 가장 가까운 값을 쓴다 — 0.5px 차이는 눈에 띄지 않는다.
  static const _lineHeight = AppSpacing.space4;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (final value in axis.ticks)
        Positioned(
          right: AppSpacing.space1,
          // 글자 **가운데**를 격자선에 맞춘다. 위아래 끝에서 잘리지 않게
          // 가둔다 — 여백이 15%라 평소에는 닿지 않지만, 눈금이 하나뿐인
          // 평평한 그래프에서는 한가운데에 몰린다.
          top: (axis.dy(value, height) - _lineHeight / 2).clamp(
            0.0,
            height - _lineHeight,
          ),
          child: Text(
            format(value),
            maxLines: 1,
            style: AppTypographyV2.body18.copyWith(
              color: color,
              // 오른쪽 맞춤이 자릿수마다 흔들리지 않게 한다.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
    ],
  );
}

/// x축 라벨. 점 위치에 가운데를 맞춰 놓는다.
///
/// 구간이 많아지면 **일부만 남긴다.** 10km를 달리면 라벨 10개가 356px 안에
/// 겹쳐 붙어 아무것도 못 읽는다.
class _Labels extends StatelessWidget {
  const _Labels({
    required this.labels,
    required this.ticks,
    required this.inset,
    required this.color,
  });

  final List<String> labels;

  /// 찍을 자리. `null`이면 개수로 솎는다. [SplitLineChart.axisTicks] 참조.
  final List<int>? ticks;

  final double inset;
  final Color color;

  /// 라벨 한 칸의 너비. 50m 표본은 `12.34km`처럼 소수 둘까지 적으므로
  /// `10km` 시절보다 넓어야 한다.
  static const _slot = 56.0;

  @override
  Widget build(BuildContext context) {
    final at = ticks;
    // 다섯 개쯤으로 솎되 마지막 구간은 항상 남긴다 — 총 거리를 읽는 자리다.
    final step = (labels.length / 5).ceil().clamp(1, labels.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final span = width - inset * 2;
        final last = labels.length - 1;

        double centerOf(int i) =>
            inset + (last == 0 ? span / 2 : span * i / last);

        bool picked(int i) => at == null ? i % step == 0 : at.contains(i);

        // ⚠️ **고른 라벨이 마지막과 붙는 일이 있다.** 11점이면 3칸씩 골라
        // 0·3·6·9가 되는데 마지막 10을 항상 남기므로 9와 10이 겹쳐 찍힌다.
        // 거리로 골라도 마찬가지다 — 3.02km를 뛰면 3km와 3.02km가 붙는다.
        // 마지막에서 한 칸 안에 든 것은 버린다 — 총 거리를 읽는 쪽이 우선이다.
        final shown = [
          for (var i = 0; i < labels.length; i++)
            if (i == last ||
                (picked(i) && centerOf(last) - centerOf(i) >= _slot))
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
                  style: AppTypographyV2.body18.copyWith(color: color),
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
    required this.axis,
    required this.values,
    required this.focused,
    required this.line,
    required this.grid,
    required this.inset,
    required this.filled,
    required this.showPoints,
    required this.surface,
    required this.reading,
    required this.readingAt,
    required this.bubble,
    required this.bubbleBorder,
    required this.readingColor,
    required this.readingAtColor,
    this.secondary,
    required this.secondaryLine,
  });

  /// 세로 자. 격자선 자리와 점 높이가 전부 여기서 나온다.
  final SplitAxis axis;

  /// 구간마다의 값. **모르는 구간은 `null`**이고 거기서 선이 끊긴다.
  final List<double?> values;

  /// 두 번째 선. 없으면 `null`.
  final List<double?>? secondary;
  final Color secondaryLine;
  final int? focused;
  final Color line;
  final Color grid;
  final double inset;

  /// 선 아래를 채우는가. 50m 상세가 `true`다.
  final bool filled;

  /// 구간마다 `o`를 찍는가. 1km 그래프가 `true`다.
  final bool showPoints;

  /// 점 가운데를 메울 색. 카드 바탕이라야 선이 뚫고 지나가지 않는다.
  final Color surface;

  /// 집은 값을 사람이 읽는 말로. 손을 떼면 `null`이다.
  final String? reading;

  /// 그 값이 어느 지점인가. `0.65km`처럼 [reading] 아래 줄에 흐리게 붙는다.
  final String? readingAt;

  final Color bubble;
  final Color bubbleBorder;
  final Color readingColor;
  final Color readingAtColor;

  double _x(int i, Size size) {
    final span = size.width - inset * 2;
    if (values.length == 1) return inset + span / 2;
    return inset + span * i / (values.length - 1);
  }

  double _y(double value, Size size) => axis.dy(value, size.height);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    // ⚠️ **눈금 자리에 긋는다.** 전에는 `높이 × i/4`였는데, 데이터와 아무
    // 관계가 없어 선이 어떤 값을 뜻하는지 말해 주지 못했다. 같은 자리를
    // `_YLabels`가 숫자로 적는다.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final value in axis.ticks) {
      final y = _y(value, size);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final points = _pointsOf(values, size);

    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final run in lineRunsOf(points)) {
      if (run.length == 1) {
        canvas.drawCircle(run.first, 3, Paint()..color = line);
        continue;
      }

      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final point in run.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      // 바닥까지 내려 닫는다. 값의 최솟값이 아니라 **그림 영역 바닥**이라야
      // 구간마다 채운 높이가 서로 비교된다.
      if (filled) {
        final fill = Path.from(path)
          ..lineTo(run.last.dx, size.height)
          ..lineTo(run.first.dx, size.height)
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
      }

      canvas.drawPath(path, linePaint);
    }

    _paintSecondary(canvas, size);
    if (showPoints) _paintPoints(canvas, points);

    final index = focused;
    if (index == null || index >= points.length) return;

    // 세로 기준선은 손가락이 아니라 **그 구간의 점**에 선다. 손가락 위치에
    // 그대로 두면 어느 구간을 읽는 중인지 흔들린다.
    //
    // ⚠️ 모르는 구간에도 선은 세운다 — 짚은 자리가 어디인지는 말해 줘야
    // 한다. 점만 찍지 않는다. 말풍선은 `--`를 적는다.
    final at = points[index];
    final x = at?.dx ?? _x(index, size);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = line.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
    if (at != null) canvas.drawCircle(at, 4, Paint()..color = line);

    _paintReading(canvas, size, at ?? Offset(x, size.height / 2));
  }

  /// 값마다의 좌표. **모르는 구간은 `null`**이라 자리를 비워 둔다.
  List<Offset?> _pointsOf(List<double?> from, Size size) => [
    for (var i = 0; i < from.length && i < values.length; i++)
      if (from[i] case final value?)
        Offset(_x(i, size), _y(value, size))
      else
        null,
  ];

  /// 구간마다의 `o`.
  ///
  /// 선만 있으면 **멈출 수 있는 자리가 몇 개인지 보이지 않는다.** 점을 찍으면
  /// 밀어서 짚을 곳이 눈에 들어오고, 1km 그래프가 연속 신호가 아니라 **칸**
  /// 이라는 것도 함께 말해 준다.
  ///
  /// 가운데를 카드 바탕색으로 메운다. 비우면 선이 원을 뚫고 지나가 `o`가
  /// 아니라 매듭처럼 보인다.
  ///
  /// ⚠️ **모르는 구간에는 찍지 않는다.** 점이 있으면 그 자리의 값을 아는
  /// 것으로 읽힌다.
  void _paintPoints(Canvas canvas, List<Offset?> points) {
    final hole = Paint()..color = surface;
    final ring = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final point in points) {
      if (point == null) continue;
      canvas
        ..drawCircle(point, 3, hole)
        ..drawCircle(point, 3, ring);
    }
  }

  /// 파티원의 선. 채우지 않고 가늘게 — 주인공은 내 선이다.
  ///
  /// ⚠️ **점을 찍지 않는다.** 두 선에 다 찍으면 132px 안이 빽빽해지고,
  /// 집어서 읽는 것은 내 구간이라 점은 내 선의 표시로 남긴다.
  void _paintSecondary(Canvas canvas, Size size) {
    final other = secondary;
    if (other == null || other.isEmpty) return;

    final paint = Paint()
      ..color = secondaryLine
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final run in lineRunsOf(_pointsOf(other, size))) {
      if (run.length == 1) {
        canvas.drawCircle(run.first, 3, Paint()..color = secondaryLine);
        continue;
      }
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final point in run.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  /// 집은 값을 **그 점 바로 위**에 띄운다.
  ///
  /// 위젯이 아니라 여기서 그린다. 점의 좌표를 아는 곳이 여기뿐이라, 위젯으로
  /// 올리면 같은 계산을 두 벌 들고 서로 어긋나게 된다.
  void _paintReading(Canvas canvas, Size size, Offset at) {
    final value = reading;
    if (value == null) return;

    final text = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      text: TextSpan(
        children: [
          TextSpan(
            text: value,
            style: AppTypographyV2.body18.copyWith(
              color: readingColor,
              fontWeight: FontWeight.w600,
              // 훑는 동안 자릿수가 바뀌면 말풍선이 좌우로 떤다.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (readingAt != null)
            TextSpan(
              // 한 줄로 붙인다. 말풍선이 두 줄이면 점 위 공간을 많이 먹어
              // 그래프 위쪽 구간에서 자주 뒤집힌다.
              text: '  $readingAt',
              style: AppTypographyV2.body18.copyWith(
                color: readingAtColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    )..layout();

    const padX = AppSpacing.space2;
    const padY = AppSpacing.space1;
    const gap = AppSpacing.space2;

    final box = Size(text.width + padX * 2, text.height + padY * 2);

    // 점 위에 띄우되 천장을 넘으면 아래로 뒤집는다. 그래프 위쪽에 붙은
    // 점에서는 말풍선이 잘려 아무것도 못 읽는다.
    var top = at.dy - gap - box.height;
    if (top < 0) top = at.dy + gap;

    // 양 끝에서도 잘리지 않게 가둔다.
    final left = (at.dx - box.width / 2).clamp(0.0, size.width - box.width);

    final rect = Rect.fromLTWH(left, top, box.width, box.height);
    // `AppRadius.sm`은 BorderRadius다. 캔버스는 Radius 하나를 받으므로
    // 그 네 모서리 중 하나를 꺼내 쓴다 — 값을 새로 적지 않는다.
    final rrect = RRect.fromRectAndRadius(rect, AppRadius.sm.topLeft);

    canvas
      ..drawRRect(rrect, Paint()..color = bubble)
      ..drawRRect(
        rrect,
        Paint()
          ..color = bubbleBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    text.paint(canvas, Offset(left + padX, top + padY));
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.focused != focused ||
      old.values != values ||
      old.line != line ||
      old.axis != axis ||
      old.filled != filled ||
      old.showPoints != showPoints ||
      old.surface != surface ||
      old.reading != reading ||
      old.readingAt != readingAt ||
      old.secondary != secondary ||
      old.secondaryLine != secondaryLine;
}
