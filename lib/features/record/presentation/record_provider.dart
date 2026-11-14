import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/record/data/http_run_record_repository.dart';
import 'package:runiverse/features/record/domain/record_summary.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 기록을 누가 읽어 오나.
///
/// 목록 19번(`GET /users/me/running-records`)도 열렸다. 2026-10-04 에뮬레이터에서
/// 1인 러닝을 끝내고 `200`과 그 기록을 받았다 — 예전 주석이 `개발전`이라 적어
/// 두었던 것은 그때 이야기다. 테스트는 그래도 `FakeRunRecordRepository`를 쓴다.
final runRecordRepositoryProvider = Provider<RunRecordRepository>(
  (ref) => HttpRunRecordRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
  ),
);

/// "오늘"이 언제인가. 테스트가 고정된 날짜를 넣는다.
///
/// `DateTime.now()`를 화면에서 직접 부르면 자정 근처에서 테스트가 흔들리고,
/// 주간 차트가 어느 7일인지 검증할 수 없다.
final recordClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 러닝 결과 상세. **방 번호로 찾는다.**
///
/// 러닝을 막 끝냈을 때와 기록 탭에서 지난 기록을 눌렀을 때 둘 다 이걸 쓴다.
/// 앱이 아는 것이 방 번호라 기록 번호가 아니라 방 번호가 키다.
///
/// 화면을 닫으면 버린다(`autoDispose`) — 상세는 무거워서(구간이 10m 단위로
/// 수백 개다) 들고 있을 이유가 없다. 직접 만든 provider는 기본이 아니라서
/// 붙여야 한다(Riverpod 3).
final runDetailProvider = FutureProvider.autoDispose.family<RunDetail, int>(
  (ref, runningRoomId) =>
      ref.read(runRecordRepositoryProvider).byRoom(runningRoomId),
);

final recordControllerProvider =
    NotifierProvider<RecordController, RecordState>(RecordController.new);

/// 기록 탭의 데이터를 모은다.
///
/// ## 요청이 둘인 이유
///
/// 명세가 캘린더 모드(`from`·`to`)와 최근 목록 모드(`cursor`)의 혼용을 막는다.
/// 그리고 **이번 주(월~일)가 달 경계를 넘는다** — 9월 1일 화요일이면 8월 31일
/// 월요일부터 봐야 한다. 그래서 `from`·`to` 조회를 **이번 달**과 **이번 주**
/// 두 번 한다. 겹치는 날은 서버가 같은 기록을 두 번 주지만, 각각 따로
/// 묶으므로 문제없다.
///
/// ## ⚠️ 탭을 옮겨도 다시 읽지 않는다
///
/// 예전 주석은 그 반대로 적어 두었다 — "숨은 탭의 provider는 실제로
/// dispose된다"(`implementation-notes` 5-1). **`StatefulShellRoute.indexedStack`
/// 에는 해당하지 않는다.** 한 번 연 탭은 트리에 남아 계속 구독하므로 이
/// provider는 버려지지 않고 [build]가 두 번 돌지 않는다.
///
/// 그래서 러닝을 마치고 기록 탭에 들어가면 **방금 달린 것이 목록에 없었다.**
/// 앱을 껐다 켜야 보였다 — 2026-10-04 에뮬레이터에서 1인 러닝 1.22km 를
/// 끝내고 확인했다. 기록이 바뀌는 순간을 직접 듣는다([_watchRunFinish]).
class RecordController extends Notifier<RecordState> {
  /// 계정 차수. 계정이 바뀔 때마다 올라간다 — 그 전에 떠난 조회의 답을 가린다.
  var _accountEpoch = 0;

  @override
  RecordState build() {
    _watchRunFinish();
    _watchAccount();
    // build 안에서 await하지 않는다. 먼저 loading을 내보내고 뒤에서 읽는다.
    Future.microtask(load);
    return const RecordLoading();
  }

  /// 계정이 바뀌면 들고 있던 기록을 버리고, 로그인 상태면 새 계정으로 다시 읽는다.
  ///
  /// ⚠️ 이 provider는 로그아웃해도 살아 있고 [build]가 다시 돌지 않는다. 앱을 끄지
  /// 않고 다른 계정으로 들어오면 앞 사람의 차트·달력·목록이 그대로 보이고, 그 기록을
  /// 누르면 서버가 403으로 막는다.
  void _watchAccount() {
    ref.listen(
      authControllerProvider.select(
        (auth) => auth is AuthSignedIn ? auth.userId : null,
      ),
      (_, userId) {
        _accountEpoch++;
        state = const RecordLoading();
        if (userId != null) unawaited(load());
      },
    );
  }

  /// 러닝이 **서버에 확정되면** 목록을 다시 읽는다.
  ///
  /// ⚠️ **[RunFinished]가 아니라 `finishedRoomId`를 본다.** 화면이 요약으로
  /// 넘어가는 시점과 서버가 `RUNNING_FINISH`를 처리하는 시점이 다르다. 앞엣것에
  /// 맞춰 읽으면 그 기록이 아직 없어서, **다시 읽고도 똑같이 비어 있다** —
  /// 고치기 전과 구분되지 않는 실패라 더 나쁘다.
  void _watchRunFinish() {
    ref.listen(runningConnectionProvider.select((it) => it.finishedRoomId), (
      previous,
      next,
    ) {
      if (next == null || next == previous) return;
      unawaited(reload());
    });
  }

  /// 보고 있던 달과 고른 날을 그대로 두고 다시 읽는다.
  ///
  /// 그냥 [load]를 부르면 이번 달 오늘로 되돌아간다. 사용자가 지난달을 펼쳐
  /// 둔 채 러닝을 끝냈을 때 화면이 제멋대로 움직인다.
  Future<void> reload() {
    final current = state;
    return current is RecordData
        ? load(month: current.month, select: current.selectedDay)
        : load();
  }

  RunRecordRepository get _repository => ref.read(runRecordRepositoryProvider);

  /// 이번 달과 이번 주를 읽는다.
  ///
  /// [month]를 주면 그 달을, [select]를 주면 읽은 뒤 그 날을 고른다.
  /// [select]가 없으면 이번 달이면 오늘, 지난달이면 1일이다.
  ///
  /// ## ⚠️ 보여줄 것이 있으면 **비우지 않는다**
  ///
  /// 예전에는 부를 때마다 [RecordLoading] 으로 갈아탔다. 화면이 `switch` 로
  /// 세 갈래를 가르므로, 그 순간 **달력과 주간 기록이 통째로 버려지고 로딩
  /// 표시 하나만 남는다.** 돌아올 때는 새 위젯이라 달력이 펴 두었던 상태를
  /// 잃고 접힌 주간 뷰로 돌아갔다 — 달 이동 버튼은 **펴야만 보이므로**,
  /// 한 달 넘길 때마다 다시 펴야 했다.
  ///
  /// 그래서 **이미 읽은 것이 있으면 그대로 두고** 새 값이 오면 갈아 끼운다.
  /// 첫 진입·오류 뒤·계정이 바뀐 뒤에만 로딩을 보여준다 — 그때는 보여줄 것이 없다.
  ///
  /// ⚠️ 이 사이에는 **지난달 화면이 잠깐 그대로 보인다.** 달 이름이
  /// 늦게 바뀌는 셈인데, 통째로 깜빡이며 읽던 자리를 잃는 것보다 낫다고 봤다.
  Future<void> load({DateTime? month, DateTime? select}) async {
    final epoch = _accountEpoch;
    final now = ref.read(recordClockProvider)();
    final target = month == null
        ? DateTime(now.year, now.month)
        : DateTime(month.year, month.month);

    if (state is! RecordData) state = const RecordLoading();

    try {
      final selected = select == null
          ? _initialDay(target, now)
          : DateTime(select.year, select.month, select.day);

      // ⚠️ **두 7일이 겹치지 않는다.** 차트는 **오늘이 낀 월~일**이고 스트립은
      // **고른 날 ±3일**이다. 서로 다른 규칙이라 달 초·말에는 멀리 떨어진다.
      final days = weekOf(now);
      final strip = stripAround(selected);

      // ⚠️ **셋을 하나로 합치지 않는다.**
      //
      // 한 번에 물을 수 있는 구간이 **31일 미만**이다
      // ([RunRecordRepository.maxRangeDays]). 달 하나가 이미 그 상한에 딱
      // 걸리므로 여기에 하루만 더 붙여도 **서버까지 가지 못하고**
      // `invalidRequest` 로 떨어진다 — 달 양끝에 사흘씩 붙였다가 기기에서
      // `기록을 불러오지 못했어요` 를 봤다.
      //
      // 차트와 스트립을 묶는 것도 안전하지 않다. 지난달로 옮기면 차트는
      // **오늘이 낀 주**에 머물고 스트립은 그 달 1일로 가므로 둘이 한 달 넘게
      // 벌어진다. 7일씩 따로 묻는다.
      final monthLast = _lastDayOf(target);

      // 셋을 동시에 묻는다. 줄 세우면 왕복이 세 배다.
      final answers = await Future.wait([
        _repository.byDateRange(from: target, to: monthLast),
        _repository.byDateRange(from: days.first, to: days.last),
        _repository.byDateRange(from: strip.first, to: strip.last),
      ]);
      // 기다리는 사이 계정이 바뀌었으면 앞 사람의 기록이다. 버린다.
      if (epoch != _accountEpoch) return;

      state = RecordData(
        month: target,
        selectedDay: selected,
        monthRecords: answers[0],
        // 차트와 스트립이 겹치면 같은 러닝이 두 번 온다. **번호로 추린다** —
        // 그냥 이으면 스트립에 같은 줄이 둘 선다.
        rangeRecords: {
          for (final record in [...answers[1], ...answers[2]])
            record.id: record,
        }.values.toList(),
        weekDays: days,
        stripDays: strip,
      );
    } on RunRecordException catch (error) {
      if (epoch != _accountEpoch) return;
      debugPrint('[record] 기록을 못 읽었다 · ${error.failure}');
      state = RecordError(error.failure);
    }
  }

  /// 날짜를 고른다. 아래 목록이 그 날로 바뀐다.
  ///
  /// ## ⚠️ 보고 있는 달 밖이면 캘린더도 따라간다
  ///
  /// 주간 막대는 달 경계를 넘는다 — 9월 2일 수요일에 보는 이번 주는 8월 31일
  /// 월요일에 시작한다. 그 막대를 눌렀을 때 캘린더가 9월에 머물면 **고른 날이
  /// 캘린더 어디에도 표시되지 않는다.** 목록은 8월 31일이라 말하는데 캘린더는
  /// 아무 칸도 밝히지 않아, 두 화면이 서로 다른 말을 한다.
  ///
  /// 그 달을 새로 읽어야 한다 — 손에 든 것은 그 주 몫뿐이라 월 요약을 낼 수
  /// 없다. `‹ ›`로 달을 옮길 때와 같은 비용이고, 주 경계에 걸리는 날은 한 달에
  /// 며칠뿐이다.
  void select(DateTime day) {
    final current = state;
    if (current is! RecordData) return;

    final picked = DateTime(day.year, day.month, day.day);
    final sameMonth =
        picked.year == current.month.year &&
        picked.month == current.month.month;

    if (!sameMonth) {
      unawaited(load(month: picked, select: picked));
      return;
    }
    // 스트립은 **고른 날 한가운데**로 옮긴다. 차트(월~일)는 그대로다 —
    // 둘 다 따라가면 `이번 주`라는 뜻이 사라진다.
    final strip = stripAround(picked);
    state = current.copyWith(selectedDay: picked, stripDays: strip);

    // 달 안쪽은 이미 손에 있다(월 조회). **달 밖으로 넘친 사흘**만 없다 —
    // 1일이나 말일을 고르면 스트립이 이웃 달로 걸친다. 그 칸에 점이 안 찍히면
    // **모르는 것이 안 뛴 것처럼** 보이므로 뒤에서 채운다.
    if (_outside(strip.first, current.month) ||
        _outside(strip.last, current.month)) {
      unawaited(_fillStrip(strip));
    }
  }

  /// 스트립이 달 밖으로 걸친 구간을 받아 **갖고 있는 것에 더한다.**
  ///
  /// 화면을 비우지 않고 조용히 채우기만 한다. 실패해도 그대로 둔다 —
  /// 고른 날의 목록은 이미 보이고 있고, 여기서 오류 화면으로 갈아타면
  /// 사용자가 보던 것을 잃는다.
  Future<void> _fillStrip(List<DateTime> strip) async {
    final epoch = _accountEpoch;
    try {
      final extra = await _repository.byDateRange(
        from: strip.first,
        to: strip.last,
      );
      final current = state;
      // 그 사이 계정이 바뀌었거나 사용자가 다른 날·다른 달로 옮겼으면 버린다.
      if (epoch != _accountEpoch ||
          current is! RecordData ||
          current.stripDays.first != strip.first) {
        return;
      }
      state = current.copyWith(
        // 겹치는 날이 있으므로 **번호로 추린다.** 그냥 이으면 같은 러닝이
        // 스트립에 두 번 선다.
        rangeRecords: {
          for (final record in [...current.allRangeRecords, ...extra])
            record.id: record,
        }.values.toList(),
      );
    } on RunRecordException catch (error) {
      debugPrint('[record] 스트립 바깥을 못 읽었다 · ${error.failure}');
    }
  }

  /// [day]가 [month] 밖인가.
  static bool _outside(DateTime day, DateTime month) =>
      day.year != month.year || day.month != month.month;

  /// 이전·다음 달로 옮긴다. 그 달을 새로 읽는다.
  Future<void> moveMonth(int delta) {
    final current = state;
    final base = current is RecordData
        ? current.month
        : DateTime(
            ref.read(recordClockProvider)().year,
            ref.read(recordClockProvider)().month,
          );
    return load(month: DateTime(base.year, base.month + delta));
  }

  /// 그 달의 마지막 날.
  ///
  /// `DateTime(년, 월 + 1, 0)`은 **다음 달 0일** = 이번 달 말일이다. 말일을
  /// 28·30·31로 나눠 적으면 윤년에서 틀린다.
  static DateTime _lastDayOf(DateTime month) =>
      DateTime(month.year, month.month + 1, 0);

  /// 처음 고를 날.
  static DateTime _initialDay(DateTime month, DateTime now) {
    final isThisMonth = month.year == now.year && month.month == now.month;
    return isThisMonth
        ? DateTime(now.year, now.month, now.day)
        : DateTime(month.year, month.month);
  }
}

/// 화면이 목록만 필요할 때 쓰는 좁은 구독.
///
/// 상태 전체를 watch하면 달을 옮길 때 화면 전체가 다시 그려진다
/// (`implementation-notes` 5-3).
final selectedRecordsProvider = Provider<List<RunRecord>>((ref) {
  final state = ref.watch(recordControllerProvider);
  return state is RecordData ? state.selectedRecords : const <RunRecord>[];
});
