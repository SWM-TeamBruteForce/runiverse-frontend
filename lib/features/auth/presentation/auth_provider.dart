import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';

/// 토큰을 어디에 넣을 것인가. 지금은 메모리다.
///
/// `flutter_secure_storage`가 들어오면 **이 한 줄만 바꾼다.**
final tokenStoreProvider = Provider<TokenStore>((ref) => InMemoryTokenStore());

/// 누가 인증에 답할 것인가. 지금은 가짜다.
///
/// 서버를 부르는 구현이 생기면 **이 한 줄만 바꾼다.**
/// 타입이 [AuthRepository](인터페이스)라서 화면은 바뀐 줄도 모른다.
///
/// ⚠️ **이 파일은 `presentation`에 있으면서 `data`를 import한다.** 의존 방향
/// (`presentation → domain ← data`)의 예외인데, 구현체를 고르는 일은 어딘가에서
/// 반드시 해야 하고 그 자리가 여기다. 화면 파일은 여전히 `data`를 모른다.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FakeAuthRepository(),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// 로그인·가입·로그아웃과 그 결과로 바뀌는 상태.
///
/// ## 실패를 던지지 않고 돌려준다
///
/// [signIn]·[signUp]은 성공하면 `null`, 실패하면 이유를 돌려준다.
/// 화면마다 `try`/`catch`를 쓰게 하면 한 곳만 빠뜨려도 앱이 죽는다.
/// 잡는 곳을 여기 하나로 모은다.
///
/// ## 로딩은 여기 없다
///
/// "버튼이 도는 중"은 화면의 상태고, "이 앱이 로그인 상태인가"는 앱 전체의 상태다.
/// 둘을 한 값에 담으면 로그인 실패가 앱을 로그아웃 상태로 되돌리는 식의 사고가 난다.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnknown();

  TokenStore get _store => ref.read(tokenStoreProvider);
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// 저장된 토큰을 읽어 상태를 정한다. 앱이 켜질 때 한 번 부른다.
  Future<void> restore() async {
    final userId = await _store.readUserId();
    state = userId == null ? const AuthSignedOut() : AuthSignedIn(userId);
  }

  /// 성공하면 `null`.
  Future<AuthFailure?> signIn({
    required String email,
    required String password,
  }) =>
      _authenticate(() => _repository.signIn(email: email, password: password));

  /// 성공하면 `null`.
  Future<AuthFailure?> signUp({
    required String email,
    required String password,
  }) =>
      _authenticate(() => _repository.signUp(email: email, password: password));

  Future<void> signOut() async {
    // 서버 호출이 실패해도 로컬은 반드시 비운다. 안 비우면 사용자는
    // "로그아웃을 눌렀는데 여전히 로그인 상태"인 앱을 보게 된다.
    try {
      await _repository.signOut();
    } on AuthException {
      // 무시한다. 서버 세션은 만료되면 어차피 죽는다.
    }
    await _store.clear();
    state = const AuthSignedOut();
  }

  Future<AuthFailure?> _authenticate(
    Future<AuthSession> Function() call,
  ) async {
    try {
      final session = await call();
      await _store.save(
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      state = AuthSignedIn(session.userId);
      return null;
    } on AuthException catch (error) {
      return error.failure;
    }
  }
}
