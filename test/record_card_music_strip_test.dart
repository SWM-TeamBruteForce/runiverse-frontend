import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/presentation/music_strip.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 음악 줄 (설계 6-5) — **지금 보고 있는 장의 곡**을 말한다.
///
/// 곡이 장마다 하나다(연동 가이드 2절). 묶음 5까지는 카드 하나에 상태가
/// 하나여서 줄도 카드 하나에 하나였다.
void main() {
  late FakeRecordCardRepository repo;

  setUp(() {
    repo = FakeRecordCardRepository(today: DateTime(2026, 11, 16));
  });

  Future<void> pump(
    WidgetTester tester, {
    CardMusic? music,
    bool hasFailed = false,
    bool playing = false,
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
              cardId: 'card-1003',
              music: music,
              hasFailed: hasFailed,
              playing: playing,
              canAdvance: canAdvance,
              canRequest: canRequest,
              onTogglePlay: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('남의 카드', () {
    testWidgets('⚠️ 다 된 곡만 선다 — 나머지는 자리를 비운다', (tester) async {
      // 생성 요청은 쓰기다. 못 하는 일을 적어 두면 쓸모없는 글이 남고,
      // 빈 40px만 남기면 그 자리가 고장으로 읽힌다.
      await pump(
        tester,
        music: const CardMusic(status: MusicStatus.failed),
        canRequest: false,
      );
      expect(find.byType(SizedBox).evaluate(), isNotEmpty);
      expect(find.text(AppStrings.recordCardMusicFailed), findsNothing);

      await pump(
        tester,
        music: const CardMusic(status: MusicStatus.generating),
        canRequest: false,
      );
      expect(find.text(AppStrings.recordCardMusicProcessing), findsNothing);
    });

    testWidgets('다 된 곡은 남의 카드에서도 들을 수 있다', (tester) async {
      await pump(
        tester,
        music: const CardMusic(status: MusicStatus.completed, url: 'https://x'),
        canRequest: false,
      );

      expect(find.text(AppStrings.recordCardMusicPlay), findsOne);
    });
  });

  group('지금 장의 곡', () {
    testWidgets('만드는 중이면 그렇게 말한다', (tester) async {
      await pump(
        tester,
        music: const CardMusic(status: MusicStatus.generating),
      );

      expect(find.text(AppStrings.recordCardMusicProcessing), findsOne);
    });

    testWidgets('⚠️ 아직 안 온 곡에는 아무 말도 하지 않는다', (tester) async {
      // 한 프레임일 수도 있는 구간에 글자를 세우면 열 때마다 번쩍인다.
      await pump(tester);

      expect(find.text(AppStrings.recordCardMusicProcessing), findsNothing);
      expect(find.text(AppStrings.recordCardMusicFailed), findsNothing);
      expect(find.text(AppStrings.recordCardMusicReady), findsNothing);
    });

    testWidgets('⚠️ 실패한 장에서는 다시 만들기를 준다', (tester) async {
      await pump(
        tester,
        music: const CardMusic(status: MusicStatus.failed),
        hasFailed: true,
      );

      expect(find.text(AppStrings.recordCardMusicFailed), findsOne);
      expect(find.text(AppStrings.recordCardMusicRetry), findsOne);
    });

    testWidgets('⚠️ 이 장이 안 왔어도 다른 장이 실패했으면 다시 걸 수 있다', (tester) async {
      // 재요청은 `FAILED`인 곡 전부를 다시 거는 것이다(가이드 4절). 이 장이
      // 아직 안 왔다고 그 길이 사라지면, 실패한 장으로 넘어가야만 누를 수 있다.
      await pump(tester, hasFailed: true);

      expect(find.text(AppStrings.recordCardMusicRetry), findsOne);
    });
  });

  group('다 된 곡', () {
    testWidgets('⚠️ 도는 중에는 멈춤을, 멈춰 있으면 재생을 권한다', (tester) async {
      const done = CardMusic(status: MusicStatus.completed, url: 'https://x');

      await pump(tester, music: done, playing: true);
      expect(find.text(AppStrings.recordCardMusicPause), findsOne);
      expect(find.byIcon(LucideIcons.pause), findsOne);

      await pump(tester, music: done);
      expect(find.text(AppStrings.recordCardMusicPlay), findsOne);
      expect(find.byIcon(LucideIcons.play), findsOne);
    });

    testWidgets('⚠️ 넘어갈 장이 없으면 버튼을 두지 않는다', (tester) async {
      // 사진이 없는 카드는 한 장뿐이라 타이머를 아예 걸지 않는다 — 그 자리에
      // 토글을 세우면 눌러도 아무 일도 없는 버튼이 된다.
      await pump(
        tester,
        music: const CardMusic(status: MusicStatus.completed, url: 'https://x'),
        canAdvance: false,
      );

      expect(find.text(AppStrings.recordCardMusicReady), findsOne);
      expect(find.text(AppStrings.recordCardMusicPlay), findsNothing);
    });

    testWidgets('라이트에서도 그려진다', (tester) async {
      await pump(
        tester,
        music: const CardMusic(status: MusicStatus.completed, url: 'https://x'),
        light: true,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.recordCardMusicPlay), findsOne);
    });
  });
}
