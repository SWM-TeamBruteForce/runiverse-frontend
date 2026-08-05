import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';

/// 서버 없이 로그인 흐름을 돌려보기 위한 가짜 저장소.
///
/// ## 왜 있는가
///
/// 백엔드를 띄우지 않고 화면과 상태 전이를 완성하기 위해서다.
/// 서버가 준비되면 이 클래스를 **지우지 않고 남긴다** — 테스트에서 계속 쓴다.
/// 진짜 서버를 부르는 구현은 같은 인터페이스로 옆에 만든다.
///
/// ## 씨앗 계정
///
/// 빈 저장소로 시작하면 로그인 화면을 열어도 시험해볼 계정이 없다.
/// [seedEmail] / [seedPassword]로 미리 하나 넣어둔다.
/// **비밀번호는 `PasswordRule`을 통과하는 값이다** — 규칙을 바꿀 때 같이 확인한다.
///
/// ## 계정은 앱을 끄면 사라진다
///
/// 메모리에만 있다. 가입해두고 앱을 재시작하면 그 계정으로 로그인할 수 없다.
/// 저장이 필요해지는 시점은 진짜 서버가 붙는 시점과 같아서 따로 만들지 않는다.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.latency = const Duration(milliseconds: 600)});

  static const seedEmail = 'test@runiverse.app';
  static const seedPassword = 'runi123!';

  /// 응답이 즉시 오면 로딩 표시가 화면에 뜨는지 확인할 수 없다.
  /// 테스트에서는 [Duration.zero]를 넣어 기다리지 않는다.
  final Duration latency;

  final Map<String, String> _accounts = {seedEmail: seedPassword};

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    // 없는 이메일과 틀린 비밀번호를 구분하지 않는다.
    // 구분하면 "이 이메일은 가입돼 있다"가 새어 나간다.
    if (_accounts[key] != password) {
      throw const AuthException(AuthFailure.invalidCredentials);
    }
    return _sessionFor(key);
  }

  @override
  Future<AuthSession> signUp({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    if (_accounts.containsKey(key)) {
      throw const AuthException(AuthFailure.emailAlreadyExists);
    }
    _accounts[key] = password;
    return _sessionFor(key);
  }

  @override
  Future<void> signOut() => Future<void>.delayed(latency);

  /// 이메일은 대소문자를 가리지 않는다. `Runner@`와 `runner@`가 다른 계정이 되면
  /// 사용자는 왜 로그인이 안 되는지 알 수 없다.
  String _normalize(String email) => email.trim().toLowerCase();

  /// 같은 이메일이면 항상 같은 `userId`가 나오게 이메일에서 만든다.
  /// 매번 새 번호를 매기면 로그인할 때마다 다른 사람이 된다.
  AuthSession _sessionFor(String email) => AuthSession(
    userId: 'fake-${email.hashCode.toRadixString(16)}',
    accessToken: 'fake-access-$email',
    refreshToken: 'fake-refresh-$email',
  );
}
