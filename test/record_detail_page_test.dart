import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/run_map_view.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record/domain/run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_detail_page.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record/presentation/run_result_view.dart';

/// 기록 상세가 **지금** 지키는 것.
///
/// ## ⚠️ 옮기기 전에 치는 그물이다
///
/// 이 화면은 `record_detail_page`(160) + `run_result_view`(848) +
/// `split_line_chart`(593)로 **1,601줄**인데 위젯 테스트가 하나도 없었다.
///
/// 다음 PR 은 **토큰만 갈아끼운다.** 그래도 치는 이유는 CLAUDE.md 가 금지한
/// 둘 — **파티원 GPS 노출**과 **순위 표시** — 이 여기 걸려 있어서다. 색과
/// 타이포를 고치다 실수로 되살릴 수 있고, 그것은 눈으로 안 띈다.
void main() {
  RunPlayerResult player(
    String id, {
    required bool isMe,
    int? meters = 5000,
    Duration? pace = const Duration(seconds: 330),
  }) => RunPlayerResult(
    userId: id,
    nickname: '러너$id',
    isMe: isMe,
    distanceMeters: meters,
    duration: const Duration(minutes: 28),
    averagePace: pace,
  );

  RunDetail detail({
    List<RunPlayerResult>? players,
    int? cadence,
    int? calories,
  }) => RunDetail(
    runningRoomId: 125,
    distanceMeters: 5020,
    duration: const Duration(minutes: 28),
    rawSplits: const [],
    averagePace: const Duration(seconds: 330),
    cadenceSpm: cadence,
    caloriesKcal: calories,
    players: players ?? [player('1', isMe: true), player('2', isMe: false)],
  );

  Future<void> pump(
    WidgetTester tester, {
    RunRecordRepository? repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runRecordRepositoryProvider.overrideWithValue(
            repository ?? _StubDetail(detail()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const RecordDetailPage(runningRoomId: 125),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('세 갈래를 다 그린다', () {
    testWidgets('⚠️ 불러오는 동안 기다리는 표시가 있다', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runRecordRepositoryProvider.overrideWithValue(
              _StubDetail(detail(), delay: const Duration(milliseconds: 50)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const RecordDetailPage(runningRoomId: 125),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('데이터가 오면 결과를 그린다', (tester) async {
      await pump(tester);

      expect(find.byType(RunResultView), findsOneWidget);
    });

    testWidgets('⚠️ 못 읽으면 그렇다고 말한다', (tester) async {
      await pump(tester, repository: _FailingDetail(RunRecordFailure.network));

      expect(find.byType(RunResultView), findsNothing);
      expect(find.text(AppStrings.recordRetry), findsOneWidget);
    });

    testWidgets('⚠️ 다시 시도해도 같은 답인 오류는 재시도를 권하지 않는다', (tester) async {
      // 404·403 은 기다린다고 생기지 않는다. 재시도를 권하면 몇 번을 눌러도
      // 같은 화면만 돌아온다.
      await pump(tester, repository: _FailingDetail(RunRecordFailure.notFound));

      expect(find.text(AppStrings.recordDetailMissing), findsOneWidget);
      expect(find.text(AppStrings.recordRetry), findsNothing);
    });
  });

  group('⚠️ CLAUDE.md 가 금지한 것', () {
    testWidgets('⚠️ 순위 숫자를 붙이지 않는다', (tester) async {
      // **경쟁이 아니라 동행 프레임이다.** 1등·2등을 적는 순간 같이 달린
      // 일이 겨룬 일이 된다. 순서도 서버가 준 그대로 둔다.
      await pump(tester);

      for (final rank in ['1등', '2등', '3등', '1위', '2위', '3위']) {
        expect(find.textContaining(rank), findsNothing, reason: '$rank 가 보인다');
      }
    });

    testWidgets('⚠️ 파티원의 경로를 그리지 않는다', (tester) async {
      // GPS 좌표·경로는 **어떤 화면·API로도** 파티원에게 내보내지 않는다.
      // 지도에 올리는 것은 `detail.track`(내 것) 하나뿐이다.
      await pump(tester);

      final maps = tester.widgetList(find.byType(RunMapView));
      expect(maps, hasLength(1), reason: '지도가 둘 이상이면 남의 경로가 섞인다');
    });
  });

  group('⚠️ 없는 값을 지어내지 않는다', () {
    testWidgets('케이던스를 모르면 0 으로 적지 않는다', (tester) async {
      await pump(tester);

      expect(find.text('0 spm'), findsNothing);
      expect(find.text('0spm'), findsNothing);
    });

    testWidgets('칼로리를 모르면 0 으로 적지 않는다', (tester) async {
      await pump(tester);

      expect(find.text('0 kcal'), findsNothing);
      expect(find.text('0kcal'), findsNothing);
    });

    testWidgets('⚠️ 기록이 없는 파티원을 0km 로 적지 않는다', (tester) async {
      // 있지만 수치가 전부 `null`인 사람이 있다 — 아직 뛰는 중이거나 기록이
      // 안 들어왔다. **0km 를 달린 것이 아니다.**
      await pump(
        tester,
        repository: _StubDetail(
          detail(
            players: [
              player('1', isMe: true),
              player('2', isMe: false, meters: null, pace: null),
            ],
          ),
        ),
      );

      expect(find.text('0.00km'), findsNothing);
    });
  });
}

/// 늘 같은 상세를 주는 저장소.
class _StubDetail implements RunRecordRepository {
  _StubDetail(this.detail, {this.delay = Duration.zero});

  final RunDetail detail;
  final Duration delay;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<RunDetail> byRoom(int runningRoomId) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return detail;
  }
}

/// 늘 실패하는 저장소.
class _FailingDetail implements RunRecordRepository {
  _FailingDetail(this.failure);

  final RunRecordFailure failure;

  @override
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => const [];

  @override
  Future<Never> byRoom(int runningRoomId) async =>
      throw RunRecordException(failure);
}
