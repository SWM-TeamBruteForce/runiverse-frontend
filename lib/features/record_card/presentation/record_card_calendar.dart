import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/day_cards_sheet.dart';
import 'package:runiverse/features/record_card/presentation/record_card_cell.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

/// 그 달 1일 앞에 비워 둘 칸 수. **일요일부터 센다.**
///
/// `DateTime.weekday`는 월요일이 1이고 일요일이 7이다. `% 7`을 하면 일요일이
/// 0이 되어 요일 머리와 자리가 맞는다.
int leadingBlanks(DateTime month) =>
    DateTime(month.year, month.month, 1).weekday % 7;

/// 세로로 이어지는 월 달력.
///
/// ## ⚠️ 최신 달이 위다
///
/// 설계 스케치는 과거가 위였는데, 그러면 탭을 열 때마다 **이번 달이 화면 밖에**
/// 있다. 가장 자주 보는 것은 이번 달이라 위에 둔다. 아래로 내려가면 과거이고,
/// 끝에 닿으면 더 받는다.
///
/// ## ⚠️ 좌우로 넘기지 않는다
///
/// 달을 좌우로 넘기게 만들면 **어디까지 왔는지 알 수 없다.** 기록 탭 캘린더가
/// 같은 이유를 적어 두었다.
class RecordCardCalendar extends StatelessWidget {
  const RecordCardCalendar({
    required this.data,
    required this.onOpen,
    required this.onEmptyDay,
    required this.onZoom,
    required this.onLoadOlder,
    super.key,
  });

  final RecordCardData data;

  /// 카드 한 장을 열었다.
  final ValueChanged<RecordCard> onOpen;

  /// 카드가 없는 날을 눌렀다. **그날 러닝 기록이 있는지는 부르는 쪽이 본다.**
  final ValueChanged<DateTime> onEmptyDay;

  final ValueChanged<CalendarZoom> onZoom;

  /// 바닥에 닿았다 — 더 과거를 받는다.
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) {
    // 최신 달이 위로 오게 뒤집는다. 상태는 오름차순으로 들고 있다.
    final months = data.visible.reversed.toList();

    return _PinchDetector(
      zoom: data.zoom,
      onZoom: onZoom,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is! ScrollUpdateNotification) return false;
          final metrics = notification.metrics;
          if (!metrics.hasContentDimensions) return false;
          if (metrics.pixels >= metrics.maxScrollExtent - 200) onLoadOlder();
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: AppSpacing.space8),
          itemCount: months.length,
          itemBuilder: (context, index) => _MonthSection(
            month: months[index],
            zoom: data.zoom,
            onOpen: onOpen,
            onEmptyDay: onEmptyDay,
          ),
        ),
      ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.month,
    required this.zoom,
    required this.onOpen,
    required this.onEmptyDay,
  });

  final MonthCards month;
  final CalendarZoom zoom;
  final ValueChanged<RecordCard> onOpen;
  final ValueChanged<DateTime> onEmptyDay;

  /// 분기 보기에서 그리드를 얼마로 줄이나.
  ///
  /// ⚠️ **디자인 확인이 필요한 값이다.** 세 달이 한 화면에 들어오는 것이
  /// 기준이고, 기기에서 보고 다듬는다.
  static const _quarterScale = 0.6;

  /// 칸의 가로세로 비. 시안 `43 × 62`.
  static const _cellRatio = 43 / 62;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final compact = zoom == CalendarZoom.quarter;
    final daysInMonth = DateTime(month.month.year, month.month.month + 1, 0).day;
    final blanks = leadingBlanks(month.month);

    final grid = GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      // 바깥 ListView가 스크롤을 맡는다.
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: _cellRatio,
      children: [
        for (var i = 0; i < blanks; i++) const SizedBox.shrink(),
        for (var dayOfMonth = 1; dayOfMonth <= daysInMonth; dayOfMonth++)
          _cellFor(context, dayOfMonth, compact: compact),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                AppStrings.recordMonthLabel(month.month),
                style: AppTypographyV2.body12.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                AppStrings.recordCardMonthCount(month.cardCount),
                style: AppTypographyV2.body18.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          // ⚠️ 분기 보기에서는 칸이 26dp쯤이라 요일 글자도 숫자도 안 읽힌다.
          if (!compact) _WeekdayHeader(),
          if (compact)
            FractionallySizedBox(widthFactor: _quarterScale, child: grid)
          else
            grid,
        ],
      ),
    );
  }

  Widget _cellFor(BuildContext context, int dayOfMonth, {required bool compact}) {
    final day = DateTime(month.month.year, month.month.month, dayOfMonth);
    final cards = month.byDay[day] ?? const <RecordCard>[];

    return RecordCardCell(
      day: day,
      cards: cards,
      showDayNumber: !compact,
      onTap: () {
        if (cards.isEmpty) {
          onEmptyDay(day);
          return;
        }
        if (cards.length == 1) {
          onOpen(cards.single);
          return;
        }
        showDayCardsSheet(context, day: day, cards: cards, onOpen: onOpen);
      },
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space1),
      child: Row(
        children: [
          for (final label in AppStrings.recordWeekdays)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: AppTypographyV2.body18.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 두 손가락으로 오므렸다 벌렸다 하는 것만 본다.
///
/// ## ⚠️ `GestureDetector(onScaleUpdate:)`를 쓰지 않는다
///
/// `ScaleGestureRecognizer`는 손가락 **하나짜리 끌기도 받아들여서**, 스크롤
/// 가능한 자식 위에 얹으면 세로 스크롤을 빼앗는다. [Listener]는 제스처 경쟁에
/// 끼지 않으므로 스크롤이 그대로 산다.
class _PinchDetector extends StatefulWidget {
  const _PinchDetector({
    required this.zoom,
    required this.onZoom,
    required this.child,
  });

  final CalendarZoom zoom;
  final ValueChanged<CalendarZoom> onZoom;
  final Widget child;

  @override
  State<_PinchDetector> createState() => _PinchDetectorState();
}

class _PinchDetectorState extends State<_PinchDetector> {
  final _points = <int, Offset>{};

  /// 두 손가락이 처음 닿았을 때의 거리. 이것과 견줘 배율을 낸다.
  double? _base;

  double? _spread() {
    if (_points.length != 2) return null;
    final values = _points.values.toList();
    return (values.first - values.last).distance;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _points[event.pointer] = event.position;
      _base = _spread();
    },
    onPointerMove: (event) {
      if (!_points.containsKey(event.pointer)) return;
      _points[event.pointer] = event.position;

      final base = _base;
      final now = _spread();
      if (base == null || now == null || base <= 0) return;

      final next = zoomFor(widget.zoom, now / base);
      if (next == widget.zoom) return;
      // 한 번 바뀌면 손을 뗄 때까지 또 바뀌지 않게 기준을 지운다.
      _base = null;
      widget.onZoom(next);
    },
    onPointerUp: (event) {
      _points.remove(event.pointer);
      _base = _spread();
    },
    onPointerCancel: (event) {
      _points.remove(event.pointer);
      _base = _spread();
    },
    child: widget.child,
  );
}
