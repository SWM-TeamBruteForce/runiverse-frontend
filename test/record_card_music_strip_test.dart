import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';
import 'package:runiverse/features/record_card/presentation/music_strip.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 목 카드 번호. 상태가 심어져 있다(`FakeRecordCardRepository._seeded`).
const _processing = 'card-1000';
const _failed = 'card-1001';
const _none = 'card-1002';
const _done = 'card-1003';

void main() {
  late DateTime now;
  late FakeRecordCardRepository repo;
  late int toggles;

  setUp(() {
    now = DateTime(2026, 11, 16, 10);
    toggles = 0;
    repo = FakeRecordCardRepository(
      today: DateTime(2026, 11, 16),
      clock: () => now,
    );
  });

  /// 줄 하나를 세운다. **`pumpAndSettle`을 쓰지 않는다** — 진행 표시가 서면
  /// 영영 끝나지 않는다.
  Future<void> pump(
    WidgetTester tester, {
    required String cardId,
    bool playing = true,
    bool canAdvance = true,
    bool canRequest = true,
    bool light = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: light ? AppTheme.light() : AppTheme.dark(),
          home: Scaffold(
            body: MusicStrip(
              cardId: cardId,
              playing: playing,
              canAdvance: canAdvance,
              canRequest: canRequest,
              onTogglePlay: () => toggles++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('⚠️ 요청할 수 없으면 만들 수 없는 상태에서 자리를 비운다', (tester) async {
    // 남의 카드다. 빈 40px를 남기면 그 자리가 고장으로 읽힌다.
    await pump(tester, cardId: _none, canRequest: false);

    expect(find.text(AppStrings.recordCardMusicCreate), findsNothing);
    expect(tester.getSize(find.byType(MusicStrip)).height, 0);
  });

  testWidgets('⚠️ 요청할 수 없어도 다 된 음악은 줄이 선다', (tester) async {
    await pump(tester, cardId: _done, canRequest: false);

    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);
  });

  testWidgets('만들지 않은 카드는 만들라고 권한다', (tester) async {
    await pump(tester, cardId: _none);

    expect(find.text(AppStrings.recordCardMusicCreate), findsOneWidget);
  });

  testWidgets('누르면 요청이 나간다', (tester) async {
    await pump(tester, cardId: _none);

    await tester.tap(find.text(AppStrings.recordCardMusicCreate));
    await tester.pump();

    expect(repo.musicRequests, 1);
    expect(find.text(AppStrings.recordCardMusicQueued), findsOneWidget);
  });

  testWidgets('⚠️ 만드는 중은 말만 한다 — 누를 것이 없다', (tester) async {
    await pump(tester, cardId: _processing);

    expect(find.text(AppStrings.recordCardMusicProcessing), findsOneWidget);
    expect(find.text(AppStrings.recordCardMusicRetry), findsNothing);
    expect(find.text(AppStrings.recordCardMusicPlay), findsNothing);
  });

  testWidgets('⚠️ 도는 중이면 멈춤이고, 멈춰 있으면 재생이다', (tester) async {
    await pump(tester, cardId: _done);
    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);
    expect(find.text(AppStrings.recordCardMusicPlay), findsNothing);

    await pump(tester, cardId: _done, playing: false);
    expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
    expect(find.text(AppStrings.recordCardMusicPause), findsNothing);
  });

  testWidgets('재생을 누르면 바깥이 듣는다', (tester) async {
    await pump(tester, cardId: _done, playing: false);

    await tester.tap(find.text(AppStrings.recordCardMusicPlay));
    await tester.pump();

    expect(toggles, 1);
  });

  testWidgets('실패하면 다시 만들기가 선다', (tester) async {
    await pump(tester, cardId: _failed);

    expect(find.text(AppStrings.recordCardMusicFailed), findsOneWidget);
    expect(find.text(AppStrings.recordCardMusicRetry), findsOneWidget);
  });

  testWidgets('다시 만들기를 누르면 요청이 나간다', (tester) async {
    await pump(tester, cardId: _failed);

    await tester.tap(find.text(AppStrings.recordCardMusicRetry));
    await tester.pump();

    expect(repo.musicRequests, 1);
    expect(find.text(AppStrings.recordCardMusicQueued), findsOneWidget);

    // 폴링 타이머를 남기지 않는다.
    now = now.add(const Duration(seconds: 13));
    await tester.pump(CardMusicController.pollInterval);
  });

  testWidgets('못 읽었으면 오류를 말하고 다시 묻게 한다', (tester) async {
    repo.failWith = RecordCardFailure.network;
    await pump(tester, cardId: _done);

    expect(find.text(AppStrings.recordCardMusicError), findsOneWidget);

    repo.failWith = null;
    await tester.tap(find.text(AppStrings.recordCardMusicReload));
    await tester.pump();

    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);
  });

  testWidgets('⚠️ 받는 동안에도 줄 높이가 같다 — 아래가 튀지 않는다', (tester) async {
    repo = FakeRecordCardRepository(
      today: DateTime(2026, 11, 16),
      clock: () => now,
      delay: const Duration(milliseconds: 50),
    );
    await pump(tester, cardId: _done);

    final loading = tester.getSize(find.byType(MusicStrip)).height;

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);
    expect(tester.getSize(find.byType(MusicStrip)).height, loading);
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await pump(tester, cardId: _failed, light: true);

    expect(find.text(AppStrings.recordCardMusicFailed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⚠️ 스크린리더가 무슨 줄인지 읽는다 — 아이콘만 서는 구간이 있다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, cardId: _done);

    expect(
      find.bySemanticsLabel(RegExp(AppStrings.recordCardMusicSemantics)),
      findsWidgets,
    );

    handle.dispose();
  });

  testWidgets('⚠️ 요청이 날아가는 동안 줄이 그 말을 한다 — 같은 라벨로 서 있지 않는다', (tester) async {
    repo = FakeRecordCardRepository(
      today: DateTime(2026, 11, 16),
      clock: () => now,
      delay: const Duration(milliseconds: 50),
    );
    await pump(tester, cardId: _none);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    await tester.tap(find.text(AppStrings.recordCardMusicCreate));
    await tester.pump();

    expect(find.text(AppStrings.recordCardMusicRequesting), findsOneWidget);
    expect(find.text(AppStrings.recordCardMusicCreate), findsNothing);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.text(AppStrings.recordCardMusicQueued), findsOneWidget);

    now = now.add(const Duration(seconds: 13));
    await tester.pump(CardMusicController.pollInterval);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
  });

  testWidgets('⚠️ 요청 중에는 다시 눌려도 아무 일도 없다', (tester) async {
    repo = FakeRecordCardRepository(
      today: DateTime(2026, 11, 16),
      clock: () => now,
      delay: const Duration(milliseconds: 50),
    );
    await pump(tester, cardId: _none);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    await tester.tap(find.text(AppStrings.recordCardMusicCreate));
    await tester.pump();
    // 줄이 버튼이 아니므로 두 번째 탭이 들어갈 자리가 없다.
    await tester.tap(find.text(AppStrings.recordCardMusicRequesting));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(repo.musicRequests, 1);

    now = now.add(const Duration(seconds: 13));
    await tester.pump(CardMusicController.pollInterval);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
  });
}
