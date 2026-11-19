import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';

MusicGeneration _generation(MusicStatus status) =>
    MusicGeneration(cardId: 7, status: status, trackCount: 3);

void main() {
  test('⚠️ 곡 수는 사진 수 + 1이다 — 사진이 없어도 기본 음악 한 곡이 있다', () {
    expect(MusicGeneration.trackCountFor(0), 1);
    expect(MusicGeneration.trackCountFor(1), 2);
    // 설계 3절: 기본 30초 + 사진 1장당 10초 → 5장이면 6곡.
    expect(MusicGeneration.trackCountFor(5), 6);
  });

  test('경로 장은 30초, 사진 장은 10초다', () {
    expect(MusicGeneration.durationOfPage(0), const Duration(seconds: 30));
    expect(MusicGeneration.durationOfPage(1), const Duration(seconds: 10));
    expect(MusicGeneration.durationOfPage(5), const Duration(seconds: 10));
  });

  test('만드는 중인 것은 준비 중과 만드는 중 둘이다', () {
    for (final status in MusicStatus.values) {
      expect(
        _generation(status).isWorking,
        status == MusicStatus.queued || status == MusicStatus.processing,
        reason: '$status',
      );
    }
  });

  test('틀 수 있는 것은 다 된 것뿐이다', () {
    for (final status in MusicStatus.values) {
      expect(
        _generation(status).isPlayable,
        status == MusicStatus.succeeded,
        reason: '$status',
      );
    }
  });

  test('⚠️ 만들지 않은 카드는 곡이 0개다 — 상태가 아니라 수로도 드러난다', () {
    expect(MusicGeneration.none(7).status, MusicStatus.none);
    expect(MusicGeneration.none(7).trackCount, 0);
  });
}
