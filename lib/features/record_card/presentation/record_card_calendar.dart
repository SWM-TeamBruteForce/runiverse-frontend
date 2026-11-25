import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';
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
/// ## ⚠️ 최신 달이 **맨 아래**다
///
/// 과거를 보려면 **위로 올린다**(사용자 결정 2026-11-24). 뒤집어 놓았으므로
/// 스크롤 0이 곧 바닥이고, 탭을 열면 이번 달이 그 자리에 떠 있다 — 가장 자주
/// 보는 것이 이번 달이라는 전제는 그대로다.
///
/// ⚠️ **`더 받기` 줄도 함께 맨 위로 간다.** 뒤집힌 목록에서 `maxScrollExtent`는
/// 위쪽 끝이라, 더 받는 방아쇠 조건은 바꾸지 않아도 그대로 맞는다.
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
  final ValueChanged<RecordCardSummary> onOpen;

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
          // ⚠️ **아래에서 위로 쌓는다.** index 0이 바닥에 놓여 최신 달이 거기
          // 선다. 열었을 때 보이는 것이 이번 달이어야 한다.
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
          // 마지막 한 칸은 더 받기 줄이다 — 뒤집혀서 **맨 위**에 놓인다.
          itemCount: months.length + 1,
          itemBuilder: (context, index) => index == months.length
              ? _Footer(atOldest: data.atOldest, onLoadOlder: onLoadOlder)
              : _MonthSection(
                  month: months[index],
                  zoom: data.zoom,
                  shoeDays: data.shoeDays,
                  onOpen: onOpen,
                  onEmptyDay: onEmptyDay,
                ),
        ),
      ),
    );
  }
}

/// 목록 맨 아래의 더 받기 줄.
///
/// ## ⚠️ 스크롤만으로는 못 받는다
///
/// 안드로이드에서 **스크롤할 것이 없는 목록은 `ScrollUpdateNotification`을 아예
/// 내지 않는다**(`ClampingScrollPhysics`). 보이는 달이 하나뿐이면 그것만으로는
/// 과거를 받을 방아쇠가 없어, 더 과거의 카드에 닿을 길이 앱 안에 사라진다.
///
/// 누를 것을 두면 스크린리더·모터 제약 사용자에게도 길이 생긴다.
class _Footer extends StatelessWidget {
  const _Footer({required this.atOldest, required this.onLoadOlder});

  final bool atOldest;
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space4,
        AppSpacing.space6,
      ),
      child: Center(
        // ⚠️ 더 없을 때 버튼을 **그냥 치우지 않는다.** 사라지면 다 받은 것인지
        // 고장인지 알 수 없다.
        child: atOldest
            ? Text(
                AppStrings.recordCardNoOlder,
                style: AppTypographyV2.body18.copyWith(
                  color: colors.textTertiary,
                ),
              )
            : AppButtonV2(
                label: AppStrings.recordCardLoadOlder,
                variant: AppButtonV2Variant.secondary,
                expand: false,
                onPressed: onLoadOlder,
              ),
      ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.month,
    required this.zoom,
    required this.shoeDays,
    required this.onOpen,
    required this.onEmptyDay,
  });

  final MonthCards month;
  final CalendarZoom zoom;

  /// 뛰었는데 카드를 안 쓴 날. **달 전체가 아니라 상태가 들고 있는 것**을
  /// 그대로 받는다 — 유형 필터를 따르지 않아야 해서다(`RecordCardData.shoeDays`).
  final Set<DateTime> shoeDays;
  final ValueChanged<RecordCardSummary> onOpen;
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
    final daysInMonth = DateTime(
      month.month.year,
      month.month.month + 1,
      0,
    ).day;
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

  Widget _cellFor(
    BuildContext context,
    int dayOfMonth, {
    required bool compact,
  }) {
    final day = DateTime(month.month.year, month.month.month, dayOfMonth);
    final cards = month.byDay[day] ?? const <RecordCardSummary>[];
    final hasUnwrittenRun = shoeDays.contains(day);

    return RecordCardCell(
      day: day,
      cards: cards,
      showDayNumber: !compact,
      hasUnwrittenRun: hasUnwrittenRun,
      // ⚠️ **안 뛴 빈 날은 눌리지 않는다**(설계 6-1, 2026-11-18). 눌러서
      // "기록이 없어요"를 보여 주는 것보다 애초에 안 눌리는 편이 낫다.
      // `null`을 주면 `Semantics(button:)`도 함께 꺼져, 스크린리더가 누를 수
      // 없는 칸을 버튼으로 읽지 않는다.
      onTap: cards.isEmpty && !hasUnwrittenRun
          ? null
          : () {
              if (cards.isEmpty) {
                onEmptyDay(day);
                return;
              }
              if (cards.length == 1) {
                onOpen(cards.single);
                return;
              }
              showDayCardsSheet(
                context,
                day: day,
                cards: cards,
                onOpen: onOpen,
              );
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
