import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/data/http_auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 소셜 로그인 실패 응답을 앱이 제대로 읽는가.
///
/// ## ⚠️ 이 매핑에는 그물이 없었다
///
/// `kakao_login_test` 는 `FakeOauthCodeSource` 로 실패를 **주입**한다 — 서버
/// 응답을 지나지 않는다. 그래서 2026-09-29 서버가 401 코드 이름을
/// `OAUTH_CODE_EXCHANGE_FAILED` → `OAUTH_LOGIN_FAILED` 로 바꿨을 때
/// **아무것도 깨지지 않은 채** 매핑이 죽었다. 401 이 `unknown` 으로 떨어져
/// 엉뚱한 문구가 떴다.
///
/// 서버를 띄우지 않고 **dio 어댑터만 갈아끼워** 실제 파싱 코드를 지난다.
void main() {
  Future<AuthFailure> failureOf(int status, String code) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))
      ..httpClientAdapter = _ErrorAdapter(status, code);

    try {
      await HttpAuthRepository(dio).signInWithOauth(
        provider: OauthProvider.kakao,
        authorization: const OauthCode(
          authorizationCode: 'code',
          codeVerifier: 'verifier',
        ),
      );
    } on AuthException catch (error) {
      return error.failure;
    }
    fail('실패를 던져야 한다');
  }

  test('⚠️ 401 OAUTH_LOGIN_FAILED — 서버가 2026-09-29 에 이름을 바꿨다', () async {
    expect(await failureOf(401, 'OAUTH_LOGIN_FAILED'), AuthFailure.oauthFailed);
  });

  test('403 OAUTH_EMAIL_NOT_PROVIDED', () async {
    expect(
      await failureOf(403, 'OAUTH_EMAIL_NOT_PROVIDED'),
      AuthFailure.oauthEmailMissing,
    );
  });

  test('409 EMAIL_ALREADY_EXISTS', () async {
    expect(
      await failureOf(409, 'EMAIL_ALREADY_EXISTS'),
      AuthFailure.emailAlreadyExists,
    );
  });

  test('⚠️ 503 OAUTH_PROVIDER_UNAVAILABLE — 매핑이 없어도 5xx 로 받는다', () async {
    // 새로 생긴 코드다. 이름을 모르더라도 "잠시 후 다시" 문구가 떠야 한다.
    expect(
      await failureOf(503, 'OAUTH_PROVIDER_UNAVAILABLE'),
      AuthFailure.server,
    );
  });

  test('⚠️ 모르는 코드는 unknown 이다 — 조용히 넘기지 않는다', () async {
    // 이 줄이 위 네 개의 의미를 지킨다. 무엇이든 `oauthFailed` 로 떨어지면
    // 이름이 바뀌어도 테스트가 통과해 버린다.
    expect(await failureOf(401, 'SOMETHING_NEW'), AuthFailure.unknown);
  });

  /// 보내는 모양 — **경로와 본문이 제공자마다 다르다.**
  ///
  /// 실패 매핑만 보던 그물에는 이 구멍이 있었다. 본문의 열쇠 이름이 틀리면
  /// 서버는 400 `INVALID_REQUEST`를 주는데, 그 화면 문구("입력을 확인해
  /// 주세요")가 원인을 가린다.
  group('보내는 모양', () {
    /// 요청을 가로채 **보낸 것 그대로** 돌려준다.
    Future<_Sent> sentOf(
      OauthProvider provider,
      OauthAuthorization authorization,
    ) async {
      final adapter = _CaptureAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))
        ..httpClientAdapter = adapter;

      await HttpAuthRepository(
        dio,
      ).signInWithOauth(provider: provider, authorization: authorization);
      return adapter.sent!;
    }

    test('⚠️ 애플은 ID 토큰과 nonce 원본을 함께 보낸다', () async {
      final sent = await sentOf(
        OauthProvider.apple,
        const OauthIdTokenWithNonce(idToken: 'id-token', nonce: 'raw-nonce'),
      );

      expect(sent.path, '/api/v1/auth/oauth/apple');
      expect(sent.body, {'idToken': 'id-token', 'nonce': 'raw-nonce'});
    });

    test('⚠️ 구글에는 nonce 가 붙지 않는다', () async {
      // 애플을 붙이면서 공통 자리에 nonce 를 넣으면, 구글 요청에 모르는
      // 열쇠가 섞여 들어간다.
      final sent = await sentOf(
        OauthProvider.google,
        const OauthIdToken('id-token'),
      );

      expect(sent.path, '/api/v1/auth/oauth/google');
      expect(sent.body, {'idToken': 'id-token'});
    });

    test('카카오는 인가 코드와 검증값이다', () async {
      final sent = await sentOf(
        OauthProvider.kakao,
        const OauthCode(authorizationCode: 'code', codeVerifier: 'verifier'),
      );

      expect(sent.path, '/api/v1/auth/oauth/kakao');
      expect(sent.body, {
        'authorizationCode': 'code',
        'codeVerifier': 'verifier',
      });
    });
  });
}

/// 앱이 실제로 내보낸 경로와 본문.
class _Sent {
  const _Sent(this.path, this.body);

  final String path;
  final Map<String, dynamic> body;
}

/// 요청을 받아 적고, 성공 응답을 흉내 내 돌려준다.
class _CaptureAdapter implements HttpClientAdapter {
  _Sent? sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent = _Sent(options.path, (options.data as Map).cast<String, dynamic>());

    return ResponseBody.fromString(
      jsonEncode({
        'userId': 'u-1',
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'isOnboarded': true,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 정해둔 상태 코드와 `code` 로 거절한다.
class _ErrorAdapter implements HttpClientAdapter {
  _ErrorAdapter(this.status, this.code);

  final int status;
  final String code;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'code': code, 'message': '테스트'}),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
