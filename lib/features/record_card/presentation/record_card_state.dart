import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';

/// 달력이 얼마나 오므라들었나.
enum CalendarZoom {
  /// 한 달이 한 화면쯤. 날짜 숫자가 보인다.
  month,

  /// 세 달이 한 화면. 칸이 작아 날짜 숫자는 뺀다.
  quarter,
}

/// 오므린 정도를 보고 다음 단계를 고른다.
///
/// ## ⚠️ 문턱이 있다
///
/// 손가락이 조금만 움직여도 바뀌면 **세로로 스크롤하다 줌이 튄다.** 많이
/// 오므렸을 때(`< 0.8`)와 많이 벌렸을 때(`> 1.25`)만 움직인다.
CalendarZoom zoomFor(CalendarZoom current, double scale) {
  if (scale < 0.8) return CalendarZoom.quarter;
  if (scale > 1.25) return CalendarZoom.month;
  return current;
}

/// 한 달치 — **그 달의 러닝 기록과 거기 쓴 카드**.
///
/// ⚠️ **묶는 일은 생성자에서 끝낸다.** 위젯이 매 빌드마다 다시 묶으면 스크롤할
/// 때마다 같은 계산이 반복된다(`docs/implementation-notes.md` 5-3,
/// `RecordData`가 같은 이유를 적어 두었다).
class MonthCards {
  MonthCards({required this.month, required this.runs})
    : byDay = _groupByDay(runs),
      recordDays = {for (final run in runs) run.day};

  /// 이 묶음이 가리키는 달. 항상 그 달 **1일 0시**다.
  final DateTime month;

  /// 이 달의 러닝 기록 전부. 카드가 없는 것도 들어 있다. 시작 시각 오름차순.
  ///
  /// ⚠️ **한 조회에서 온다**(`GET /users/me/running-records`, 7-1). 묶음 6까지는
  /// 카드와 기록을 따로 받아 달마다 요청이 둘이었다.
  final List<ComposableRecord> runs;

  /// 날짜별 **카드**. 키는 시·분을 자른 날짜다. 카드가 없는 기록은 빠진다.
  ///
  /// 하루에 두 번 뛰면 값이 둘일 수 있다 — 러닝 기록 1건당 카드가 1개라서,
  /// **하루당 카드 1개가 아니다.**
  final Map<DateTime, List<RecordCardSummary>> byDay;

  /// 이 달에 **뛴 날들**. 카드가 있는지와는 무관하다.
  ///
  /// ⚠️ **이제 카드와 같은 응답에서 온다.** 따로 받던 때는 그 조회만 실패하면
  /// 운동화가 빠졌는데, 지금은 둘이 함께 오거나 함께 실패한다.
  final Set<DateTime> recordDays;

  int get cardCount => byDay.values.fold(0, (sum, cards) => sum + cards.length);

  /// [activity]만 남긴 같은 달. `null`이면 그대로 돌려준다.
  ///
  /// ⚠️ **러닝 기록은 거르지 않는다.** 카드가 없는 기록에는 유형이 없어서
  /// (가이드 1절) 거르면 **필터를 켠 순간 운동화가 전부 사라진다.** 빼는 것은
  /// 카드뿐이다.
  MonthCards filtered(RecordCardActivity? activity) {
    if (activity == null) return this;
    return MonthCards(
      month: month,
      runs: [
        for (final run in runs)
          if (run.existingCard?.activity == activity)
            run
          else
            ComposableRecord(record: run.record),
      ],
    );
  }

  static Map<DateTime, List<RecordCardSummary>> _groupByDay(
    List<ComposableRecord> runs,
  ) {
    final byDay = <DateTime, List<RecordCardSummary>>{};
    for (final run in runs) {
      final card = run.existingCard;
      if (card != null) (byDay[run.day] ??= []).add(card);
    }
    return byDay;
  }
}

/// 기록카드 탭의 상태. loading / data / error 세 갈래다.
///
/// freezed를 아직 안 쓰므로 sealed class로 직접 적는다 — `RecordState`와 같은
/// 방식이라 화면의 `switch`가 세 갈래를 빠짐없이 처리하도록 강제된다.
sealed class RecordCardState {
  const RecordCardState();
}

class RecordCardLoading extends RecordCardState {
  const RecordCardLoading();
}

class RecordCardError extends RecordCardState {
  const RecordCardError(this.failure);

  final RecordCardFailure failure;
}

/// 받아 온 카드.
class RecordCardData extends RecordCardState {
  factory RecordCardData({
    required List<MonthCards> months,
    RecordCardActivity? filter,
    CalendarZoom zoom = CalendarZoom.month,
    bool atOldest = false,
  }) => RecordCardData._(
    months: [...months]..sort((a, b) => a.month.compareTo(b.month)),
    filter: filter,
    zoom: zoom,
    atOldest: atOldest,
  );

  RecordCardData._({
    required this.months,
    required this.filter,
    required this.zoom,
    required this.atOldest,
  }) : visible = _visibleOf(months, filter),
       shoeDays = _shoeDaysOf(months);

  /// 필터를 걸기 **전**의 달들. 오름차순이다.
  ///
  /// 화면은 이쪽을 보지 않는다 — [visible]을 본다. 필터를 바꿀 때 서버를 다시
  /// 부르지 않으려고 원본을 들고 있는 것이다.
  final List<MonthCards> months;

  /// 필터를 적용한 달들. **화면이 보는 것은 이쪽이다.**
  ///
  /// ⚠️ **0장이 된 달도 남는다.** 달이 통째로 사라지면 달력이 아니게 된다.
  final List<MonthCards> visible;

  /// 뛰었는데 카드를 안 쓴 날. 달력이 여기에 운동화를 두고, **이 날만 눌러서**
  /// 작성으로 간다.
  ///
  /// ## ⚠️ 유형 필터를 따르지 않는다
  ///
  /// [months]로 가린다 — [visible]로 가리면 `대회` 필터를 걸었을 때 일상 카드를
  /// 쓴 날이 전부 "안 쓴 날"이 되어 **달력이 운동화로 뒤덮인다.** 필터는
  /// 보는 방식이고, 카드를 썼는지는 필터와 무관한 사실이다.
  final Set<DateTime> shoeDays;

  /// `null`이면 전체다.
  final RecordCardActivity? filter;

  final CalendarZoom zoom;

  /// 더 과거에는 카드가 없다고 본 상태.
  ///
  /// ⚠️ **"끝"이 아니라 "여기까지 파 봤다"는 뜻이다.** 석 달을 통째로 쉰
  /// 사람은 그 앞에 카드가 있을 수 있어, 화면은 이 값일 때도 **사용자가 한 번
  /// 더 파게** 둔다(`loadOlder(force: true)`).
  final bool atOldest;

  /// 필터를 떼고 보면 카드가 하나라도 있나.
  ///
  /// ## ⚠️ [visible]이 비었는지로 판단하면 안 된다
  ///
  /// 필터를 걸어 0장이 된 것과 **카드를 한 장도 안 쓴 것**은 다르다. 전자에게
  /// "아직 없어요"를 띄우면 필터 때문인 줄 모른다.
  bool get hasAnyCard => months.any((month) => month.cardCount > 0);

  /// 들고 있는 달들. 컨트롤러가 **이미 받은 달을 다시 받지 않으려고** 본다.
  Set<DateTime> get loadedMonths => {for (final month in months) month.month};

  RecordCardData copyWith({
    List<MonthCards>? months,
    RecordCardActivity? filter,
    bool clearFilter = false,
    CalendarZoom? zoom,
    bool? atOldest,
  }) => RecordCardData(
    months: months ?? this.months,
    filter: clearFilter ? null : (filter ?? this.filter),
    zoom: zoom ?? this.zoom,
    atOldest: atOldest ?? this.atOldest,
  );

  static Set<DateTime> _shoeDaysOf(List<MonthCards> months) => {
    for (final month in months)
      for (final day in month.recordDays)
        if (!month.byDay.containsKey(day)) day,
  };

  /// 화면에 세울 달들. **가장 오래된 빈 달들을 잘라 낸다.**
  ///
  /// ## ⚠️ 더 받기가 빈 달을 붙여 둔다
  ///
  /// 과거로 더 받다 보면 카드가 없는 달이 딸려 온다. 그대로 두면 바닥에
  /// **아무것도 없는 달력이 줄줄이** 늘어선다. 설계가 "과거는 첫 카드가 있는
  /// 달까지"라고 적은 이유다.
  ///
  /// 자르는 기준은 **필터를 걸기 전**이다. 필터로 0장이 된 달까지 잘라 내면
  /// 필터를 걸 때마다 달력의 길이가 들쭉날쭉해진다.
  ///
  /// ⚠️ **사이에 낀 빈 달은 남긴다.** 9월과 11월만 뛰었다고 10월을 빼면 달력이
  /// 달을 건너뛴다. ⚠️ **한 장도 없으면 받은 그대로 둔다** — 달력이 통째로
  /// 비면 이 탭이 무엇인지 알 수 없다.
  static List<MonthCards> _visibleOf(
    List<MonthCards> sorted,
    RecordCardActivity? filter,
  ) {
    final first = sorted.indexWhere((month) => month.cardCount > 0);
    final from = first < 0 ? 0 : first;
    return [for (final month in sorted.skip(from)) month.filtered(filter)];
  }
}
