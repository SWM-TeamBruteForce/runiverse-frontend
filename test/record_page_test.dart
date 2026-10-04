import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_calendar.dart';
import 'package:runiverse/features/record/presentation/record_day_list.dart';
import 'package:runiverse/features/record/presentation/record_page.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record/presentation/record_week_chart.dart';

/// 기록 탭이 **지금** 지키는 것.
///
/// ## ⚠️ 옮기기 전에 치는 그물이다
///
/// 이 화면은 854줄인데 위젯 테스트가 하나도 없었다. 다음 PR 이 주간 차트를
/// 면적 그래프로, 월 달력을 가로 스트립으로 **다시 만든다** — 그물 없이
/// 그렇게 하면 무엇이 사라졌는지 아무도 모른다.
///
/// 그래서 **지금 동작을 고정하는 것이 목적이 아니다.** 여기 적힌 것은 화면이
/// 바뀌어도 **지켜야 하는 약속**이고, 모양에 묶이지 않게 글자와 동작으로만
/// 적는다.
void main() {
  /// 기록이 하나도 없는 저장소. 빈 상태를 보려고 쓴다.
  final empty = _EmptyRecords();

  Future<void> pump(
    WidgetTester tester, {
    RunRecordRepository? repository,
    DateTime? today,
  }) async {
    final now = today ?? DateTime(2026, 9, 30);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(
            repository ?? FakeRunRecordRepository(today: now),
          ),
          // ⚠️ `DateTime.now()`를 그대로 두면 자정 근처에서 흔들리고, 주간
          // 차트가 어느 7일인지 검증할 수 없다.
          recordClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const RecordPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// ⚠️ **`ListView` 는 화면 밖 자식을 짓지 않는다.**
  ///
  /// 차트와 달력이 먼저 자리를 차지해서 그 아래 것들은 스크롤해야 생긴다.
  /// 안 하면 "없다"와 "안 보인다"가 구분되지 않는다.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  group('세 갈래를 다 그린다', () {
    testWidgets('⚠️ 불러오는 동안 기다리는 표시가 있다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runRecordRepositoryProvider.overrideWithValue(
              FakeRunRecordRepository(
                today: DateTime(2026, 9, 30),
                delay: const Duration(milliseconds: 50),
              ),
            ),
            recordClockProvider.overrideWithValue(() => DateTime(2026, 9, 30)),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const RecordPage()),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('데이터가 오면 차트와 달력을 그린다', (tester) async {
      await pump(tester);

      expect(find.byType(RecordWeekChart), findsOneWidget);
      expect(find.byType(RecordCalendar), findsOneWidget);
    });

    testWidgets('⚠️ 못 불러오면 다시 시도할 길을 준다', (tester) async {
      // 빈 목록과 **구분되어야** 한다. 오류를 빈 상태로 그리면 사용자가
      // 기록이 사라진 줄 안다(📅 기록 탭 연동 가이드 6장).
      await pump(tester, repository: _FailingRecords());

      expect(find.text(AppStrings.recordError), findsOneWidget);
      expect(find.text(AppStrings.recordRetry), findsOneWidget);
    });
  });

  group('빈 상태', () {
    testWidgets('⚠️ 그 달에 기록이 없으면 그렇다고 말한다', (tester) async {
      // **오류가 아니다.** 기간에 기록이 없으면 서버가 빈 배열을 준다.
      await pump(tester, repository: empty);
      await scrollTo(tester, find.text(AppStrings.recordMonthEmpty));

      expect(find.text(AppStrings.recordMonthEmpty), findsOneWidget);
      expect(find.text(AppStrings.recordError), findsNothing);
    });

    testWidgets('⚠️ 기록이 없어도 차트와 달력은 남는다', (tester) async {
      // 화면이 통째로 비면 "아직 아무것도 없다"가 아니라 **고장**으로 읽힌다.
      await pump(tester, repository: empty);

      expect(find.byType(RecordWeekChart), findsOneWidget);
      expect(find.byType(RecordCalendar), findsOneWidget);
    });
  });

  group('⚠️ 안 뛴 날이 사라지지 않는다', () {
    // 옛 규칙은 **"안 뛴 날에 막대가 서지 않는다"**였다(디자인 시스템 v1.1
    // §5-5, 잔디의 죄책감 문제). 그 제약은 2026-10-04 에 걷혔다 — 화면
    // 정본이 Figma 시안으로 바뀌었고 주간 기록이 **면적 그래프**가 됐다.
    //
    // 지키려던 것은 남는다: **안 뛴 날이 결손으로 읽히지 않을 것.**
    // 면적 그래프에서는 그 날도 점을 찍고 선이 바닥을 지나간다.

    testWidgets('⚠️ 기록이 하나도 없어도 요일 일곱 칸이 남는다', (tester) async {
      // 칸을 지우면 어디가 빈 날인지 읽을 수 없다.
      await pump(tester, repository: empty);

      for (final label in AppStrings.recordWeekdays) {
        expect(
          find.descendant(
            of: find.byType(RecordWeekChart),
            matching: find.text(label),
          ),
          findsWidgets,
          reason: '$label 칸이 없다',
        );
      }
    });

    testWidgets('⚠️ 안 뛴 날의 칸도 눌린다', (tester) async {
      // 누를 수 없으면 그 날은 없는 것과 같다. 빈 날을 골라야 "이 날은
      // 달리지 않았어요"를 볼 수 있다.
      await pump(tester, repository: empty);

      final column = find.descendant(
        of: find.byType(RecordWeekChart),
        matching: find.byType(GestureDetector),
      );

      expect(column, findsNWidgets(AppStrings.recordWeekdays.length));
      await tester.tap(column.first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('날짜 고르기', () {
    testWidgets('⚠️ 안 뛴 날을 고르면 그 날은 비었다고 말한다', (tester) async {
      await pump(tester, repository: empty);
      await scrollTo(tester, find.text(AppStrings.recordMonthEmpty));

      // 달에 기록이 없으면 날짜별 목록 대신 한 줄로 알린다.
      expect(find.byType(RecordDayList), findsNothing);
      expect(find.text(AppStrings.recordMonthEmpty), findsOneWidget);
    });

    testWidgets('⚠️ 기록이 있는 날을 고르면 그날 것만 보인다', (tester) async {
      await pump(tester);
      await scrollTo(tester, find.byType(RecordDayList));

      expect(find.byType(RecordDayList), findsOneWidget);
    });
  });
}

/// 기록이 하나도 없는 저장소.
class _EmptyRecords implements RunRecordRepository {
  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<Never> byRoom(int runningRoomId) async =>
      throw const RunRecordException(RunRecordFailure.notFound);
}

/// 늘 실패하는 저장소.
class _FailingRecords implements RunRecordRepository {
  @override
  Future<Never> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => throw const RunRecordException(RunRecordFailure.network);

  @override
  Future<Never> byRoom(int runningRoomId) async =>
      throw const RunRecordException(RunRecordFailure.network);
}
