import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/domain/card_audio_player.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/card_audio_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_page.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';

/// 카드 상세의 **소리** (설계 6-2).
///
/// 곡은 장마다 하나다. 장을 넘기면 그 장의 곡이 처음부터 나고, 끝나면
/// 반복한다 — 책은 저절로 넘어가지 않는다.
void main() {
  /// 무엇을 시켰는지만 적는다. **소리는 내지 않는다.**
  late _FakePlayer fake;
  late _Repo repo;

  setUp(() {
    fake = _FakePlayer();
    repo = _Repo(_cardWith(baseUrl: 'https://cdn.invalid/base.m4a?sig=AAA'));
  });

  /// 상세를 띄운다. 첫 프레임은 받아 오는 중이라 두 번 민다.
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordCardRepositoryProvider.overrideWithValue(repo),
          cardAudioPlayerProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CardDetailPage(cardId: 'card-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// 폴링이 한 번 돈 것처럼 상세를 다시 읽힌다.
  Future<void> refreshDetail(WidgetTester tester, RecordCard next) async {
    repo.card = next;
    final element = tester.element(find.byType(CardDetailPage));
    ProviderScope.containerOf(element).invalidate(cardDetailProvider('card-1'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 폴링이 새 주소를 줘도 다시 물지 않는다', (tester) async {
    // 서명 주소는 읽을 때마다 달라진다. 그대로 비교하면 **1분마다 소리가
    // 끊긴다**(설계 7-1).
    await open(tester);
    expect(fake.calls, ['otherAudioPlaying', 'load', 'play']);

    await refreshDetail(
      tester,
      _cardWith(baseUrl: 'https://cdn.invalid/base.m4a?sig=BBB'),
    );

    expect(fake.calls, ['otherAudioPlaying', 'load', 'play']);
  });

  testWidgets('⚠️ 서 있는 동안 곡이 완성되면 바로 난다', (tester) async {
    // 만드는 중인 장을 보고 있으면 폴링이 바로 그 일을 한다. 장을 다시
    // 밀어야 들린다면 사용자는 완성된 줄도 모른다(설계 7-2).
    repo.card = _cardWith(baseStatus: MusicStatus.generating);
    await open(tester);
    expect(fake.calls, isEmpty);

    await refreshDetail(
      tester,
      _cardWith(baseUrl: 'https://cdn.invalid/base.m4a?sig=AAA'),
    );

    expect(fake.calls, ['otherAudioPlaying', 'load', 'play']);
  });

  testWidgets('⚠️ 다른 앱이 소리를 내고 있으면 자동 재생을 접는다', (tester) async {
    // 듣던 음악이 카드를 연다고 멈추면 안 된다. 물려는 두어 누르면 바로 난다.
    fake.othersPlaying = true;

    await open(tester);

    expect(fake.calls, ['otherAudioPlaying', 'load']);
    expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
  });

  testWidgets('장을 넘기면 그 장의 곡이 처음부터 난다', (tester) async {
    repo.card = _cardWith(
      baseUrl: 'https://cdn.invalid/base.m4a?sig=AAA',
      photoUrl: 'https://cdn.invalid/photo.m4a?sig=AAA',
    );
    await open(tester);
    fake.calls.clear();

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(fake.calls, ['load', 'play']);
  });

  testWidgets('줄을 누르면 멈추고 다시 누르면 이어 듣는다', (tester) async {
    await open(tester);
    fake.calls.clear();

    await tester.tap(find.text(AppStrings.recordCardMusicPause));
    await tester.pumpAndSettle();
    expect(fake.calls, ['pause']);
    expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);

    await tester.tap(find.text(AppStrings.recordCardMusicPlay));
    await tester.pumpAndSettle();
    // ⚠️ `load`가 끼면 처음부터 다시 난다 — 이어 듣기가 아니다.
    expect(fake.calls, ['pause', 'play']);
  });

  testWidgets('⚠️ 멈춰 둔 채로 장을 넘기면 멈춘 채로 둔다', (tester) async {
    // 사람이 방금 끈 것을 장을 넘긴다고 되살리지 않는다. 물려는 둔다.
    repo.card = _cardWith(
      baseUrl: 'https://cdn.invalid/base.m4a?sig=AAA',
      photoUrl: 'https://cdn.invalid/photo.m4a?sig=AAA',
    );
    await open(tester);
    await tester.tap(find.text(AppStrings.recordCardMusicPause));
    await tester.pumpAndSettle();
    fake.calls.clear();

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(fake.calls, ['load']);
    expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
  });

  testWidgets('⚠️ 두 번 실패해도 상세를 한 번만 다시 읽는다', (tester) async {
    // 만료된 주소는 403 이지만 ExoPlayer 오류에서 그것을 가려낼 수 없다 —
    // 어떤 실패든 "만료일 수 있다"로 보고 한 번만 다시 읽는다(설계 7-3).
    fake.loadThrows = Exception('못 물었다');

    await open(tester);

    // 처음 읽기 + 못 물어서 다시 읽기.
    expect(repo.reads, 2);

    // 새 주소를 받았는데 또 만료였다. 같은 곡이라 다시 물지 않고, 다시
    // 읽지도 않는다 — 여기서 고리가 생기면 끝나지 않는다.
    await refreshDetail(
      tester,
      _cardWith(baseUrl: 'https://cdn.invalid/base.m4a?sig=BBB'),
    );

    expect(repo.reads, 3, reason: '다시 읽기가 또 돌았다');
  });

  testWidgets('⚠️ 앱이 배경으로 가면 멈추고 돌아와도 안 튼다', (tester) async {
    await open(tester);
    fake.calls.clear();

    // ⚠️ **실제 순서를 그대로 흉내 낸다.** `resumed → paused` 로 건너뛰면
    // 프레임워크가 "Invalid state transition" 으로 막는다.
    for (final step in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(step);
    }
    await tester.pumpAndSettle();
    expect(fake.calls, ['pause']);

    for (final step in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(step);
    }
    await tester.pumpAndSettle();

    expect(fake.calls, ['pause'], reason: '돌아왔다고 저절로 났다');
    expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
  });

  testWidgets('⚠️ 시트를 열어도 계속 난다', (tester) async {
    // ⋮ 메뉴는 잠깐 열었다 닫는 것이다 — 화면을 떠나는 것이 아니다.
    await open(tester);
    fake.calls.clear();

    await tester.tap(find.byTooltip(AppStrings.recordCardMore));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.recordCardEditTitle), findsOneWidget);
    expect(fake.calls, isEmpty);
  });
}

/// 곡을 심은 카드. 사진은 [photoUrl]을 주면 한 장 생긴다.
RecordCard _cardWith({
  String? baseUrl,
  MusicStatus baseStatus = MusicStatus.completed,
  String? photoUrl,
}) {
  final base = CardMusic(status: baseStatus, url: baseUrl);
  return RecordCard(
    id: 'card-1',
    runningRecordId: 1,
    startedAt: DateTime(2026, 11, 24, 4, 28),
    activity: RecordCardActivity.daily,
    visibility: RecordCardVisibility.private,
    reviewText: '오늘은 가볍게 달렸다',
    photos: [
      if (photoUrl != null)
        RecordCardPhoto(
          id: 'img-0',
          url: 'assets/images/sign_in_hero.png',
          caption: '결승선',
          music: CardMusic(status: MusicStatus.completed, url: photoUrl),
        ),
    ],
    route: RouteArt.empty,
    distanceMeters: 410,
    duration: const Duration(minutes: 2, seconds: 26),
    averagePace: const Duration(minutes: 5, seconds: 56),
    runners: const [],
    isMine: true,
    baseMusic: base,
  );
}

class _FakePlayer implements CardAudioPlayer {
  final calls = <String>[];
  bool othersPlaying = false;
  Object? loadThrows;

  @override
  Future<void> load(String url) async {
    calls.add('load');
    final boom = loadThrows;
    if (boom != null) throw boom;
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<bool> otherAudioPlaying() async {
    calls.add('otherAudioPlaying');
    return othersPlaying;
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// 상세만 답하는 저장소. 몇 번 읽혔는지 센다.
class _Repo implements RecordCardRepository {
  _Repo(this.card);

  RecordCard card;
  var reads = 0;

  @override
  Future<RecordCard> detailOf(String cardId) async {
    reads++;
    return card;
  }

  @override
  Future<void> retryMusic(String cardId) async {}

  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) => throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) => throw UnsupportedError('이 테스트는 목록을 받지 않는다');

  @override
  Future<RecordCard> create(NewRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 만들지 않는다');

  @override
  Future<RecordCard> update(EditRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 고치지 않는다');

  @override
  Future<void> delete(String cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');
}
