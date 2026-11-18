import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/activity_filter.dart';
import 'package:runiverse/features/record_card/presentation/record_card_calendar.dart';
import 'package:runiverse/features/record_card/presentation/record_card_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

final _today = DateTime(2026, 11, 16);

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn('u-1', isOnboarded: true);
}

/// 카드가 한 장도 없는 저장소.
class _EmptyRepository implements RecordCardRepository {
  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

Future<void> _pump(
  WidgetTester tester, {
  RecordCardRepository? repository,
  bool light = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recordCardRepositoryProvider.overrideWithValue(
          repository ?? FakeRecordCardRepository(today: _today),
        ),
        // 달력이 러닝 기록도 받는다 — 실제 구현을 그대로 두면 dio와 토큰
        // 저장소를 끌어온다.
        runRecordRepositoryProvider.overrideWithValue(
          FakeRunRecordRepository(today: _today),
        ),
        recordCardClockProvider.overrideWithValue(() => _today),
        authControllerProvider.overrideWith(_Auth.new),
      ],
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: const RecordCardPage(),
      ),
    ),
  );
}

void main() {
  testWidgets('받는 동안 로딩을 보여준다', (tester) async {
    await _pump(
      tester,
      repository: FakeRecordCardRepository(
        today: _today,
        delay: const Duration(milliseconds: 50),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('받아 오면 달력이 선다', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(RecordCardCalendar), findsOneWidget);
  });

  testWidgets('실패하면 오류와 다시 시도가 뜬다', (tester) async {
    await _pump(
      tester,
      repository: FakeRecordCardRepository(
        today: _today,
        failWith: RecordCardFailure.network,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.recordCardError), findsOneWidget);
    expect(find.text(AppStrings.recordRetry), findsOneWidget);
    expect(find.byType(RecordCardCalendar), findsNothing);
  });

  testWidgets('⚠️ 카드가 하나도 없어도 달력은 남는다', (tester) async {
    await _pump(tester, repository: _EmptyRepository());
    await tester.pumpAndSettle();

    expect(find.byType(RecordCardCalendar), findsOneWidget);
    expect(find.text(AppStrings.recordCardEmptyTitle), findsOneWidget);
  });

  testWidgets('⚠️ 필터로 0장이 된 것은 빈 상태가 아니다', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.recordCardActivityRace));
    await tester.pumpAndSettle();

    // 카드는 있는데 유형 필터로 안 보일 뿐이다. 안내를 띄우면 필터 때문인 줄 모른다.
    expect(find.text(AppStrings.recordCardEmptyTitle), findsNothing);
  });

  testWidgets('유형 칩은 하나만 고를 수 있다', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.byType(ActivityFilter), findsOneWidget);
    expect(find.text(AppStrings.recordCardFilterAll), findsOneWidget);

    await tester.tap(find.text(AppStrings.recordCardActivityTravel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.recordCardActivityDaily));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('고른 칩을 다시 누르면 전체로 돌아온다', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.recordCardActivityDaily));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.recordCardActivityDaily));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await _pump(tester, light: true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(RecordCardCalendar), findsOneWidget);
  });
}
