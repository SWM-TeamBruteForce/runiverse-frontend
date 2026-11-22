import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';

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

  /// 날짜 구간의 카드 전부. [from]·[to]는 KST 달력 날짜이고 **양 끝을 포함**한다.
  ///
  /// 결과는 **시작 시각 오름차순**이고, 없으면 **빈 목록**이다 — 오류가 아니다.
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  });

  /// **이 사람의 공개된 카드.** 프로필 그리드와 전체 보기가 읽는다(설계 6-7).
  ///
  /// 결과는 **최신순**(시작 시각 내림차순)이고, 없으면 **빈 목록**이다 —
  /// 오류가 아니다. 달력([byDateRange])이 오름차순인 것과 반대다. 달력은 칸을
  /// 날짜로 채우고, 그리드는 **최근 것이 위**다.
  ///
  /// ## ⚠️ 거르는 것은 서버다
  ///
  /// 비공개 카드는 **응답에 오지 않는다.** 앱이 거르면 "안 보여야 할 카드가
  /// 이미 기기에 와 있다"는 뜻이 되고, 내려받은 뒤 가리는 것은 가린 것이
  /// 아니다. 내 프로필에서도 비공개는 안 보인다(사용자 결정) — 나만 보는
  /// 카드를 보는 자리는 기록카드 탭이다.
  ///
  /// ## ⚠️ [limit]이 `int?`인 이유
  ///
  /// `GET /users/{userId}/record-cards`가 기간·커서를 받는지, 상한이 몇인지
  /// **아직 모른다**(`docs/notes/2026-11-16-record-card-backend-questions.md`
  /// 1-3번). 그리드는 7장만 묻고(6장 + "더 있나" 한 장), 전체 보기는 주지
  /// 않는다 — 서버 기본값에 맡긴다. **커서가 정해지면 여기서 이어 받는다.**
  Future<List<RecordCard>> byUser({required String userId, int? limit});

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
  Future<void> delete(int cardId);

  /// 이 카드의 음악이 어디까지 갔나.
  ///
  /// ## ⚠️ 붙일 엔드포인트가 **하나도 없다**
  ///
  /// 생성 요청·재요청·상태 조회가 3차 명세의 어디에도 없다
  /// (`docs/notes/2026-11-16-record-card-backend-questions.md` 4번). 그래서
  /// 지금은 가짜만 답한다.
  ///
  /// ## ⚠️ 카드 응답에 싣지 않고 따로 묻는다
  ///
  /// 음악이 **카드 응답에 실릴지, 따로 조회할지도 모른다.** 어디에 올지 모르는
  /// 값을 [RecordCard]의 필드로 지어 넣으면, 따로 오는 것으로 정해지는 날
  /// 도메인과 화면을 다시 짓는다. 따로 묻는 쪽은 그 반대로 — 카드에 실려 오면
  /// 이 메서드가 **이미 받은 값을 돌려주는 것**으로 줄어든다.
  ///
  /// 한 번도 요청하지 않았으면 [MusicStatus.none]이다 — 오류가 아니다.
  /// 없는 카드면 [RecordCardFailure.notFound]로 던진다.
  Future<MusicGeneration> musicOf(int cardId);

  /// **전곡을** 만들어 달라고 한다. 처음 만드는 것과 다시 만드는 것이 같다.
  ///
  /// ## ⚠️ 곡 하나만 다시 만드는 길이 없다
  ///
  /// 상태가 묶음 하나에 하나라서(설계 3절) 1곡만 실패해도 카드 전체가
  /// [MusicStatus.failed]이고, 다시 만들기는 전곡이다.
  ///
  /// 돌려주는 것은 **요청 직후 상태**([MusicStatus.queued])다 — 부르는 쪽이
  /// 바로 줄을 바꿔 세워야 하고, 다시 묻는 것은 그다음 일이다.
  Future<MusicGeneration> requestMusic(int cardId);
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
