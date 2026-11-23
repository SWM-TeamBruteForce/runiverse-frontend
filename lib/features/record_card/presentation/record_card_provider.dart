import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/data/http_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

/// 기록카드를 누가 읽어 오나.
///
/// ## ⚠️ **저장만 아직 가짜다**
///
/// 읽기(달력 7-1 · 상세 8-1 · 프로필 10-3)와 삭제(9-4) · 음악 재요청(9-6)은
/// 진짜 서버로 간다. **새 카드 저장과 수정은 서버에 가지 않는다** — 9-1 → S3
/// → 9-2 흐름이 묶음 8이다. 앱을 끄면 그렇게 만든 카드는 사라진다.
///
/// 기기에서 볼 때 그 차이를 기억해야 한다: 달력·상세·프로필은 **서버가 가진
/// 것**이고, 저장한 카드는 **이 기기 안에만** 있다.
final recordCardRepositoryProvider = Provider<RecordCardRepository>(
  (ref) => HttpRecordCardRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
    // 묶음 8까지 저장·수정을 맡는다.
    fallback: FakeRecordCardRepository(),
  ),
);

/// "오늘"이 언제인가. 테스트가 고정된 날짜를 넣는다.
///
/// `DateTime.now()`를 컨트롤러에서 직접 부르면 자정 근처에서 테스트가 흔들리고,
/// 어느 달을 받아 왔는지 검증할 수 없다.
final recordCardClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final recordCardControllerProvider =
    NotifierProvider<RecordCardController, RecordCardState>(
      RecordCardController.new,
    );

/// 기록카드 탭의 데이터를 모은다.
///
/// ## ⚠️ 받은 달은 다시 받지 않는다
///
/// 달력이 월 ⇄ 분기로 오가고 유형 필터도 붙지만, **둘 다 요청을 만들지
/// 않는다.** 들고 있는 [RecordCardData.months]를 걸러서 쓸 뿐이다. 분기 보기는
/// "새로 3개월을 받는 것"이 아니라 "이미 받은 달 셋을 작게 그리는 것"이다.
///
/// ## ⚠️ 달마다 한 번씩 묻는다
///
/// 한 번에 [RecordCardRepository.maxRangeDays]를 넘길 수 없다. 세 달이면
/// 세 번이다.
///
/// ## ⚠️ 달마다 요청이 둘이다 — 카드와 러닝 기록
///
/// 달력은 뛰었는데 카드를 안 쓴 날에 운동화를 둬야 한다(설계 6-1). 그 날이
/// 어디인지는 카드 조회가 알려 주지 않아 **러닝 기록을 따로 받는다.** 둘은
/// 동시에 던진다 — 줄 세우면 왕복이 두 배다.
class RecordCardController extends Notifier<RecordCardState> {
  /// 한 번에 받아 오는 달 수.
  static const _batchMonths = 3;

  /// 계정 차수. 계정이 바뀔 때마다 올라간다 — 그 전에 떠난 조회의 답을 가린다.
  var _accountEpoch = 0;

  /// 더 받는 중인가.
  ///
  /// ⚠️ **없으면 스크롤이 멈춘 것처럼 보인다.** 달력이 바닥에 닿으면 스크롤하는
  /// 내내 매 프레임 [loadOlder]를 부르는데, 그때마다 상태가 바뀌어 목록이 계속
  /// 다시 그려진다. 에뮬레이터에서 실제로 그렇게 멈췄다(2026-11-16).
  var _loadingOlder = false;

  /// 더 과거에는 아무것도 없다.
  var _atOldest = false;

  @override
  RecordCardState build() {
    _watchAccount();
    // build 안에서 await하지 않는다. 먼저 loading을 내보내고 뒤에서 읽는다.
    Future.microtask(load);
    return const RecordCardLoading();
  }

  /// 이번 달을 포함한 최근 [_batchMonths]개월을 받는다. 오류 화면의 다시 시도도
  /// 이것을 부른다.
  Future<void> load() {
    _loadingOlder = false;
    _atOldest = false;
    final now = ref.read(recordCardClockProvider)();
    return _fetch([
      for (var back = _batchMonths - 1; back >= 0; back--)
        DateTime(now.year, now.month - back),
    ], reset: true);
  }

  /// 들고 있는 것보다 더 과거 [_batchMonths]개월을 덧붙인다.
  ///
  /// 달력이 바닥에 닿을 때마다 불린다 — **같은 요청이 겹치지 않게 막고**, 받아
  /// 온 묶음이 통째로 비어 있으면 더 파고들지 않는다.
  /// [force]면 **더 없다고 본 뒤에도 한 번 더 판다.** 석 달을 통째로 쉰 사람의
  /// 그 앞에 카드가 있을 수 있어, 사용자가 요구하면 들어준다.
  Future<void> loadOlder({bool force = false}) async {
    final current = state;
    if (_loadingOlder) return;
    if (_atOldest && !force) return;
    if (current is! RecordCardData || current.months.isEmpty) return;

    final earliest = current.months.first.month;
    final wanted = [
      for (var back = _batchMonths; back >= 1; back--)
        DateTime(earliest.year, earliest.month - back),
    ];

    _loadingOlder = true;
    try {
      await _fetch(wanted, reset: false);

      // ⚠️ **빈 묶음이 왔으면 거기가 끝이다.** 안 멈추면 과거로 영원히 파고들며
      // 빈 달을 붙인다. 석 달을 통째로 쉰 사람은 그 앞도 못 보게 되는데, 볼
      // 것이 없으므로 보이는 결과는 같다. 서버가 "더 있다"를 알려 주면 그걸 쓴다.
      final next = state;
      if (next is RecordCardData) {
        final added = next.months.where((m) => wanted.contains(m.month));
        _atOldest = added.every((month) => month.cardCount == 0);
        state = next.copyWith(atOldest: _atOldest);
      }
    } finally {
      _loadingOlder = false;
    }
  }

  /// `null`이면 전체다. **서버를 부르지 않는다.**
  void setFilter(RecordCardActivity? activity) {
    final current = state;
    if (current is! RecordCardData) return;
    state = current.copyWith(filter: activity, clearFilter: activity == null);
  }

  /// **서버를 부르지 않는다.** 이미 받은 달을 작게 그릴 뿐이다.
  void setZoom(CalendarZoom zoom) {
    final current = state;
    if (current is! RecordCardData) return;
    state = current.copyWith(zoom: zoom);
  }

  Future<void> _fetch(List<DateTime> wanted, {required bool reset}) async {
    final epoch = _accountEpoch;
    final previous = reset || state is! RecordCardData
        ? null
        : state as RecordCardData;
    final existing = previous?.months ?? const [];
    final already = previous?.loadedMonths ?? const <DateTime>{};
    final repository = ref.read(recordCardRepositoryProvider);

    try {
      final fetched = <MonthCards>[];
      for (final month in wanted) {
        // 이미 들고 있는 달은 건너뛴다.
        if (already.contains(month)) continue;
        // ⚠️ **요청이 하나다.** 7-1이 러닝 기록과 카드 유무를 함께 주므로
        // (연동 가이드 1절) 묶음 6까지의 `Future.wait` 두 갈래가 사라졌다.
        fetched.add(
          MonthCards(
            month: month,
            runs: await repository.runsInRange(
              from: month,
              to: _lastDayOf(month),
            ),
          ),
        );
      }

      if (epoch != _accountEpoch) return;
      state = RecordCardData(
        months: [...existing, ...fetched],
        filter: previous?.filter,
        zoom: previous?.zoom ?? CalendarZoom.month,
      );
    } on RecordCardException catch (error) {
      if (epoch != _accountEpoch) return;
      // ⚠️ **더 받다 실패했다고 들고 있던 달력을 갈아치우지 않는다.** 지하철에서
      // 한 번 끊겼다고 잘 보던 여섯 달이 사라지고 필터까지 풀리면 안 된다.
      // 오류 화면은 처음 받기(`reset`)가 실패했을 때만이다.
      if (previous != null) return;
      state = RecordCardError(error.failure);
    }
  }

  /// 계정이 바뀌면 들고 있던 카드를 버리고, 로그인 상태면 다시 읽는다.
  ///
  /// ⚠️ 이 provider는 로그아웃해도 살아 있고 [build]가 다시 돌지 않는다. 앱을
  /// 끄지 않고 다른 계정으로 들어오면 **앞 사람의 카드가 그대로 보이고**, 그 카드를
  /// 누르면 서버가 403으로 막는다. 기록 탭이 같은 함정을 적어 두었다
  /// (`record_provider.dart`).
  void _watchAccount() {
    ref.listen(
      authControllerProvider.select(
        (auth) => auth is AuthSignedIn ? auth.userId : null,
      ),
      (_, userId) {
        _accountEpoch++;
        state = const RecordCardLoading();
        if (userId != null) unawaited(load());
      },
    );
  }

  /// 그 달의 마지막 날. 다음 달 0일이 이번 달 말일이다.
  static DateTime _lastDayOf(DateTime month) =>
      DateTime(month.year, month.month + 1, 0);
}
