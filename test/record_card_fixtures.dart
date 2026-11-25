import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_audio_player.dart';
import 'package:runiverse/features/record_card/presentation/card_audio_provider.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 기록카드 테스트가 함께 쓰는 7-1 모양 픽스처.
///
/// 7-1은 **러닝 기록 한 줄에 카드를 얹어** 준다(연동 가이드 1절). 테스트마다
/// 그 줄을 손으로 짓다 보면 `runningRecordId`가 어긋나 "카드가 안 붙는다"가
/// 조용히 생긴다 — 한곳에서 짓는다.

/// 카드 요약 하나. 번호만 주면 나머지는 그럴듯한 값이 붙는다.
RecordCardSummary summary({
  required int id,
  DateTime? startedAt,
  String? thumbnailUrl,
  RouteArt route = RouteArt.empty,
  RecordCardActivity? activity = RecordCardActivity.daily,
  int distanceMeters = 5000,
}) => RecordCardSummary(
  id: 'card-$id',
  startedAt: startedAt ?? DateTime(2026, 9, 2, 18, 54),
  distanceMeters: distanceMeters,
  thumbnailUrl: thumbnailUrl,
  route: route,
  activity: activity,
);

/// 카드가 매달린 러닝 한 줄.
///
/// ⚠️ **기록 번호를 카드 번호에서 뽑지 않는다.** 둘은 서로 다른 번호 공간이다
/// (카드는 UUID 문자열, 기록은 숫자). 주지 않으면 [startedAt]에서 만든다.
ComposableRecord runWith(RecordCardSummary card, {int? runningRecordId}) =>
    ComposableRecord(
      record: _run(
        id: runningRecordId ?? card.startedAt.millisecondsSinceEpoch % 100000,
        startedAt: card.startedAt,
        distanceMeters: card.distanceMeters,
      ),
      existingCard: card,
    );

/// **카드를 안 쓴** 러닝 한 줄. 달력의 운동화가 이것으로 선다.
ComposableRecord runOnly(DateTime startedAt, {int id = 90001}) =>
    ComposableRecord(
      record: _run(id: id, startedAt: startedAt, distanceMeters: 4200),
    );

/// 7-1 응답에서 **카드만** 뽑는다. 카드 없는 기록은 빠진다.
List<RecordCardSummary> cardsOf(List<ComposableRecord> rows) => [
  for (final row in rows) ?row.existingCard,
];

/// 상세 응답 한 장을 요약으로 줄인다. 가짜 저장소가 하는 일과 같다.
RecordCardSummary summaryOfCard(RecordCard card) => RecordCardSummary(
  id: card.id,
  startedAt: card.startedAt,
  distanceMeters: card.distanceMeters,
  thumbnailUrl: card.thumbnailUrl,
  route: card.route,
  activity: card.activity,
);

RunRecord _run({
  required int id,
  required DateTime startedAt,
  required int distanceMeters,
}) => RunRecord(
  id: id,
  // 가짜에는 방이 따로 없다. 러닝 요약이 방 번호로 줄을 찾으므로 값이 있어야
  // 한다(가이드 6절).
  runningRoomId: id,
  startedAt: startedAt,
  distanceMeters: distanceMeters,
  duration: const Duration(minutes: 30),
  averagePace: const Duration(minutes: 6),
  playerCount: 1,
);

/// 아무 소리도 내지 않는 플레이어.
///
/// 상세 화면을 띄우는 테스트는 전부 이것을 끼워야 한다 — 안 끼우면 진짜
/// [CardAudioPlayer] 가 서고, 테스트 환경에는 오디오 플러그인이 없어 곡을
/// 못 물어 **음악 줄이 영영 `재생`에 머문다.**
///
/// 무엇을 시켰는지 보고 싶으면 그 테스트가 자기 가짜를 따로 둔다
/// (`record_card_audio_test.dart`).
class SilentAudioPlayer implements CardAudioPlayer {
  /// 무엇을 시켰나. 보지 않는 테스트는 그냥 둔다.
  final calls = <String>[];

  @override
  Future<void> load(String url) async => calls.add('load');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// 상세를 띄우는 테스트가 `ProviderScope`에 얹을 것.
///
/// ⚠️ **타입을 적지 않는다.** Riverpod 3은 `Override`를 공개로 내보내지
/// 않는다 — 적으면 "Type 'Override' not found"가 난다.
final silentAudio = cardAudioPlayerProvider.overrideWithValue(
  SilentAudioPlayer(),
);
