import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 쓰다 만 기록카드 한 장.
///
/// 작성이 세 화면이라(기록·유형·회고 → 사진 → 공개범위·음악) 라우트를
/// 넘나든다. 그 사이를 이것 하나가 따라간다 — 들고 있는 쪽은
/// `CardDraftController`다.
///
/// ## ⚠️ 러닝 기록은 **고르는** 것이고, 경로는 **딸려 오는** 것이다
///
/// [record]는 사용자가 목록에서 고른다. [route]는 그 기록의 상세를 받아 와야
/// 알 수 있어, 고른 뒤에 채워지고 **못 받으면 비어 있다.** 그래서 경로는
/// [canProceed]의 조건이 아니다 — 트레드밀 러닝은 경로가 아예 없다.
class CardDraft {
  const CardDraft({
    this.record,
    this.route,
    this.activity,
    this.reviewText = '',
    this.photos = const [],
    this.visibility = RecordCardVisibility.friends,
    this.editing,
    this.seeded = false,
  });

  /// 카드를 **고치려고** 뜬 초안 (설계 6-6).
  ///
  /// ## ⚠️ 러닝 기록을 지어내지 않는다
  ///
  /// 카드는 **방 번호를 모른다**(설계 3절) — `RunRecord`를 만들어 꽂으면
  /// `runningRoomId`에 가짜 값이 들어간다. 대신 [editing]에 카드를 들고, 읽기
  /// 전용으로 보여 줄 것은 거기서 바로 읽는다.
  ///
  /// ## ⚠️ [seeded]가 참으로 뜬다
  ///
  /// 값이 다 차 있어도 **사용자가 손댄 것은 아니다.** 참이 아니면 들어오자마자
  /// 이어 쓰기 시트가 뜨고, 고치러 들어온 사람에게 아무 말이나 묻는 꼴이 된다.
  factory CardDraft.fromCard(RecordCard card) => CardDraft(
    editing: card,
    route: card.route,
    activity: card.activity,
    visibility: card.visibility,
    reviewText: card.reviewText,
    photos: [
      for (final photo in card.photos)
        SavedPhoto(
          id: photo.id,
          url: photo.url,
          thumbnailUrl: photo.thumbnailUrl,
          caption: photo.caption ?? '',
        ),
    ],
    seeded: true,
  );

  /// 이 카드가 붙을 러닝 기록. 고르기 전에는 `null`이다.
  final RunRecord? record;

  /// [record]의 경로 선 아트. **못 받았거나 경로가 없는 러닝이면 `null`이다.**
  final RouteArt? route;

  /// 일상 · 대회 · 여행. 고르기 전에는 `null`이다.
  final RecordCardActivity? activity;

  /// 회고. **설계가 필수로 못 박았다**(6-2). 빈 문자열이 "아직 안 썼다"다.
  final String reviewText;

  /// 붙인 사진. **선택이다** — 한 장도 없이 저장할 수 있다(설계 6-3).
  final List<CardPhotoDraft> photos;

  /// 누가 볼 수 있나. 기본값은 **친구 공개**다(설계 6-4).
  final RecordCardVisibility visibility;

  // ⚠️ **음악 설정이 없다.** 서버가 카드를 확정할 때 늘 생성을 요청한다
  // (연동 가이드 3절). 끌 수 없는 값을 초안에 들고 있으면 저장할 때 보낼
  // 곳도 없고, 화면은 고를 수 있는 것처럼 보인다. 2026-11-24에 걷어냈다.

  /// 회고 상한. 서버 `review_text`가 받는 길이이고, 입력 칸도 여기서 멈춘다.
  static const reviewMaxLength = 1000;

  /// 사진 상한. 기본 음악 1곡 + 사진 음악 5곡 = 6곡이라 **서버가 아니라 우리가**
  /// 정한 값이다(설계 3절 — DB에 제약이 없다).
  static const maxPhotos = 5;

  /// 한 장 더 넣을 수 있나.
  bool get canAddPhoto => photos.length < maxPhotos;

  /// 다음 화면으로 갈 수 있나 — **기록 · 유형 · 회고가 다 차야 한다**(설계 6-2).
  ///
  /// 공백뿐인 회고는 쓴 것으로 세지 않는다. 띄어쓰기 한 칸으로 필수 항목을
  /// 통과하면 회고를 필수로 둔 뜻이 없어진다.
  /// 고치고 있는 카드. **새 카드면 `null`이다.**
  ///
  /// ⚠️ 수정에서는 [record]가 비어 있고 이것이 찬다 — 카드가 방 번호를 몰라
  /// `RunRecord`를 지어낼 수 없다.
  final RecordCard? editing;

  /// 카드에서 **뜬 직후**인가. 사용자가 한 번이라도 손대면 내려간다.
  ///
  /// ⚠️ [copyWith]가 이 값을 **들고 가지 않는다**(기본이 `false`다) — 모든
  /// 고치기가 `copyWith`를 지나므로, 그것만으로 "손댔다"가 된다.
  final bool seeded;

  /// 저장할 수 있나.
  ///
  /// ⚠️ **[record]만 보면 수정이 영원히 못 저장한다** — 수정에는 러닝 기록이
  /// 없고 고치는 카드가 있다.
  bool get canProceed =>
      (record != null || editing != null) &&
      activity != null &&
      reviewText.trim().isNotEmpty;

  /// 버리기 전에 사용자에게 물어야 하나.
  ///
  /// ## ⚠️ [record]와 [route]는 세지 않는다
  ///
  /// 둘은 **앱이 꽂아 준 것**이다 — 달력의 운동화를 누르거나 러닝 요약에서
  /// 들어오면 고르지 않아도 차 있다. 그것만 보고 확인을 받으면 잘못 들어온
  /// 사람이 나갈 때마다 막힌다. 사용자가 손으로 넣은 것은 유형·회고·사진과
  /// **기본값에서 바꾼 공개범위**도 센다.
  ///
  /// ⚠️ 공개범위는 기본값이 있어 "비었는지"로 못 가린다. 기본값과 비교한다 —
  /// 안 세면 나만 보기로 바꿔 둔 사람이 뒤로 눌렀을 때 그 선택이 조용히
  /// 사라진다.
  /// ⚠️ **카드에서 막 뜬 초안은 손댄 것이 아니다**([seeded]). 값이 다 차 있어도
  /// 사용자가 넣은 것이 아니라 앱이 꽂아 준 것이다.
  bool get isDirty =>
      !seeded &&
      (activity != null ||
          reviewText.trim().isNotEmpty ||
          photos.isNotEmpty ||
          visibility != RecordCardVisibility.friends);

  /// ⚠️ **비우려면 `clear*`를 쓴다.** `record: null`은 "안 바꾼다"와 구별되지
  /// 않는다. `RecordCardData.copyWith(clearFilter:)`와 같은 꼴이다.
  CardDraft copyWith({
    RunRecord? record,
    bool clearRecord = false,
    RouteArt? route,
    bool clearRoute = false,
    RecordCardActivity? activity,
    String? reviewText,
    List<CardPhotoDraft>? photos,
    RecordCardVisibility? visibility,
  }) => CardDraft(
    // ⚠️ **[seeded]를 들고 가지 않는다.** 모든 고치기가 여기를 지나므로,
    // 기본값 `false`가 곧 "사용자가 손댔다"가 된다.
    editing: editing,
    record: clearRecord ? null : (record ?? this.record),
    route: clearRoute ? null : (route ?? this.route),
    activity: activity ?? this.activity,
    reviewText: reviewText ?? this.reviewText,
    photos: photos ?? this.photos,
    visibility: visibility ?? this.visibility,
  );
}
