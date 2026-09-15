import 'package:runiverse/features/session/domain/user_status.dart';

/// 서버가 아는 상태를 보고 **어디로 갈 것인가.**
///
/// ## 왜 따로 있는가
///
/// 여섯 조합을 화면 코드에서 `if`로 풀면 조합 하나를 빠뜨려도 조용히 지나간다.
/// 여기서 한 번 좁혀 두면 **빠뜨린 조합을 컴파일러가 잡는다.**
///
/// 라우트 이름을 알지 않는 이유는 그것이 `app/router`의 것이기 때문이다.
/// 이 값은 "무엇을 해야 하는가"까지만 말한다.
enum RunResume {
  /// 홈. 진행 중인 것이 없거나, 있어도 지금 열 화면이 없다.
  home,

  /// 솔로 러닝 준비 화면. **자동으로 시작하지 않는다** — 사용자가 버튼을 누른다.
  soloPrepare,

  /// 러닝 화면. WebSocket에 붙어 `RUNNING_START`로 이어 달린다.
  running;

  /// [status]가 가리키는 자리.
  ///
  /// ## ⚠️ 매칭 대기·확정도 홈이다
  ///
  /// 매칭 화면이 아직 없다. **상태를 숨기지는 않는다** — 홈의 배너가 진행 중임을
  /// 알린다([showsMatchBanner]). 매칭 화면이 생기면 여기만 고친다.
  static RunResume of(UserStatus status) => switch (status) {
    UserStatusIdle() => RunResume.home,
    UserStatusWaiting() => RunResume.home,
    UserStatusReady(:final isSolo) =>
      isSolo ? RunResume.soloPrepare : RunResume.home,
    // ⚠️ 매칭이든 솔로든 할 일이 같다. 방에 다시 붙어 이어 달린다.
    UserStatusRunning() => RunResume.running,
  };

  /// 홈에 "매칭 진행 중" 배너를 띄울 상태인가.
  ///
  /// 매칭을 신청해 두고 앱을 껐다 켠 사람에게 **아무 흔적도 없으면** 신청이
  /// 사라진 줄 알고 다시 신청하려 든다. 그때 서버는 409로 막는다.
  static bool showsMatchBanner(UserStatus status) => switch (status) {
    UserStatusWaiting() => true,
    UserStatusReady(:final isSolo) => !isSolo,
    UserStatusIdle() || UserStatusRunning() => false,
  };
}
