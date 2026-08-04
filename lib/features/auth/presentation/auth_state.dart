/// 앱이 지금 로그인 상태인가.
///
/// `bool` 하나로 두지 않은 이유는 **"모른다"가 실제 상태이기 때문**이다.
/// 앱이 막 켜져서 저장소를 아직 읽지 않은 순간이 있다. 이때 `false`로 두면
/// 스플래시가 저장된 세션을 무시하고 온보딩으로 보내버린다.
///
/// `sealed`이므로 `switch`에서 세 경우를 다 다루지 않으면 컴파일러가 잡아준다.
/// freezed를 쓰지 않은 이유는 설계 문서 §2-6에 있다 — 상태가 셋뿐이라
/// 코드 생성 도구를 들이는 비용이 더 크다.
sealed class AuthState {
  const AuthState();
}

/// 저장된 토큰을 아직 확인하지 못했다. 앱의 첫 상태다.
final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

final class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.userId);

  final String userId;
}
