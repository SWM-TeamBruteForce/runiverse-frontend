import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/domain/run_record.dart';

/// 내 러닝 기록을 읽는다. `GET /api/v1/users/me/running-records`.
///
/// ## ⚠️ 2026-10-01 에 조회 방식이 하나로 줄었다
///
/// 옛 명세는 `from`·`to`(캘린더)와 `cursor`·`limit`(최근 목록) 두 모드였는데,
/// **기간 조회만** 남았다. 커서 메서드를 껍데기로 남겨 두지 않는다 — 남기면
/// 다음 사람이 페이지가 있는 줄 안다. (📅 기록 탭 연동 가이드 2장)
///
/// 하루치가 필요하면 [byDateRange]에 같은 날을 넣는다. 한 주·한 달도 그
/// 구간을 그대로 넣으면 되고, **그날 것만 고르는 일은 받은 목록에서 한다** —
/// 추가 요청이 필요 없다(가이드 1장).
abstract interface class RunRecordRepository {
  /// 한 번에 물을 수 있는 **최대 일수**. 넘기면 서버가 400을 준다.
  ///
  /// ⚠️ **구현마다 따로 적지 않는다.** 예전에는 `HttpRunRecordRepository`
  /// 안에만 있어서 가짜 저장소가 이 한도를 몰랐고, **테스트는 통과하는데
  /// 기기에서는 400** 이 나는 구간을 실제로 만들어 냈다.
  static const maxRangeDays = 31;

  /// 날짜 구간의 **전체** 기록. 캘린더와 주간 차트가 쓴다.
  ///
  /// [from]·[to]는 KST 달력 날짜이고 **양 끝을 포함**한다. 페이지가 나뉘지
  /// 않으므로 그 구간의 기록이 한 번에 다 온다.
  ///
  /// ⚠️ **최대 31일이다.** 넘기면 서버가 400을 준다. 한 달치 조회가 상한에
  /// 딱 걸리므로, 여기서 구간을 늘려 쓰는 화면을 만들면 조용히 깨진다.
  ///
  /// 결과는 **시작 시각 오름차순**이고, 기록이 없으면 **빈 목록**이다 —
  /// 그것은 오류가 아니다.
  Future<List<RunRecord>> byDateRange({
    required DateTime from,
    required DateTime to,
  });

  /// 러닝 결과 상세. **방 번호로 찾는다.**
  ///
  /// `GET /running-rooms/{id}/results`와 `.../split-results`를 합친다.
  /// 둘을 동시에 부른다 — 줄 세우면 왕복이 두 배다.
  ///
  /// ⚠️ **기록 상세 API 는 삭제됐다.** 이 둘이 그 자리를 대신한다(가이드 5장).
  ///
  /// ⚠️ **기록 번호가 아니라 방 번호다.** 러닝을 막 끝냈을 때 앱이 아는 것은
  /// `POST /solo`가 준 방 번호뿐이고, 기록 번호는 아직 모른다.
  ///
  /// **구간은 서버가 나눈 것을 그대로 쓴다** — 앱이 좌표에서 다시 나누면
  /// 같은 러닝의 숫자가 화면마다 달라진다.
  Future<RunDetail> byRoom(int runningRoomId);
}

/// 기록을 못 읽은 이유.
///
/// `RunningRoomFailure`와 같은 방식이다 — 예외를 화면까지 올리지 않고 값으로
/// 답해서, 화면마다 `try`/`catch`를 쓰지 않게 한다.
enum RunRecordFailure {
  /// 요청이 잘못됐다(400). 날짜 형식이 틀렸거나, 시작일이 늦거나, 구간이
  /// 31일을 넘었다.
  ///
  /// **사용자가 고칠 수 있는 것이 아니라 앱의 버그다.** 화면은 일반 오류로
  /// 보이되 로그에는 남긴다.
  invalidRequest,

  /// 로그인이 풀렸다(401).
  sessionExpired,

  /// 그런 기록이 없다(404). 방이 없거나 아직 확정되지 않았다.
  ///
  /// ⚠️ **다시 시도해도 같은 답이다.** `server`로 뭉치면 화면이 "잠시 뒤 다시"를
  /// 권하는데, 기다린다고 생기지 않는다.
  notFound,

  /// 그 방의 참가자가 아니다(403).
  ///
  /// 남의 기록을 열려 했다는 뜻이다. 재시도 대상이 아니다.
  forbidden,

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
