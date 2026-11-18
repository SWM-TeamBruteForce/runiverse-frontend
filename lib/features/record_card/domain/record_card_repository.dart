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
