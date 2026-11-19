import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 목 카드 번호. 1002는 음악이 없고, 1003은 다 돼 있다.
const _noMusic = 1002;
const _done = 1003;

void main() {
  late DateTime now;
  late FakeRecordCardRepository repo;

  /// 시계를 민다. 가짜가 흐른 시간으로 상태를 낸다.
  void advance(Duration by) => now = now.add(by);

  /// ⚠️ **구독을 걸어 둔다.** 이 provider는 `autoDispose`라, 듣는 사람이
  /// 없으면 `read` 직후 버려지고 다음 `read`가 **처음부터 다시** 세운다 —
  /// 화면에서는 위젯이 듣고 있어서 그 일이 없다.
  ProviderContainer open(int cardId) {
    final container = ProviderContainer(
      overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.listen(cardMusicProvider(cardId), (_, _) {});
    return container;
  }

  setUp(() {
    now = DateTime(2026, 11, 16, 10);
    repo = FakeRecordCardRepository(
      today: DateTime(2026, 11, 16),
      clock: () => now,
    );
  });

  testWidgets('열면 받아 온다', (tester) async {
    final container = open(_done);

    expect(container.read(cardMusicProvider(_done)), isA<CardMusicLoading>());

    await tester.pump();

    final state = container.read(cardMusicProvider(_done));
    expect(state, isA<CardMusicData>());
    expect(
      (state as CardMusicData).generation.status,
      MusicStatus.succeeded,
    );
  });

  testWidgets('⚠️ 만드는 중이면 스스로 다시 묻는다 — 열어 둔 사람이 끝을 본다', (
    tester,
  ) async {
    final container = open(_noMusic);
    await container.read(cardMusicProvider(_noMusic).notifier).request();

    expect(
      (container.read(cardMusicProvider(_noMusic)) as CardMusicData)
          .generation
          .status,
      MusicStatus.queued,
    );

    // 가짜는 3초에 PROCESSING, 13초에 SUCCEEDED다.
    advance(const Duration(seconds: 4));
    await tester.pump(CardMusicController.pollInterval);
    await tester.pump();
    expect(
      (container.read(cardMusicProvider(_noMusic)) as CardMusicData)
          .generation
          .status,
      MusicStatus.processing,
    );

    advance(const Duration(seconds: 10));
    await tester.pump(CardMusicController.pollInterval);
    await tester.pump();
    expect(
      (container.read(cardMusicProvider(_noMusic)) as CardMusicData)
          .generation
          .status,
      MusicStatus.succeeded,
    );
  });

  testWidgets('⚠️ 다 되면 더 묻지 않는다', (tester) async {
    final container = open(_done);
    container.read(cardMusicProvider(_done));
    await tester.pump();

    final before = repo.musicCalls;
    await tester.pump(CardMusicController.pollInterval * 5);

    expect(repo.musicCalls, before, reason: '다 된 뒤에도 물었다');
  });

  testWidgets('⚠️ 닫으면 폴링이 멈춘다', (tester) async {
    final container = ProviderContainer(
      overrides: [recordCardRepositoryProvider.overrideWithValue(repo)],
    );
    container.listen(cardMusicProvider(_noMusic), (_, _) {});
    await container.read(cardMusicProvider(_noMusic).notifier).request();
    final before = repo.musicCalls;

    container.dispose();
    await tester.pump(CardMusicController.pollInterval * 5);

    expect(repo.musicCalls, before, reason: '닫았는데 계속 물었다');
  });

  testWidgets('⚠️ 두 번 연타해도 요청은 한 번이다', (tester) async {
    final container = open(_noMusic);
    final controller = container.read(cardMusicProvider(_noMusic).notifier);

    await Future.wait([controller.request(), controller.request()]);

    expect(repo.musicRequests, 1);

    // ⚠️ **폴링 타이머를 남기고 끝내면 테스트가 실패한다**(`!timersPending`).
    // 끝까지 흘려 보내 끝 상태로 세운다.
    advance(const Duration(seconds: 13));
    await tester.pump(CardMusicController.pollInterval);
  });

  testWidgets('못 읽었으면 오류로 세운다', (tester) async {
    repo.failWith = RecordCardFailure.network;
    final container = open(_done);

    container.read(cardMusicProvider(_done));
    await tester.pump();

    final state = container.read(cardMusicProvider(_done));
    expect(state, isA<CardMusicError>());
    expect((state as CardMusicError).failure, RecordCardFailure.network);
  });

  testWidgets('⚠️ 오류 뒤에는 폴링하지 않는다 — 끊긴 망을 3초마다 두드리지 않는다', (
    tester,
  ) async {
    repo.failWith = RecordCardFailure.network;
    final container = open(_done);
    container.read(cardMusicProvider(_done));
    await tester.pump();

    final before = repo.musicCalls;
    await tester.pump(CardMusicController.pollInterval * 5);

    expect(repo.musicCalls, before);
  });

  testWidgets('오류에서 다시 누르면 다시 받아 온다', (tester) async {
    repo.failWith = RecordCardFailure.network;
    final container = open(_done);
    container.read(cardMusicProvider(_done));
    await tester.pump();

    repo.failWith = null;
    await container.read(cardMusicProvider(_done).notifier).load();

    expect(container.read(cardMusicProvider(_done)), isA<CardMusicData>());
  });

  testWidgets('요청이 실패하면 오류로 세운다', (tester) async {
    final container = open(_noMusic);
    await tester.pump();

    repo.failWith = RecordCardFailure.server;
    await container.read(cardMusicProvider(_noMusic).notifier).request();

    expect(container.read(cardMusicProvider(_noMusic)), isA<CardMusicError>());
  });

  testWidgets('⚠️ 카드마다 따로 든다 — 한 장을 열어 둔 채 다른 장을 봐도 안 섞인다', (
    tester,
  ) async {
    final container = open(_done);
    container.listen(cardMusicProvider(_noMusic), (_, _) {});
    await tester.pump();

    expect(
      (container.read(cardMusicProvider(_done)) as CardMusicData)
          .generation
          .status,
      MusicStatus.succeeded,
    );
    expect(
      (container.read(cardMusicProvider(_noMusic)) as CardMusicData)
          .generation
          .status,
      MusicStatus.none,
    );
  });
}
