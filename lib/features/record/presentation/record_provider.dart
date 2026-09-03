import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/record/data/http_run_record_repository.dart';
import 'package:runiverse/features/record/domain/record_summary.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_state.dart';

/// 기록을 누가 읽어 오나.
///
/// ## ⚠️ 목록은 아직 서버가 없다
///
/// 상세(17·18번)는 열려 있지만 목록 19번(`GET /users/me/running-records`)은
/// `개발전`이다 — 서버가 `NoResourceFoundException`으로 답하는 것을 확인했다.
/// 목록이 필요한 테스트는 `FakeRunRecordRepository`를 덮어써서 쓴다.
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
/// `autoDispose`가 기본이라 화면을 닫으면 버려진다 — 상세는 무거워서
/// (구간이 10m 단위로 수백 개다) 들고 있을 이유가 없다.
final runDetailProvider = FutureProvider.family<RunDetail, int>(
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
/// ## ⚠️ 탭을 옮기면 다시 읽는다
///
/// 숨은 탭의 provider는 실제로 dispose된다(`implementation-notes` 5-1).
/// 기록은 러닝만큼 자주 바뀌지 않으므로 매번 다시 읽어도 무방하고, 오히려
/// 러닝을 마치고 돌아왔을 때 최신이라는 이점이 있다. **`keepAlive`를 붙이지
/// 않는 것이 의도다.**
class RecordController extends Notifier<RecordState> {
  @override
  RecordState build() {
    // build 안에서 await하지 않는다. 먼저 loading을 내보내고 뒤에서 읽는다.
    Future.microtask(load);
    return const RecordLoading();
  }

  RunRecordRepository get _repository => ref.read(runRecordRepositoryProvider);

  /// 이번 달과 이번 주를 읽는다.
  ///
  /// [month]를 주면 그 달을, [select]를 주면 읽은 뒤 그 날을 고른다.
  /// [select]가 없으면 이번 달이면 오늘, 지난달이면 1일이다.
  Future<void> load({DateTime? month, DateTime? select}) async {
    final now = ref.read(recordClockProvider)();
    final target = month == null
        ? DateTime(now.year, now.month)
        : DateTime(month.year, month.month);

    state = const RecordLoading();

    try {
      final days = weekOf(now);
      // 둘을 동시에 보낸다. 줄 세우면 왕복이 두 배가 된다.
      final results = await Future.wait([
        _repository.byDateRange(from: target, to: _lastDayOf(target)),
        _repository.byDateRange(from: days.first, to: days.last),
      ]);

      state = RecordData(
        month: target,
        selectedDay: select == null
            ? _initialDay(target, now)
            : DateTime(select.year, select.month, select.day),
        monthRecords: results[0],
        weekRecords: results[1],
        weekDays: days,
      );
    } on RunRecordException catch (error) {
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
    state = current.copyWith(selectedDay: picked);
  }

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
