import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 진짜 서버를 부르는 [AuthRepository].
///
/// `FakeAuthRepository`와 같은 인터페이스를 구현한다. 어느 쪽이 답하는지는
/// `auth_provider.dart`가 정하고, 화면은 둘을 구분하지 못한다.
///
/// ## dio를 밖으로 흘리지 않는다
///
/// 이 클래스 밖으로 나가는 실패는 전부 [AuthException]이다. [DioException]이
/// 새어 나가면 화면이 dio를 알아야 하고, 나중에 클라이언트를 바꿀 때
/// 화면까지 따라 고쳐야 한다.
class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._dio);

  final Dio _dio;

  static const _loginPath = '/api/v1/auth/login';
  static const _signUpPath = '/api/v1/auth/signup';
  static const _refreshPath = '/api/v1/auth/refresh';

  /// provider가 뒤에 붙는다 — `/auth/oauth/kakao`.
  static const _oauthPath = '/api/v1/auth/oauth';
  static const _sendCodePath = '/api/v1/auth/email/verifications';
  static const _verifyCodePath = '/api/v1/auth/email/verifications/confirm';

  /// 내 기본 정보. **`isOnboarded`의 유일한 출처다.**
  static const _mePath = '/api/v1/users/me';

  /// 갱신에만 짧은 시간 제한을 건다.
  ///
  /// 이 호출은 **스플래시가 기다리는 유일한 요청**이다. dio 기본값(10초)을 그대로
  /// 쓰면 연결이 나쁜 곳에서 앱이 10초 멈춘 것처럼 보인다.
  static const _refreshTimeout = Duration(seconds: 5);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => _login(email: email, password: password);

  /// 가입 응답이 **토큰까지 준다.** 이어서 로그인할 필요가 없다.
  ///
  /// 몸통의 필드 이름이 로그인 응답과 같아 [_sessionOf]를 그대로 쓴다.
  /// `isOnboarded`는 방금 만든 계정이라 서버가 항상 `false`를 준다.
  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _signUpPath,
        data: {'verificationTicket': verificationTicket, 'password': password},
      );
      return _sessionOf(response.data);
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }

  /// 응답 몸통이 로그인과 같아 [_sessionOf]를 그대로 쓴다.
  ///
  /// **계정이 없으면 서버가 만들고**, 그때 `isOnboarded`는 `false`로 온다.
  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_oauthPath/${provider.path}',
        data: {
          'authorizationCode': authorization.authorizationCode,
          'codeVerifier': authorization.codeVerifier,
        },
      );
      return _sessionOf(response.data);
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }

  @override
  Future<void> sendVerificationCode(String email) async {
    try {
      // 204라 몸통이 없다. 읽을 것이 없으니 타입을 세우지 않는다.
      await _dio.post<void>(_sendCodePath, data: {'email': email});
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }

  @override
  Future<String> verifyCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _verifyCodePath,
        data: {'email': email, 'code': code},
      );
      final ticket = response.data?['verificationTicket'];
      // 200을 받아도 티켓이 없으면 가입을 시작할 수 없다. 빈 문자열로 넘기면
      // 가입 단계에서 403이 나고, 원인에서 한참 떨어진 곳에 증상이 남는다.
      if (ticket is! String || ticket.isEmpty) {
        throw const AuthException(AuthFailure.unknown);
      }
      return ticket;
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }

  /// 서버를 부르지 않는다.
  ///
  /// 서버 세션을 끊으려면 `accessToken`을 헤더에 실어야 하는데 이 저장소는
  /// 토큰을 들고 있지 않다 — 보관은 `TokenStore`의 몫이다. 인터페이스에 토큰을
  /// 받는 자리를 뚫는 일은 이 변경의 범위를 넘어선다.
  ///
  /// 호출자가 로컬 토큰을 지우므로 앱은 로그아웃된다. 다만 **서버 쪽
  /// `refreshToken`은 만료될 때까지 살아 있다.** 기기를 잃어버렸을 때
  /// 세션을 끊을 방법이 없다는 뜻이라, 토큰을 실어 보내는 일은 따로 해야 한다.
  @override
  Future<void> signOut() async {}

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _refreshPath,
        data: {'refreshToken': refreshToken},
        options: Options(
          sendTimeout: _refreshTimeout,
          receiveTimeout: _refreshTimeout,
        ),
      );
      return _tokensOf(response.data);
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }

  /// 200을 받아도 몸통이 기대와 다를 수 있다. 못 읽으면 만들지 않는다.
  AuthTokens _tokensOf(Map<String, dynamic>? body) {
    final accessToken = body?['accessToken'];
    final refreshToken = body?['refreshToken'];

    if (accessToken is! String || refreshToken is! String) {
      throw const AuthException(AuthFailure.unknown);
    }
    return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  @override
  Future<CurrentUser> fetchCurrentUser(String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _mePath,
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      return _currentUserOf(response.data);
    } on DioException catch (error) {
      // 401은 토큰이 죽은 것이다. 부르는 쪽이 갱신하고 다시 온다.
      if (error.response?.statusCode == 401) {
        throw const AuthException(AuthFailure.sessionExpired);
      }
      throw AuthException(_failureOf(error));
    }
  }

  /// 몸통에서 사람을 꺼낸다.
  ///
  /// ⚠️ **닉네임·이미지·소개글은 없을 수 있다.** 온보딩 전에는 서버가 채우지
  /// 못한다. `userId`와 `email`만 반드시 있어야 하고, 그것이 없으면 답이
  /// 계약과 다른 것이므로 세션을 믿지 않는다.
  CurrentUser _currentUserOf(Map<String, dynamic>? body) {
    final userId = body?['userId'];

    // ⚠️ **`email`을 요구하지 않는다.** 서버 규격에 그 필드가 없다. 요구하면
    // 200을 받고도 여기서 던지고, `_loadCurrentUser`가 그 예외를 삼켜
    // **닉네임도 `isOnboarded`도 영영 반영되지 않는다.** 실제로 그랬다.
    if (userId is! String) {
      throw const AuthException(AuthFailure.unknown);
    }

    return CurrentUser(
      userId: userId,
      // 값이 없거나 타입이 다르면 false로 본다. 유도 카드를 한 번 더 보이는 쪽이
      // 프로필 없는 사람에게 아무것도 안 알리는 것보다 낫다.
      isOnboarded: body?['isOnboarded'] == true,
      nickname: _stringOrNull(body?['nickname']),
      profileImageUrl: _stringOrNull(body?['profileImageUrl']),
      introduction: _stringOrNull(body?['introduction']),
    );
  }

  /// 빈 문자열도 `null`로 본다. 서버가 `""`를 주는 것과 아예 안 주는 것을
  /// 화면이 다르게 그릴 이유가 없다.
  static String? _stringOrNull(Object? value) =>
      (value is String && value.isNotEmpty) ? value : null;

  Future<AuthSession> _login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _loginPath,
        data: {'email': email, 'password': password},
      );
      return _sessionOf(response.data);
    } on DioException catch (error) {
      throw AuthException(_failureOf(error));
    }
  }

  /// 서버가 200을 줬어도 몸통이 기대와 다를 수 있다.
  ///
  /// 필드를 하나라도 못 읽으면 세션을 만들지 않는다. 빈 문자열로 채워두면
  /// 로그인은 성공한 것처럼 보이고 **그다음 API 호출부터 인증이 깨진다** —
  /// 원인에서 한참 떨어진 곳에서 증상이 나온다.
  AuthSession _sessionOf(Map<String, dynamic>? body) {
    final userId = body?['userId'];
    final accessToken = body?['accessToken'];
    final refreshToken = body?['refreshToken'];

    if (userId is! String ||
        accessToken is! String ||
        refreshToken is! String) {
      throw const AuthException(AuthFailure.unknown);
    }

    return AuthSession(
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      // ⚠️ **없으면 `null`이다. `false`가 아니다.**
      //
      // 서버가 2026-08-17 이 필드를 응답에서 뺐다. `false`로 떨어뜨리면
      // 이미 프로필을 채운 사람이 로그인할 때마다 폼으로 끌려간다.
      // 모르는 것은 모르는 채로 넘기고, 판단은 `AuthController`가 한다.
      isOnboarded: body?['isOnboarded'] is bool
          ? body!['isOnboarded'] as bool
          : null,
    );
  }

  /// 서버가 준 `code`를 앱의 실패 이유로 옮긴다.
  ///
  /// **`message`는 쓰지 않는다.** 서버 문구는 습니다체고 앱은 해요체다.
  /// 그대로 화면에 얹으면 톤이 깨지고, 서버가 문구를 고치면 앱 화면이 같이 바뀐다.
  ///
  /// ## ⚠️ `code`를 상태 코드보다 먼저 본다
  ///
  /// `EMAIL_SEND_FAILED`가 **503**이다. 5xx를 먼저 [AuthFailure.server]로
  /// 잘라내면 그 사유가 영영 나오지 않는다. 상태 코드는 **아는 `code`가 없을 때만**
  /// 쓰는 마지막 수단이다.
  AuthFailure _failureOf(DioException error) {
    // 응답 자체가 없는 경우 — 연결 실패, 시간 초과. 서버까지 닿지 못했다.
    if (error.type != DioExceptionType.badResponse) {
      return AuthFailure.network;
    }

    final response = error.response;
    final body = response?.data;
    final code = body is Map ? body['code'] : null;

    final known = switch (code) {
      'INVALID_CREDENTIALS' => AuthFailure.invalidCredentials,
      'EMAIL_ALREADY_EXISTS' => AuthFailure.emailAlreadyExists,
      'INVALID_REFRESH_TOKEN' => AuthFailure.sessionExpired,
      'INVALID_VERIFICATION_CODE' => AuthFailure.invalidCode,
      'EMAIL_VERIFICATION_NOT_FOUND' => AuthFailure.codeExpired,
      'TOO_MANY_VERIFICATION_ATTEMPTS' => AuthFailure.tooManyCodeAttempts,
      'EMAIL_VERIFICATION_COOLDOWN' => AuthFailure.sendCooldown,
      'EMAIL_VERIFICATION_DAILY_LIMIT_EXCEEDED' => AuthFailure.sendDailyLimit,
      'EMAIL_SEND_FAILED' => AuthFailure.sendFailed,
      'EMAIL_NOT_VERIFIED' => AuthFailure.emailNotVerified,
      'OAUTH_CODE_EXCHANGE_FAILED' => AuthFailure.oauthFailed,
      'OAUTH_EMAIL_NOT_PROVIDED' => AuthFailure.oauthEmailMissing,
      // 서버가 모르는 provider다. 앱이 enum으로 보내므로 정상 경로에서는
      // 나오지 않는다 — 나온다면 서버에 그 구현이 아직 없는 것이다.
      'UNSUPPORTED_PROVIDER' => AuthFailure.oauthFailed,
      _ => null,
    };
    if (known != null) return known;

    // 형식 거절은 **코드가 두 가지**다. 로그인·가입은 `VALIDATION_FAILED`인데
    // 이메일 인증 두 경로는 `INVALID_REQUEST`를 준다 — 같은 `/auth` 아래인데도
    // 다르다(2026-08-10 서버 응답으로 확인). 하나만 보면 나머지가 `unknown`으로
    // 떨어져 "로그인하지 못했어요"라는 엉뚱한 문구가 뜬다.
    if (code == 'VALIDATION_FAILED' || code == 'INVALID_REQUEST') {
      // 앱이 먼저 막았어야 할 값이 서버까지 갔다. 사유는 `message`에만 있는데
      // 그것을 갈라 읽으면 서버가 문구를 고칠 때 조용히 깨진다.
      // 화면에는 앱 문구를 쓰고, 여기서는 구멍을 찾을 단서만 남긴다.
      if (kDebugMode) {
        debugPrint('[api] 검증 거절: ${body is Map ? body['message'] : ''}');
      }
      return AuthFailure.validation;
    }

    // 아는 `code`가 없을 때만 상태 코드로 판단한다.
    if ((response?.statusCode ?? 0) >= 500) return AuthFailure.server;
    return AuthFailure.unknown;
  }
}
