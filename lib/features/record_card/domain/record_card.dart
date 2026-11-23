import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 카드에 붙인 사진 한 장.
class RecordCardPhoto {
  const RecordCardPhoto({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    this.caption,
    this.isThumbnail = false,
  });

  /// `record_card_image_id`. **UUID 문자열이다**(연동 가이드 2절). AI가
  /// 사진별 음악을 이 번호로 돌려준다.
  final String id;

  /// 원본 열람 주소. **9:16으로 잘린 결과**다 — 앱이 자른 것을 올린다.
  final String url;

  /// 작은 쪽. 달력 칸과 프로필 그리드가 쓴다.
  ///
  /// ⚠️ **서버에 아직 이 키가 없다.** 컬럼을 하나 더해 달라고 요청해 두었다
  /// (`docs/notes/2026-11-16-record-card-backend-questions.md` 4번). 없으면
  /// 원본을 쓰는데, 달력 한 화면에 원본이 서른 장 걸린다.
  final String? thumbnailUrl;

  /// 이 사진에 붙인 한마디. **AI가 사진 음악을 만들 때 읽는다.**
  final String? caption;

  /// 이 장이 **대표 사진**인가(`isThumbnail`).
  ///
  /// ## ⚠️ 첫 장이라는 뜻이 아니다
  ///
  /// 가이드 4절: "기존 대표 A를 둔 채 배열 순서만 바꾸면 A가 계속 대표입니다."
  /// 그래서 **순서로 가늠하면 틀린다** — 두 번째 장이 대표일 수 있다.
  ///
  /// ## ⚠️ 아직 화면이 쓰지 않는다
  ///
  /// 수정 화면의 `대표 사진` 표시를 이 값으로 옮기는 것은 **묶음 8**이다 —
  /// 거기서 `thumbnailIndex`를 보내는 쪽과 함께 바뀌어야 한다. 지금 표시만
  /// 옮기면 "대표라고 적힌 장을 눌러도 아무 일이 없는" 구간이 생긴다.
  ///
  /// 읽어 두는 이유는 **서버가 주는 값을 DTO가 흘리지 않게** 하려는 것이다.
  /// 나중에 더하면 그때 DTO를 다시 고친다.
  final bool isThumbnail;
}

/// 함께 뛴 사람.
///
/// ⚠️ **색이 없다.** 러닝 지표에서 색을 만드는 규칙이 아직 없고
/// (`features/color/`가 비어 있다) 서버도 색을 주지 않는다. 규칙이 정해지면
/// 여기에 필드가 는다.
class CardRunner {
  const CardRunner({
    required this.userId,
    required this.nickname,
    this.profileImageUrl,
  });

  final String userId;

  /// 탈퇴한 사용자는 서버가 `탈퇴한 사용자`로 준다.
  final String nickname;

  final String? profileImageUrl;
}

/// 기록카드 한 장 — 끝난 러닝 하나에 유형·회고·사진을 얹은 것.
///
/// ## ⚠️ 러닝 지표와 경로를 **스스로 들고 있다**
///
/// 카드가 [runningRecordId]만 들고 러닝 쪽에서 다시 가져오는 길은 막혀 있다.
/// 기록 상세 API가 삭제됐고, 남은 `byRoom`은 **기록 번호가 아니라 방 번호**를
/// 받는데 카드는 방 번호를 모른다. 남의 카드는 `403`으로 한 번 더 막히고,
/// 설령 403이 풀려도 구간 조회의 `routes`는 **부르는 사람 본인 것만** 준다.
///
/// 그래서 카드 응답이 지표·경로·파티원을 직접 싣는다
/// (`docs/specs/2026-11-16-record-card-design.md` 3절).
///
/// ## ⚠️ 러닝 기록 1건당 카드는 최대 1개다
///
/// 서버의 `unique(running_record_id)`다. 하루에 두 번 뛰면 기록이 둘이고
/// 카드도 둘일 수 있다 — **하루에 카드 하나가 아니다.**
class RecordCard {
  const RecordCard({
    required this.id,
    required this.runningRecordId,
    required this.startedAt,
    required this.activity,
    required this.visibility,
    required this.reviewText,
    required this.photos,
    required this.route,
    required this.distanceMeters,
    required this.duration,
    required this.averagePace,
    required this.runners,
    this.isMine = false,
  });

  /// `recordCardId`. **UUID 문자열이다**(연동 가이드 공통 요청 규칙).
  ///
  /// ⚠️ **숫자로 읽지 않는다.** `019aa100-0000-7000-8000-000000000001` 꼴로
  /// 오므로 `int.parse`는 던지고, 비교·정렬을 숫자로 하면 뜻이 달라진다.
  final String id;

  /// 이 카드가 매달린 러닝 기록.
  final int runningRecordId;

  /// 러닝 시작 시각.
  ///
  /// ⚠️ **서버는 오프셋 없는 KST로 준다**(`2026-09-02T18:54:00`). 달력이 이
  /// 값으로 날짜 칸을 고르므로, 시간대가 틀어지면 카드가 다른 날에 붙는다.
  final DateTime startedAt;

  final RecordCardActivity activity;
  final RecordCardVisibility visibility;

  /// 전체 회고. **앱은 빈 글을 저장하지 못하게 막는다** — 서버는 막지 않는다
  /// (`review_text`가 nullable이다).
  final String reviewText;

  /// 붙인 사진. 최대 5장이고 **없을 수 있다.**
  final List<RecordCardPhoto> photos;

  /// 배경 없이 그릴 달린 모양.
  final RouteArt route;

  final int distanceMeters;
  final Duration duration;

  /// 1km당 평균 페이스.
  final Duration averagePace;

  /// 함께 뛴 사람들. 혼자 뛰었으면 비어 있다.
  final List<CardRunner> runners;

  /// 내 카드인가(`isMine`). **서버가 답한다**(가이드 2절).
  ///
  /// 상세 화면이 이 값으로 `⋮`(수정·삭제)와 음악 재요청을 세운다.
  ///
  /// ## ⚠️ 기본값이 `false`인 이유
  ///
  /// 모르면 **손을 떼는 쪽**이다. 빠뜨린 자리가 `true`면 **남의 카드에 수정
  /// 버튼이 서고** 저장할 때 404를 받는다 — 고칠 수 없는 것을 고치게 한 셈이다.
  /// `false`면 내 카드에서 `⋮`가 안 보일 뿐이고, 그건 눈에 바로 띈다.
  ///
  /// 상세(8-1)만 이 값을 싣는다. 달력·프로필 목록 응답에는 없다 — 그 자리에는
  /// 애초에 `⋮`가 없다.
  final bool isMine;

  /// [startedAt]에서 시·분을 자른 날짜. **달력이 이것으로 묶는다.**
  DateTime get day => DateTime(startedAt.year, startedAt.month, startedAt.day);

  /// 달력 칸과 그리드에 띄울 주소. **사진이 없으면 `null`이다** — 부르는 쪽이
  /// 그때 [route]로 선을 그린다.
  String? get thumbnailUrl {
    if (photos.isEmpty) return null;
    final first = photos.first;
    return first.thumbnailUrl ?? first.url;
  }
}
