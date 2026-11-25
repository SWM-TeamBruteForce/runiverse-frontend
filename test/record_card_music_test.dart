import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

RecordCard _card({CardMusic? base, List<CardMusic?> photos = const []}) =>
    RecordCard(
      id: 'card-7',
      runningRecordId: 11,
      startedAt: DateTime(2026, 11, 22, 18),
      activity: RecordCardActivity.daily,
      visibility: RecordCardVisibility.friends,
      reviewText: '좋았다',
      photos: [
        for (var i = 0; i < photos.length; i++)
          RecordCardPhoto(
            id: 'img-$i',
            url: 'https://x/$i.jpg',
            music: photos[i],
          ),
      ],
      route: RouteArt.empty,
      distanceMeters: 5000,
      duration: const Duration(minutes: 30),
      averagePace: const Duration(minutes: 6),
      runners: const [],
      baseMusic: base,
    );

void main() {
  group('곡 하나', () {
    test('다 됐고 주소가 있으면 틀 수 있다', () {
      const music = CardMusic(status: MusicStatus.completed, url: 'https://x');

      expect(music.isPlayable, isTrue);
      expect(music.isWorking, isFalse);
      expect(music.hasFailed, isFalse);
    });

    test('⚠️ 주소가 없으면 다 됐어도 틀 수 없다', () {
      const music = CardMusic(status: MusicStatus.completed);

      expect(music.isPlayable, isFalse);
    });

    test('만드는 중과 실패를 가린다', () {
      expect(const CardMusic(status: MusicStatus.generating).isWorking, isTrue);
      expect(const CardMusic(status: MusicStatus.failed).hasFailed, isTrue);
      expect(const CardMusic(status: MusicStatus.failed).isPlayable, isFalse);
    });
  });

  group('카드의 곡들', () {
    test('⚠️ 0번 장이 기본곡이고 그 뒤가 사진이다', () {
      final card = _card(
        base: const CardMusic(status: MusicStatus.completed, url: 'base'),
        photos: const [
          CardMusic(status: MusicStatus.generating),
          CardMusic(status: MusicStatus.failed),
        ],
      );

      expect(card.musicOfPage(0)?.url, 'base');
      expect(card.musicOfPage(1)?.status, MusicStatus.generating);
      expect(card.musicOfPage(2)?.status, MusicStatus.failed);
    });

    test('⚠️ 없는 장을 물어도 터지지 않는다', () {
      // 사진을 지운 카드를 보던 중에 장 번호가 남을 수 있다.
      expect(_card().musicOfPage(3), isNull);
      expect(_card().musicOfPage(1), isNull);
    });

    test('⚠️ 사진 곡 하나가 만드는 중이면 카드가 그렇다고 답한다', () {
      // 기본곡이 다 됐다고 끝난 것이 아니다 — 묶음 5까지는 상태가 하나여서
      // 이 구분이 아예 없었다.
      final card = _card(
        base: const CardMusic(status: MusicStatus.completed, url: 'base'),
        photos: const [CardMusic(status: MusicStatus.generating)],
      );

      expect(card.isMusicWorking, isTrue);
      expect(card.hasFailedMusic, isFalse);
    });

    test('⚠️ 사진 곡 하나가 실패하면 카드가 그렇다고 답한다', () {
      final card = _card(
        base: const CardMusic(status: MusicStatus.completed, url: 'base'),
        photos: const [
          CardMusic(status: MusicStatus.completed, url: 'p0'),
          CardMusic(status: MusicStatus.failed),
        ],
      );

      expect(card.hasFailedMusic, isTrue);
      expect(card.isMusicWorking, isFalse);
    });

    test('⚠️ 곡이 안 온 카드는 만드는 중도 실패도 아니다', () {
      // 서버가 아직 아무 곡도 주지 않았다. 못 만든 것과 다르다 — 같이 보면
      // 받아 오는 중인 카드에 "못 만들었어요"가 선다.
      final card = _card(photos: const [null]);

      expect(card.isMusicWorking, isFalse);
      expect(card.hasFailedMusic, isFalse);
    });

    test('사진이 없어도 기본곡 하나를 센다', () {
      final card = _card(base: const CardMusic(status: MusicStatus.generating));

      expect(card.isMusicWorking, isTrue);
    });
  });

  group('장이 서 있는 길이', () {
    test('⚠️ 0번은 30초, 사진은 10초다 — AI 계약이 정한 값이다', () {
      expect(CardMusicTiming.durationOfPage(0), const Duration(seconds: 30));
      expect(CardMusicTiming.durationOfPage(1), const Duration(seconds: 10));
      expect(CardMusicTiming.durationOfPage(5), const Duration(seconds: 10));
    });
  });
}
