import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/network/dio_client.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/secure_token_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/http_auth_repository.dart';
import 'package:runiverse/features/auth/data/kakao_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_code_source.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';

/// 토큰을 어디에 넣을 것인가. 안드로이드 Keystore · iOS Keychain이다.
///
/// ⚠️ **위젯 테스트는 이것을 override해야 한다.** 플랫폼 채널을 부르는데
/// 테스트 환경에는 채널이 없어 `MissingPluginException`이 난다.
/// `InMemoryTokenStore`를 넣으면 된다.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// 약관 동의 기록을 어디에 넣을 것인가.
///
/// [tokenStoreProvider]와 나란히 두는 이유는 성격이 같아서다 — 둘 다 화면이 아니라
/// 저장소를 고르는 일이다. **수명은 다르다**: 로그아웃이 토큰만 지우고 이것은 남긴다.
///
/// ⚠️ 위젯 테스트는 이것도 override해야 한다. `InMemoryConsentStore`를 넣으면 된다.
final consentStoreProvider = Provider<ConsentStore>(
  (ref) => SecureConsentStore(),
);

/// 서버를 부를 [Dio] 하나.
///
/// 앱이 사는 동안 하나만 쓴다 — 요청마다 새로 만들면 연결을 매번 새로 연다.
final dioProvider = Provider<Dio>((ref) {
  final dio = createDio();
  ref.onDispose(dio.close);
  return dio;
});

/// 누가 인증에 답할 것인가. 이제 진짜 서버다.
///
/// **바뀐 것은 이 한 줄뿐이다.** 화면도 `AuthController`도 손대지 않았다 —
/// 타입이 [AuthRepository](인터페이스)라서 누가 답하는지 알지 못한다.
/// 인터페이스를 먼저 둔 값이 여기서 나온다.
///
/// `FakeAuthRepository`는 지우지 않았다. 서버 없이 도는 테스트가 계속 쓴다.
///
/// ⚠️ **이 파일은 `presentation`에 있으면서 `data`를 import한다.** 의존 방향
/// (`presentation → domain ← data`)의 예외인데, 구현체를 고르는 일은 어딘가에서
/// 반드시 해야 하고 그 자리가 여기다. 화면 파일은 여전히 `data`를 모른다.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => HttpAuthRepository(ref.watch(dioProvider)),
);

/// 소셜 인가 코드를 어디서 얻는가.
///
/// ⚠️ **테스트는 이것을 override해야 한다.** 카카오 SDK는 플랫폼 채널을 부르는데
/// 테스트 환경에는 채널이 없다. `FakeOauthCodeSource`를 넣으면 된다.
final oauthCodeSourceProvider = Provider<OauthCodeSource>(
  (ref) => const KakaoCodeSource(),
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

  /// 저장된 토큰으로 세션을 되살린다. 앱이 켜질 때 한 번, 재시도할 때 다시 부른다.
  ///
  /// ## 갈림길
  ///
  /// ```
  /// refreshToken 있음 → 갱신 → 성공 : 로그인 상태 (isOnboarded가 홈/프로필을 가른다)
  ///                            401  : 토큰만 지우고 로그인 화면
  ///                            그 밖 : 판정 불가 — AuthUnknown에 머문다
  /// refreshToken 없음 → userId 있으면 로그인 화면, 없으면 온보딩 소개
  /// ```
  ///
  /// **판정에 실패하면 상태를 바꾸지 않는다.** 저장된 값을 믿고 들여보내면
  /// "네트워크가 끊긴 것"과 "토큰이 살아 있는 것"을 같이 취급하게 된다.
  /// 화면은 상태가 [AuthUnknown]에 머무는 것을 보고 재시도를 띄운다.
  Future<void> restore() async {
    final stored = await _store.read();

    if (stored.refreshToken == null) {
      // 저장된 것이 아예 없으면 처음 온 사람이고, userId만 남았으면
      // 만료됐거나 로그아웃한 사람이다. 후자에게 소개를 다시 보이지 않는다.
      state = AuthSignedOut(returning: stored.userId != null);
      return;
    }

    final userId = stored.userId;
    if (userId == null) {
      // 토큰은 있는데 누구인지 모른다. 저장소가 어긋난 상태라 되살릴 수 없다.
      // 빈 문자열로 채우면 로그인된 것처럼 보이고 다음 API 호출부터 깨진다.
      await _store.clear();
      state = const AuthSignedOut(returning: false);
      return;
    }

    try {
      final tokens = await _refreshWithRetry(stored.refreshToken!);
      // ⚠️ 회전된 refreshToken을 반드시 덮어쓴다. 안 하면 다음 갱신이 401로 죽는다.
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      state = AuthSignedIn(userId, isOnboarded: stored.isOnboarded);
    } on AuthException catch (error) {
      if (error.failure == AuthFailure.sessionExpired) {
        // userId·isOnboarded는 남긴다. 이 사람은 처음 온 것이 아니다.
        await _store.clearTokens();
        state = const AuthSignedOut(returning: true);
        return;
      }
      // 네트워크·5xx — 판정에 실패했다. 상태를 바꾸지 않는다.
    }
  }

  /// 한 번 더 시도한다. 터널이나 엘리베이터처럼 **순간 끊김**을 흡수한다.
  ///
  /// 무한 재시도는 하지 않는다 — 비행기 모드인 기기에서는 배터리만 쓴다.
  /// 그 뒤로는 사용자가 화면에서 눌러 [restore]를 다시 부른다.
  Future<AuthTokens> _refreshWithRetry(String refreshToken) async {
    try {
      return await _repository.refresh(refreshToken);
    } on AuthException catch (error) {
      // 만료는 다시 시도해도 결과가 같다. 기다릴 이유가 없다.
      if (error.failure == AuthFailure.sessionExpired) rethrow;
      return _repository.refresh(refreshToken);
    }
  }

  /// 성공하면 `null`.
  Future<AuthFailure?> signIn({
    required String email,
    required String password,
  }) =>
      _authenticate(() => _repository.signIn(email: email, password: password));

  /// 성공하면 `null`.
  ///
  /// ⚠️ **실패하면 티켓은 이미 소비됐다.** 화면은 티켓을 버리고 인증 단계로
  /// 되돌아가야 한다 — 같은 티켓으로 다시 부르면 `emailNotVerified`가 나온다.
  Future<AuthFailure?> signUp({
    required String verificationTicket,
    required String password,
  }) => _authenticate(
    () => _repository.signUp(
      verificationTicket: verificationTicket,
      password: password,
    ),
  );

  /// 성공하면 `null`.
  ///
  /// **두 단계를 여기서 잇는다** — ① 카카오에서 인가 코드를 받고 ② 서버에 넘긴다.
  /// 화면은 둘을 알 필요가 없고, 어느 쪽이 실패해도 이유 하나로 돌아온다.
  ///
  /// ⚠️ **인가에 실패하면 서버를 부르지 않는다.** 취소한 사람 때문에 요청이
  /// 나가면, 서버는 빈 코드로 카카오에 교환을 시도하게 된다.
  Future<AuthFailure?> signInWithOauth(OauthProvider provider) async {
    final OauthAuthorization authorization;
    try {
      authorization = await ref
          .read(oauthCodeSourceProvider)
          .authorize(provider);
    } on AuthException catch (error) {
      // 취소도 여기로 온다. 그대로 돌려주고 상태는 건드리지 않는다.
      return error.failure;
    }

    return _authenticate(
      () => _repository.signInWithOauth(
        provider: provider,
        authorization: authorization,
      ),
    );
  }

  /// 성공하면 `null`. **상태를 바꾸지 않는다.**
  Future<AuthFailure?> sendVerificationCode(String email) async {
    try {
      await _repository.sendVerificationCode(email);
      return null;
    } on AuthException catch (error) {
      return error.failure;
    }
  }

  /// 성공하면 `ticket`, 실패하면 `failure`. **둘 중 하나만 채워진다.**
  ///
  /// ## 왜 상태를 바꾸지 않는가
  ///
  /// 인증은 **신원 확인이지 로그인이 아니다.** 여기서 [AuthSignedIn]으로 만들면
  /// 비밀번호도 정하지 않은 사람이 홈에 들어간다. 토큰이 생기는 곳은 [signUp]뿐이다.
  ///
  /// ## 티켓을 저장하지 않는다
  ///
  /// 가입 화면이 받아서 들고 있다가 [signUp]에 넘긴다. 저장소에 넣으면 지울
  /// 자리를 따로 찾아야 하고, 앱을 껐다 켠 사람에게 남아 있을 이유가 없다.
  Future<({String? ticket, AuthFailure? failure})> verifyCode({
    required String email,
    required String code,
  }) async {
    try {
      final ticket = await _repository.verifyCode(email: email, code: code);
      return (ticket: ticket, failure: null);
    } on AuthException catch (error) {
      return (ticket: null, failure: error.failure);
    }
  }

  /// 프로필 등록을 마쳤다. **저장소와 상태를 함께** 켠다.
  ///
  /// 상태만 켜면 앱을 껐다 켰을 때 저장소가 여전히 `false`라 프로필로 다시 간다.
  /// 저장소만 켜면 지금 화면이 홈으로 넘어가지 않는다.
  Future<void> markOnboarded() async {
    await _store.markOnboarded();
    final current = state;
    // 로그인 상태가 아니면 상태를 만들지 않는다. 여기서 AuthSignedIn을 새로
    // 만들면 로그인하지 않은 사람이 홈에 들어간다.
    if (current is AuthSignedIn) {
      state = AuthSignedIn(current.userId, isOnboarded: true);
    }
  }

  Future<void> signOut() async {
    // 서버 호출이 실패해도 로컬은 반드시 비운다. 안 비우면 사용자는
    // "로그아웃을 눌렀는데 여전히 로그인 상태"인 앱을 보게 된다.
    try {
      await _repository.signOut();
    } on AuthException {
      // 무시한다. 서버 세션은 만료되면 어차피 죽는다.
    }
    await _store.clear();
    // 로그아웃한 사람은 처음 온 사람이 아니다. 소개를 다시 보여주지 않는다.
    state = const AuthSignedOut(returning: true);
  }

  Future<AuthFailure?> _authenticate(
    Future<AuthSession> Function() call,
  ) async {
    try {
      final session = await call();
      await _store.saveSession(
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        isOnboarded: session.isOnboarded,
      );
      state = AuthSignedIn(session.userId, isOnboarded: session.isOnboarded);
      return null;
    } on AuthException catch (error) {
      return error.failure;
    }
  }
}
