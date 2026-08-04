import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/verification_code_rule.dart';

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
  FakeAuthRepository({
    this.latency = const Duration(milliseconds: 600),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const seedEmail = 'test@runiverse.app';
  static const seedPassword = 'runi123!';

  /// 가짜 저장소가 받아주는 **유일한** 인증번호.
  ///
  /// 진짜 서버는 무작위로 만들어 메일로 보낸다. 여기서 무작위를 쓰면 에뮬레이터로
  /// 시험해볼 방법이 없어서 고정했다. **이 값은 서버가 붙는 순간 쓰이지 않는다.**
  static const mockCode = '123456';

  /// 응답이 즉시 오면 로딩 표시가 화면에 뜨는지 확인할 수 없다.
  /// 테스트에서는 [Duration.zero]를 넣어 기다리지 않는다.
  final Duration latency;

  /// 만료를 시험하려면 시계를 앞으로 돌릴 수 있어야 한다.
  /// `DateTime.now()`를 직접 부르면 테스트가 5분을 실제로 기다려야 한다.
  final DateTime Function() _now;

  final Map<String, String> _accounts = {seedEmail: seedPassword};

  /// 이메일 → 인증번호를 보낸 시각. 만료 판정의 기준이다.
  final Map<String, DateTime> _codeSentAt = {};

  /// 인증을 마친 이메일. 가입은 여기 있는 이메일로만 된다.
  final Set<String> _verified = {};

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
  Future<void> sendVerificationCode(String email) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    // 가입 여부를 인증번호를 치기 **전에** 알려준다.
    if (_accounts.containsKey(key)) {
      throw const AuthException(AuthFailure.emailAlreadyExists);
    }

    _codeSentAt[key] = _now();
    // 다시 보내면 이전 인증은 무효다. 이메일을 바꿔가며 인증을 쌓지 못하게 한다.
    _verified.remove(key);
  }

  @override
  Future<void> verifyCode({required String email, required String code}) async {
    await Future<void>.delayed(latency);

    final key = _normalize(email);
    final sentAt = _codeSentAt[key];

    // 받은 적 없는 이메일이다. "받은 적 없다"를 따로 알리지 않는다 —
    // 그러면 어떤 이메일에 번호가 발급됐는지 떠볼 수 있다.
    if (sentAt == null) {
      throw const AuthException(AuthFailure.invalidCode);
    }
    if (_now().difference(sentAt) > VerificationCodeRule.ttl) {
      throw const AuthException(AuthFailure.codeExpired);
    }
    if (code != mockCode) {
      throw const AuthException(AuthFailure.invalidCode);
    }

    _verified.add(key);
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
    // 앱은 인증 전에 가입 버튼을 열지 않는다. 그래도 여기서 한 번 더 막는다 —
    // **서버가 반드시 해야 하는 검사**라서, 가짜 저장소가 그 계약을 흉내낸다.
    if (!_verified.contains(key)) {
      throw const AuthException(AuthFailure.emailNotVerified);
    }

    _accounts[key] = password;
    // 가입이 끝나면 인증은 쓰였다. 남겨두면 탈퇴 후 재가입에 재사용된다.
    _verified.remove(key);
    _codeSentAt.remove(key);

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
