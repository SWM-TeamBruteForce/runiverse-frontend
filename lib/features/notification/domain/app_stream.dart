import 'package:runiverse/features/home/domain/home_notice.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';

/// 앱 전역 알림 스트림이 실패하는 이유.
enum AppStreamFailure {
  /// 서버에 닿지 못했거나 도중에 끊겼다. **다시 붙는 것뿐이다.**
  network,

  /// 토큰을 갱신하고 다시 붙는다.
  sessionExpired,

  /// 구버전 앱이다. 업데이트 화면으로 보낸다.
  ///
  /// ⚠️ **버전을 읽은 상태에서만 이 값이 된다.** `SseAppStream.failureOf`의
  /// 설명을 보라 — 헤더가 빠져서 받은 403을 이것으로 읽으면 멀쩡한 최신 앱을
  /// 영영 업데이트 화면에 가둔다.
  updateRequired,

  unknown,
}

class AppStreamException implements Exception {
  const AppStreamException(this.failure, {this.code});

  final AppStreamFailure failure;

  /// 서버가 준 오류 코드. 403이 여럿이라 그것을 가를 때 남긴다.
  final String? code;

  @override
  String toString() => 'AppStreamException($failure, code: $code)';
}

/// 앱 스트림이 올려보내는 것.
///
/// ## ⚠️ 알림만 오는 채널이 아니다
///
/// 홈 공지의 두 값([HomeWaitingArrived]·[HomeActivityArrived])도 같은
/// 연결로 온다. 따로 열 수 없다 — 같은 계정의 연결 둘은 서로를 밀어낸다
/// (`AppStreamBackoff` 주석).
sealed class AppStreamEvent {
  const AppStreamEvent();
}

/// 알림 한 건이 도착했다.
class AppNotificationArrived extends AppStreamEvent {
  const AppNotificationArrived(this.notification);

  final AppNotification notification;
}

/// `HOME_WAITING` — 오늘 아직 들어갈 수 있는 칸에 기다리는 사람 수.
///
/// 서버가 10초마다 보낸다. 칸을 합치는 것도 서버다 — 규칙이 바뀌어도 앱을
/// 다시 낼 필요가 없게.
class HomeWaitingArrived extends AppStreamEvent {
  const HomeWaitingArrived(this.waitingCount);

  final int waitingCount;
}

/// `HOME_ACTIVITY` — 공지 띠에 쓸 지금·오늘·어제 소식. 30초마다 온다.
class HomeActivityArrived extends AppStreamEvent {
  const HomeActivityArrived(this.activity);

  final HomeActivity activity;
}

/// 앱에 들어온 뒤 계속 열어 두는 알림 채널.
///
/// ## ⚠️ 매칭 스트림과 별개 연결이고, 둘을 동시에 유지한다
///
/// 방에 들어가 있는 동안에도 이쪽을 닫지 않는다. 닫으면 그 사이의 친구 요청·
/// 러닝 초대가 영영 오지 않는다(재연결로 재생되지 않는다 — 복구는 목록
/// 조회뿐이다).
///
/// ## ⚠️ 404가 없다
///
/// 활성 신청과 무관하게 열린다. 매칭 스트림이 수락 전 연결에 주는 404와
/// 구분해야 한다.
///
/// ## 연결 직후 스냅샷이 없다
///
/// `:connected` 주석 한 줄만 온다. 지금까지의 알림은 목록 API로 받는다.
abstract interface class AppStream {
  /// 붙어서 이벤트를 받는다. 부를 때마다 **새 연결**이다.
  Stream<AppStreamEvent> connect();

  Future<void> close();
}
