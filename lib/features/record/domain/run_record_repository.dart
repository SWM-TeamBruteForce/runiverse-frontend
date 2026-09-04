import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';

/// 내 러닝 기록을 읽는다. `GET /api/v1/users/me/running-records`(19번).
///
/// ## ⚠️ 모드가 둘이고 **섞을 수 없다**
///
/// 명세가 `from`·`to`(캘린더)와 `cursor`·`limit`(최근 목록)의 혼용을 막고,
/// 섞어 보내면 `INVALID_REQUEST`(400)로 거절한다. 그래서 파라미터 하나짜리
/// 메서드를 두지 않고 **모드마다 메서드를 나눴다** — 인터페이스가 잘못된
/// 조합을 애초에 표현하지 못하게 한다.
abstract interface class RunRecordRepository {
  /// 날짜 구간의 **전체** 기록. 캘린더와 주간 차트가 쓴다.
  ///
  /// [from]·[to]는 KST 달력 날짜이고 **양 끝을 포함**한다. 페이지가 나뉘지
  /// 않으므로 그 구간의 기록이 한 번에 다 온다.
  ///
  /// ⚠️ **최대 31일이다.** 넘기면 서버가 400을 준다. 한 달치 조회가 상한에
  /// 딱 걸리므로, 여기서 구간을 늘려 쓰는 화면을 만들면 조용히 깨진다.
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  });

  /// 최신순 페이지. 기록 탭의 "최근" 목록이나 프로필에서 쓴다.
  ///
  /// [cursor]가 `null`이면 첫 페이지다. 다음 페이지가 없으면 결과의
  /// `nextCursor`가 `null`로 온다.
  ///
  /// [limit]은 기본 20, **최대 50**이다. 넘겨도 서버가 50으로 깎는다.
  Future<RunRecordPage> recent({String? cursor, int limit});

  /// 러닝 결과 상세. **방 번호로 찾는다.**
  ///
  /// `GET /running-rooms/{id}/results`(17번)와 `.../split-results`(18번)를
  /// 합친다. 둘을 동시에 부른다 — 줄 세우면 왕복이 두 배다.
  ///
  /// ⚠️ **기록 번호가 아니라 방 번호다.** 러닝을 막 끝냈을 때 앱이 아는 것은
  /// `POST /solo`가 준 방 번호뿐이고, 기록 번호는 아직 모른다.
  ///
  /// **구간은 서버가 나눈 것을 그대로 쓴다** — 앱이 좌표에서 다시 나누면
  /// 같은 러닝의 숫자가 화면마다 달라진다.
  Future<RunDetail> byRoom(int runningRoomId);
}

/// [RunRecordRepository.recent]의 한 페이지.
///
/// 커서를 엔티티 목록과 함께 들고 다니려고 둔다. 목록만 돌려주면 다음 페이지를
/// 요청할 방법이 사라진다.
class RunRecordPage {
  const RunRecordPage({required this.items, required this.nextCursor});

  final List<RunRecord> items;

  /// 다음 페이지 커서. `null`이면 마지막 페이지다.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// 기록을 못 읽은 이유.
///
/// `RunningRoomFailure`와 같은 방식이다 — 예외를 화면까지 올리지 않고 값으로
/// 답해서, 화면마다 `try`/`catch`를 쓰지 않게 한다.
enum RunRecordFailure {
  /// 요청이 잘못됐다(400). 두 모드를 섞었거나 구간이 31일을 넘었다.
  ///
  /// **사용자가 고칠 수 있는 것이 아니라 앱의 버그다.** 화면은 일반 오류로
  /// 보이되 로그에는 남긴다.
  invalidRequest,

  /// 로그인이 풀렸다(401).
  sessionExpired,

  /// 못 붙었다. 다시 시도하면 될 수 있다.
  network,

  /// 서버가 5xx로 답했다.
  server,
}

class RunRecordException implements Exception {
  const RunRecordException(this.failure);

  final RunRecordFailure failure;

  @override
  String toString() => 'RunRecordException($failure)';
}
