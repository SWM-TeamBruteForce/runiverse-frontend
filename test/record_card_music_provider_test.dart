import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 목 카드 번호.
///
/// - `card-1000` 기본곡은 다 됐고 **첫 사진이 만드는 중**이다 → 폴링이 돈다.
/// - `card-1001` 기본곡이 **실패**해 있다 → 폴링이 안 돈다. 재요청 대상이다.
/// - `card-1003` 전부 **완료** → 폴링이 안 돈다.
const _working = 'card-1000';
const _failed = 'card-1001';
const _done = 'card-1003';

void main() {
  late DateTime now;
  late FakeRecordCardRepository repo;

  /// 시계를 민다. 가짜가 흐른 시간으로 곡 상태를 낸다.
  void advance(Duration by) => now = now.add(by);

  /// ⚠️ **구독을 둘 다 걸어 둔다.** 둘 다 `autoDispose`라 듣는 사람이 없으면
  /// `read` 직후 버려지고 다음 `read`가 **처음부터 다시** 세운다 — 화면에서는
  /// 위젯이 듣고 있어서 그 일이 없다.
  ProviderContainer open(String cardId) {
    final container = ProviderContainer(
      overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.listen(cardDetailProvider(cardId), (_, _) {});
    container.listen(cardMusicProvider(cardId), (_, _) {});
    return container;
  }

  /// 만드는 중인 카드를 끝까지 보내 타이머를 비운다. 남기면
  /// `!timersPending`으로 떨어진다.
  Future<void> finish(WidgetTester tester, String cardId) async {
    advance(const Duration(seconds: 13));
    await tester.pump(CardMusicController.firstInterval);
    await tester.pumpAndSettle();
  }

  setUp(() {
    now = DateTime(2026, 11, 16, 10);
    repo = FakeRecordCardRepository(
      today: DateTime(2026, 11, 16),
      clock: () => now,
    );
  });

  group('곡은 카드가 들고 온다', () {
    testWidgets('⚠️ 음악만 따로 묻지 않는다 — 상세 응답에 실려 온다', (tester) async {
      // 묶음 5까지는 `musicOf`로 따로 물었다. 가이드 2절이 곡을 상세에
      // 실어 주기로 하면서 그 길이 사라졌다.
      final container = open(_done);
      await tester.pumpAndSettle();

      final card = container.read(cardDetailProvider(_done)).value!;
      expect(card.baseMusic?.status, MusicStatus.completed);
      expect(card.isMusicWorking, isFalse);
    });

    testWidgets('⚠️ 곡 하나가 실패해도 카드는 열린다', (tester) async {
      final container = open(_failed);
      await tester.pumpAndSettle();

      final card = container.read(cardDetailProvider(_failed)).value!;
      expect(card.hasFailedMusic, isTrue);
      expect(card.reviewText, isNotEmpty, reason: '카드는 그대로 보인다');
    });
  });

  group('폴링', () {
    testWidgets('⚠️ 만드는 중이면 스스로 다시 읽는다 — 열어 둔 사람이 끝을 본다', (tester) async {
      final container = open(_working);
      await tester.pumpAndSettle();
      expect(
        container.read(cardDetailProvider(_working)).value!.isMusicWorking,
        isTrue,
      );

      // 서버 쪽에서 곡이 끝났다. 앱은 아직 모른다 — 완료를 알리는 푸시도
      // SSE도 없다(가이드 7절).
      await repo.retryMusic(_working);
      await finish(tester, _working);

      expect(
        container.read(cardDetailProvider(_working)).value!.isMusicWorking,
        isFalse,
      );
    });

    testWidgets('⚠️ 다 된 카드는 다시 묻지 않는다', (tester) async {
      final container = open(_done);
      await tester.pumpAndSettle();

      // 타이머가 걸려 있으면 `!timersPending`으로 떨어진다. 여기까지 왔으면
      // 안 걸렸다.
      expect(
        container.read(cardDetailProvider(_done)).value!.isMusicWorking,
        isFalse,
      );
    });

    testWidgets('⚠️ 실패한 카드도 다시 묻지 않는다 — 기다려도 안 바뀐다', (tester) async {
      final container = open(_failed);
      await tester.pumpAndSettle();

      expect(
        container.read(cardDetailProvider(_failed)).value!.isMusicWorking,
        isFalse,
      );
    });

    testWidgets('⚠️ 첫 간격은 10초고 1분까지 늘어난다', (tester) async {
      // 큐에서 오래 기다릴 수 있어(설계 3절) 짧은 간격은 배터리만 쓴다.
      // 가이드 7절이 "10초부터 최대 1분까지"라고 적었다.
      expect(CardMusicController.firstInterval, const Duration(seconds: 10));
      expect(CardMusicController.maxInterval, const Duration(minutes: 1));

      final container = open(_working);
      await tester.pumpAndSettle();

      // 9초로는 안 묻는다.
      await repo.retryMusic(_working);
      advance(const Duration(seconds: 13));
      await tester.pump(const Duration(seconds: 9));
      expect(
        container.read(cardDetailProvider(_working)).value!.isMusicWorking,
        isTrue,
        reason: '아직 10초가 지나지 않았다',
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        container.read(cardDetailProvider(_working)).value!.isMusicWorking,
        isFalse,
      );
    });
  });

  group('다시 만들기', () {
    testWidgets('보내면 만드는 중으로 바뀐다', (tester) async {
      final container = open(_failed);
      await tester.pumpAndSettle();

      await container.read(cardMusicProvider(_failed).notifier).retry();
      await tester.pumpAndSettle();

      expect(
        container.read(cardDetailProvider(_failed)).value!.isMusicWorking,
        isTrue,
      );

      await finish(tester, _failed);
    });

    testWidgets('⚠️ 두 번 눌러도 요청은 한 번이다', (tester) async {
      final container = open(_failed);
      await tester.pumpAndSettle();

      final notifier = container.read(cardMusicProvider(_failed).notifier);
      final before = repo.musicRequests;
      await Future.wait([notifier.retry(), notifier.retry()]);
      await tester.pumpAndSettle();

      expect(repo.musicRequests, before + 1);

      await finish(tester, _failed);
    });

    testWidgets('⚠️ 못 보냈으면 그렇다고 말한다 — 카드는 그대로다', (tester) async {
      final container = open(_failed);
      await tester.pumpAndSettle();

      repo.failWith = RecordCardFailure.network;
      await container.read(cardMusicProvider(_failed).notifier).retry();
      await tester.pumpAndSettle();

      expect(
        container.read(cardMusicProvider(_failed)),
        isA<CardMusicRetryFailed>(),
      );
      expect(
        container.read(cardDetailProvider(_failed)).value!.reviewText,
        isNotEmpty,
      );
    });
  });
}
