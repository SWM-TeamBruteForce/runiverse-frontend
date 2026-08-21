import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/network/dio_client.dart';
import 'package:runiverse/core/storage/consent_store.dart';
import 'package:runiverse/core/storage/secure_token_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/http_auth_repository.dart';
import 'package:runiverse/features/auth/data/kakao_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
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
      // 저장된 값으로 먼저 세운다. `/me`가 실패해도 앱을 쓸 수 있어야 한다.
      //
      // 캐시를 함께 실어 보낸다 — 없으면 `/me`가 도착할 때까지 프로필 탭이
      // 회색 자리표시자로 비어 있고, 지하철에서 켰다면 계속 그렇게 남는다.
      state = AuthSignedIn(
        userId,
        isOnboarded: stored.isOnboarded,
        user: _cachedUser(userId, stored),
      );
      // **여기가 진실을 맞추는 자리다.** 다른 기기에서 프로필을 채웠으면
      // 저장값은 낡았고, 이 호출이 그것을 바로잡는다.
      await _loadCurrentUser(tokens.accessToken);
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
  ///
  /// ⚠️ **`user`를 떨어뜨리지 않는다.** 새 [AuthSignedIn]을 만들면서 빠뜨리면
  /// 방금 입력한 닉네임이 화면에서 사라진다 — 프로필 탭이 자리표시자만 그린다.
  Future<void> markOnboarded() async {
    await _store.markOnboarded();
    final current = state;
    // 로그인 상태가 아니면 상태를 만들지 않는다. 여기서 AuthSignedIn을 새로
    // 만들면 로그인하지 않은 사람이 홈에 들어간다.
    if (current is! AuthSignedIn) return;
    state = AuthSignedIn(current.userId, isOnboarded: true, user: current.user);

    // **방금 서버에 닉네임이 생긴 순간이다.** 그 값을 여기서 받아온다 —
    // 다시 묻지 않으면 앱을 껐다 켤 때까지 이름이 비어 있다.
    final accessToken = (await _store.read()).accessToken;
    if (accessToken != null) await _loadCurrentUser(accessToken);
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
      final isOnboarded = await _onboardedOf(session);
      await _store.saveSession(
        userId: session.userId,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        isOnboarded: isOnboarded,
      );
      state = AuthSignedIn(session.userId, isOnboarded: isOnboarded);
      // 로그인 응답에도 isOnboarded가 실려 오지만 **/me를 진실로 삼는다.**
      // 값이 갈리는 곳을 둘로 두면 나중에 어긋났을 때 원인을 찾기 어렵다.
      await _loadCurrentUser(session.accessToken);
      return null;
    } on AuthException catch (error) {
      return error.failure;
    }
  }

  /// 이 사람이 프로필을 채웠는가. **서버가 말하지 않으면 저장된 값을 쓴다.**
  ///
  /// ## ⚠️ 저장값은 같은 사람의 것일 때만 믿는다
  ///
  /// 한 기기에 여러 계정이 로그인할 수 있다. `userId`를 보지 않고 저장값을 쓰면
  /// **앞사람이 프로필을 채웠다는 이유로 새 사람이 홈에 들어간다.** 그 사람은
  /// 프로필이 없는데 매칭도 기록도 그 값들 위에 선다.
  ///
  /// 다른 사람이면 `false`다 — 한 번 더 묻는 쪽이 안전하다.
  ///
  /// ## 이것은 이제 우회로가 아니라 **캐시 읽기**다
  ///
  /// 인증 응답(`로그인`·`가입`·`카카오`)에는 `isOnboarded`가 없다. 진실은
  /// `GET /users/me`에만 있고, 그 호출은 이 함수 **다음에** 온다. 그 사이를
  /// 무엇으로 채울 것인가가 여기서 정해진다.
  ///
  /// 저장값은 지난 `/me` 응답이 남긴 것이다. 그래서 이 자리에서 가장 정확하다 —
  /// `false`로 못 박으면 프로필을 이미 채운 사람이 `/me`가 오기 전까지
  /// 폼으로 끌려간다.
  ///
  /// ⚠️ **`/me`가 도착하면 이 값은 덮어써진다.** 여기서 틀려도 잠깐이다.
  Future<bool> _onboardedOf(AuthSession session) async {
    final answered = session.isOnboarded;
    if (answered != null) return answered;

    final stored = await _store.read();
    return stored.userId == session.userId && stored.isOnboarded;
  }

  /// `GET /users/me`로 상태를 서버 값에 맞춘다.
  ///
  /// ## ⚠️ 실패해도 로그인을 되돌리지 않는다
  ///
  /// 인증은 이미 성공했다. 부가 요청 하나가 실패했다고 사람을 로그인 화면으로
  /// 돌려보내면, **네트워크가 잠깐 끊긴 것**과 **비밀번호가 틀린 것**이 같은
  /// 결과가 된다. 그때는 로그인 응답으로 세운 상태를 그대로 둔다.
  ///
  /// 자동 로그인 경로에서는 [restore]가 이것을 부르고, 실패하면 저장된 값으로
  /// 홈에 들어간다 — 유도 카드가 잠깐 어긋날 뿐 앱은 쓸 수 있다.
  /// 저장된 `/me` 값을 화면이 쓸 모양으로 되살린다.
  ///
  /// 셋 다 비었으면 `null`을 준다. **빈 값을 지어내지 않는다** — 화면은
  /// `user`가 없는 경우를 이미 다루고, 빈 껍데기를 주면 "받아왔는데 비어 있다"와
  /// "아직 못 받았다"가 구별되지 않는다.
  CurrentUser? _cachedUser(String userId, StoredAuth stored) {
    if (stored.nickname == null &&
        stored.profileImageUrl == null &&
        stored.introduction == null) {
      return null;
    }
    return CurrentUser(
      userId: userId,
      isOnboarded: stored.isOnboarded,
      nickname: stored.nickname,
      profileImageUrl: stored.profileImageUrl,
      introduction: stored.introduction,
    );
  }

  Future<void> _loadCurrentUser(String accessToken) async {
    final current = state;
    if (current is! AuthSignedIn) return;

    try {
      final user = await _repository.fetchCurrentUser(accessToken);

      // ⚠️ **서버가 답한 경우에만 내린다.** `user.isOnboarded`가 `null`이면
      // 그것은 "아니다"가 아니라 "말하지 않았다"이고, 그때 `false`로 못 박으면
      // 방금 [markOnboarded]가 켠 값을 그 자리에서 도로 끈다 — 프로필을 다 채운
      // 사람에게 입력 시트가 즉시 다시 뜬다. 실제로 그랬다.
      final onboarded = user.isOnboarded ?? current.isOnboarded;

      state = AuthSignedIn(user.userId, isOnboarded: onboarded, user: user);
      // 다음 실행의 첫 화면이 이 값을 쓴다. 저장해 두지 않으면 /me가 늦게 오는
      // 동안 유도 카드가 깜빡이고, 프로필 탭이 회색 자리표시자로 비어 있다.
      //
      // `markOnboarded()`가 아니라 이것을 부른다 — 그쪽은 `true`만 쓸 수 있어
      // **다른 기기에서 온보딩이 취소된 경우를 되돌리지 못한다.** 서버가 실제로
      // `false`를 답한 경우는 여기서 그대로 내려간다.
      await _store.saveCurrentUser(
        userId: user.userId,
        isOnboarded: onboarded,
        nickname: user.nickname,
        profileImageUrl: user.profileImageUrl,
        introduction: user.introduction,
      );
    } on AuthException {
      // 위 주석대로 삼킨다. 상태는 로그인 응답으로 세운 것이 남는다.
    }
  }
}
