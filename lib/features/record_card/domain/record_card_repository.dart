import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';

/// 기록카드를 읽는다.
///
/// ## ⚠️ 붙일 서버가 아직 없다
///
/// 3차 API 명세서에 `record-card` 엔드포인트 여섯 줄이 등록돼 있으나 **여섯 장
/// 모두 본문이 비어 있다** — 요청·응답 스키마가 없다. 그래서 지금은
/// `FakeRecordCardRepository`가 이 자리를 맡는다.
///
/// 스키마가 채워지면 `HttpRecordCardRepository`를 만들어 provider에서 바꾼다.
abstract interface class RecordCardRepository {
  /// 한 번에 물을 수 있는 **최대 일수**.
  ///
  /// ⚠️ **카드 쪽 상한은 아직 모른다.** 러닝 기록 목록(19번)이 31일이라 같은
  /// 값으로 가정하고, 달력은 **달마다 한 번씩** 묻는다. 상한을 물어 두었다
  /// (`docs/notes/2026-11-16-record-card-backend-questions.md` 1-3번).
  ///
  /// 구현마다 따로 적지 않는다 — 가짜가 이 한도를 모르면 **테스트는 통과하는데
  /// 기기에서는 400**이 나는 구간이 생긴다.
  static const maxRangeDays = 31;

  /// 날짜 구간의 **러닝 기록과 그 기록에 쓴 카드**.
  ///
  /// [from]·[to]는 KST 달력 날짜이고 **양 끝을 포함**한다. 결과는 **시작 시각
  /// 오름차순**이고, 없으면 **빈 목록**이다 — 오류가 아니다.
  ///
  /// ## ⚠️ 카드만 묻는 길이 없다
  ///
  /// 서버에 카드 목록 API가 없다. 달력은 **러닝 기록 목록(7-1) 하나**로 카드
  /// 유무까지 받는다(연동 가이드 1절) — 묶음 6까지 달마다 던졌던 두 요청이
  /// 하나로 줄었다.
  ///
  /// 그래서 돌려주는 카드는 **요약**이다([RecordCardSummary]). 회고·사진·
  /// 파티원·음악은 [detailOf]로 따로 받는다.
  ///
  /// 내 비공개 카드도 포함된다 — 기록카드 탭은 내가 내 것을 보는 자리다.
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  });

  /// **그 사람의 기록카드 한 페이지** (10-3). 프로필 그리드와 전체 보기가
  /// 읽는다.
  ///
  /// 결과는 **카드 생성 최신순**이고, 없으면 빈 페이지다 — 오류가 아니다.
  /// 달력([runsInRange])이 오름차순인 것과 반대다: 달력은 칸을 날짜로 채우고
  /// 그리드는 **최근 것이 위**다.
  ///
  /// ## ⚠️ 거르는 것은 서버다
  ///
  /// 보는 사람과 작성자의 관계로 서버가 인가를 적용한다(연동 가이드 5절) —
  /// 앱은 받은 것을 그대로 세운다. 앱이 거르면 "안 보여야 할 카드가 이미
  /// 기기에 와 있다"는 뜻이 되고, 내려받은 뒤 가리는 것은 가린 것이 아니다.
  ///
  /// **본인에게는 비공개 카드도 온다**(사용자 결정 2026-11-24). 항목에
  /// `visibility`가 없어 앱이 가려낼 근거도 없다 — 2026-11-19의 "비공개는
  /// 프로필에 안 보인다"는 그래서 철회됐다.
  ///
  /// ## ⚠️ 커서로 이어 받는다
  ///
  /// [limit]은 서버 기본값 20, 최대 50이다(넘기면 50으로 깎인다). [cursor]를
  /// 주면 그다음부터 오고, `RecordCardListPage.nextCursor`가 `null`이면 끝이다.
  /// 1 미만이나 잘못된 커서는 `400`이다.
  ///
  /// 내 프로필도 같은 경로다 — `GET /users/me`에서 받은 내 번호를 넣는다.
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  });

  /// 카드 한 장 전부 — 경로·지표·파티원·음악까지(8-1).
  ///
  /// ## ⚠️ 내 카드와 남의 공개 카드가 같은 길이다
  ///
  /// 서버가 보는 사람과의 관계로 인가를 적용하고 [RecordCard.isMine]으로
  /// 답한다. 앱이 "내 것인지"를 따로 알아낼 필요가 없다 — 묶음 6에서 라우트에
  /// `mine` 쿼리를 실어 보냈던 것은 이 응답이 없을 때의 임시였다.
  ///
  /// ## ⚠️ `404`는 한 가지다
  ///
  /// 삭제·권한 없음·작성자 탈퇴를 **같은 응답으로** 묶는다(가이드 2절).
  /// 갈라 보이면 없는 카드의 작성자가 탈퇴했는지를 남에게 알려 주는 셈이다.
  /// 화면은 "찾을 수 없거나 볼 수 없어요"로 안내한다.
  Future<RecordCard> detailOf(String cardId);

  /// 카드를 만든다. **만들어진 카드를 그대로 돌려준다** — 부르는 쪽이 바로
  /// 상세로 보내야 하고, 상세 라우트가 카드를 `extra`로 요구한다.
  ///
  /// ## ⚠️ 서버 흐름이 이것과 다를 수 있다
  ///
  /// 3차 명세의 작성은 `POST /record-cards` → `drafts/{id}/complete` **두
  /// 단계**이고, 사진을 그 사이에 올리라는 뜻으로 보인다. 어느 시점에 draft를
  /// 만드는지 물어 두었다(`docs/notes/2026-11-16-record-card-backend-questions.md`
  /// 6-1번). 답이 오면 이 한 메서드가 두 번의 왕복으로 갈라질 수 있다 —
  /// **화면은 바뀌지 않는다.** 화면은 끝까지 쓴 뒤 한 번 저장한다.
  Future<RecordCard> create(NewRecordCard card);

  /// 카드를 고친다. **고쳐진 카드를 그대로 돌려준다.**
  ///
  /// ⚠️ 싣는 사진은 **남길 전체**다([EditRecordCard.photos]) — 빈 목록은
  /// "전부 지웠다"는 뜻이지 "안 바꿨다"가 아니다.
  Future<RecordCard> update(EditRecordCard card);

  /// 카드를 지운다.
  ///
  /// ## ⚠️ 되돌릴 수 없다
  ///
  /// 서버에 **논리 삭제 컬럼이 없다**(설계 3절). 확인을 받는 것은 화면의
  /// 일이고, 여기는 한 번 가면 끝이라는 전제로 돈다.
  ///
  /// 없는 카드면 [RecordCardFailure.notFound]로 던진다 — 이미 지워진 것을 또
  /// 지우려 한 것이다.
  Future<void> delete(String cardId);

  /// **못 만든 곡을 다시 만들어 달라고 한다** (9-6).
  ///
  /// ## ⚠️ 상태를 돌려주지 않는다
  ///
  /// 서버는 `204`만 준다. 어디까지 갔는지는 **상세(8-1)를 다시 읽어** 본다 —
  /// 음악이 카드 응답에 실려 오므로 따로 묻는 길이 없다(연동 가이드 4절).
  ///
  /// ## ⚠️ 실패한 곡이 없어도 성공한다
  ///
  /// 서버가 `FAILED`인 곡만 골라 다시 건다. 하나도 없으면 아무것도 하지 않고
  /// `204`다 — 화면이 "재요청할 것이 없다"를 따로 가릴 필요가 없다.
  ///
  /// ## ⚠️ 기본곡도 함께 바뀐다
  ///
  /// 사진 곡 하나만 다시 걸어도 결과가 오면 **기본곡이 교체된다**(가이드 4절).
  /// 이미 완료된 기본곡은 기다리는 동안 기존 주소로 틀 수 있고, 결과가
  /// 실패하면 `FAILED`로 바뀔 수 있다.
  ///
  /// 남의 카드에 보내면 `404`다.
  Future<void> retryMusic(String cardId);
}

/// 카드를 못 읽은 이유.
///
/// `RunRecordFailure`와 같은 방식이다 — 예외를 화면까지 올리지 않고 값으로
/// 답해서, 화면마다 `try`/`catch`를 쓰지 않게 한다.
enum RecordCardFailure {
  /// 요청이 잘못됐다(400). 구간이 [RecordCardRepository.maxRangeDays]를 넘었거나
  /// 시작일이 늦다. **사용자가 고칠 수 있는 것이 아니라 앱의 버그다.**
  invalidRequest,

  /// 로그인이 풀렸다(401).
  sessionExpired,

  /// 그런 카드가 없다(404). **다시 시도해도 같은 답이다.**
  notFound,

  /// 그 러닝에 **이미 카드가 있다**(409 `RECORD_CARD_ALREADY_EXISTS`).
  ///
  /// ⚠️ **다시 시도할 일이 아니라 수정으로 갈 일이다.** `server`로 뭉치면
  /// 화면이 "잠시 뒤 다시"를 권하는데, 기다린다고 달라지지 않는다.
  alreadyExists,

  /// 들고 있는 카드가 **낡았다.** 상세(8-1)를 다시 읽어야 한다.
  ///
  /// 서버는 두 가지로 말한다 — 409 `RECORD_CARD_CHANGED`(남이 먼저 고쳤다)와
  /// 400 `INVALID_RECORD_CARD_IMAGE`(남기려던 사진이 그 카드 것이 아니다).
  /// **앱이 할 일은 같아서** 한 값으로 묶는다(연동 가이드 7절).
  changed,

  /// 볼 수 없는 카드다(403). 남의 비공개 카드를 열려 했다는 뜻이다.
  forbidden,

  /// 못 붙었다. 다시 시도하면 될 수 있다.
  network,

  /// 서버가 5xx로 답했다.
  server,
}

class RecordCardException implements Exception {
  const RecordCardException(this.failure);

  final RecordCardFailure failure;

  @override
  String toString() => 'RecordCardException($failure)';
}
