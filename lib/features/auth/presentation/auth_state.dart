import 'package:runiverse/features/auth/domain/current_user.dart';

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

/// 로그인되어 있지 않다.
///
/// [returning]이 이 앱을 **처음 켠 사람**과 **로그인했다가 만료된 사람**을 가른다.
/// 이 구분이 없으면 만료된 사용자가 온보딩 소개를 처음부터 다시 보게 된다.
///
/// 별도 상태로 쪼개지 않고 필드로 둔 이유는 **이 값으로 갈리는 곳이 스플래시
/// 한 군데**여서다. `sealed`로 나눠 얻는 `switch` 망라성이 쓰일 자리가 없다.
final class AuthSignedOut extends AuthState {
  const AuthSignedOut({required this.returning});

  /// `true`면 로그인 화면으로, `false`면 온보딩 소개로.
  final bool returning;
}

final class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.userId, {required this.isOnboarded, this.user});

  final String userId;

  /// 프로필 등록(S04)을 마쳤는가.
  ///
  /// **인증 직후**(가입 · 이메일 로그인 · 카카오)에 `false`면 프로필 폼으로 보내고,
  /// **자동 로그인**이면 홈으로 보내되 유도 카드를 켠다.
  ///
  /// ⚠️ 값의 출처는 `GET /users/me`다. 로그인 응답에도 같은 이름이 있지만 그것은
  /// **그 순간의 사진**이라, 다른 기기에서 프로필을 채우면 어긋난다.
  final bool isOnboarded;

  /// 서버가 답한 내 정보. **`/me`가 오기 전에는 `null`이다.**
  ///
  /// 닉네임·프로필 이미지가 여기 있다. 화면은 없을 수 있다는 것을 전제로 그린다 —
  /// 네트워크가 느리면 이 값이 늦게 오고, 온보딩 전이면 아예 비어 있다.
  final CurrentUser? user;
}
