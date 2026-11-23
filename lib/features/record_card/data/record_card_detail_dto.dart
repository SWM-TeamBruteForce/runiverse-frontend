import 'package:runiverse/features/record_card/data/route_art_wire.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';

/// `GET /api/v1/record-cards/{recordCardId}` 응답을 엔티티로 옮긴다 (8-1).
///
/// **여기가 서버 형식을 아는 유일한 곳이다.** 필드 이름·단위가 도메인 밖으로
/// 새지 않게 한다 — 서버는 초와 미터로 주고, 도메인은 [Duration]으로 든다.
///
/// 계약은 「💾 [1.3.2] 기록 카드 프론트엔드 연동 가이드」 2절이다.
abstract final class RecordCardDetailDto {
  const RecordCardDetailDto._();

  static RecordCard from(Map<String, dynamic> json) {
    final record = _map(json['record']);

    return RecordCard(
      id: json['recordCardId'] as String,
      // ⚠️ **러닝 기록 번호는 int다.** 카드 번호만 UUID 문자열이다.
      runningRecordId: record['runningRecordId'] as int,
      // ⚠️ **오프셋 없는 KST로 온다**(`2026-11-22T18:10:00`). `.toUtc()`를
      // 붙이면 9시간 밀려 **카드가 다른 날에 붙는다.**
      startedAt: DateTime.parse(record['startedAt'] as String),
      // ⚠️ **모르는 값을 일상으로 뭉개지 않는다** — 대회에서 뛴 기록이 일상으로
      // 보이면 필터가 거짓말을 한다. 작성에 필수인 값이라 비어 올 수는 없고,
      // 여기 걸리면 **우리가 못 읽은 것**이다. 그래도 카드를 못 열게 하지는
      // 않는다 — 유형 하나 때문에 포토북을 닫는 편이 더 나쁘다.
      activity:
          RecordCardActivity.of(json['activityType']) ??
          RecordCardActivity.daily,
      // 모르는 값은 가장 닫힌 쪽으로 읽는다(`RecordCardVisibility.of`).
      visibility: RecordCardVisibility.of(json['visibility']),
      // 서버의 `memo`가 앱의 회고다.
      reviewText: json['memo'] as String? ?? '',
      photos: [
        if (json['images'] case final List images)
          for (final image in images)
            if (image is Map<String, dynamic>) _photo(image),
      ],
      route: routeArtFrom(record['routeArt']),
      distanceMeters: record['totalDistanceMeters'] as int? ?? 0,
      duration: Duration(seconds: record['totalDurationSeconds'] as int? ?? 0),
      averagePace: Duration(
        seconds: record['averagePaceSecondsPerKm'] as int? ?? 0,
      ),
      runners: [
        if (json['companions'] case final List companions)
          for (final companion in companions)
            if (companion is Map<String, dynamic>) _runner(companion),
      ],
      // ⚠️ **서버가 답한다.** 없으면 `false` — 모르면 손을 뗀다.
      isMine: json['isMine'] == true,
      baseMusic: _music(json['baseMusic']),
    );
  }

  static RecordCardPhoto _photo(Map<String, dynamic> json) => RecordCardPhoto(
    id: json['recordCardImageId'] as String,
    // 포토북 장에 쓰는 **크롭한 원본**이다(가이드 2절).
    url: json['imageUrl'] as String? ?? '',
    caption: json['caption'] as String?,
    isThumbnail: json['isThumbnail'] == true,
    music: _music(json['music']),
  );

  /// 곡 하나. **없으면 `null`이다** — 못 만든 것과 다르다.
  static CardMusic? _music(Object? wire) {
    if (wire is! Map) return null;
    final status = switch (wire['status']) {
      'GENERATING' => MusicStatus.generating,
      'COMPLETED' => MusicStatus.completed,
      'FAILED' => MusicStatus.failed,
      // ⚠️ **모르는 값을 완료로 보지 않는다.** 완료로 읽으면 주소가 없는 곡을
      // 틀려 하고, 만드는 중으로 읽으면 끝나지 않는 폴링이 된다. 모르면
      // 아무 말도 하지 않는다.
      _ => null,
    };
    if (status == null) return null;
    return CardMusic(status: status, url: wire['musicUrl'] as String?);
  }

  /// 함께 뛴 사람 하나.
  ///
  /// ⚠️ **보는 사람도 여기 들어올 수 있다.** 가이드 2절이 "'나' 표시는
  /// `userId`로 비교"하라고 적었다 — 닉네임으로 가리면 같은 닉네임이 둘일 때
  /// 틀린다.
  static CardRunner _runner(Map<String, dynamic> json) => CardRunner(
    userId: json['userId'] as String? ?? '',
    nickname: json['nickname'] as String? ?? '',
    profileImageUrl: json['profileImageUrl'] as String?,
  );

  static Map<String, dynamic> _map(Object? wire) =>
      wire is Map<String, dynamic> ? wire : const {};
}
