import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/auth/domain/auth_session.dart';
import 'package:runiverse/features/auth/domain/auth_tokens.dart';
import 'package:runiverse/features/auth/domain/current_user.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';
import 'package:runiverse/features/onboarding/data/http_onboarding_repository.dart';
import 'package:runiverse/features/onboarding/domain/gender.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';

/// 온보딩 409를 어떻게 읽는가.
///
/// ## ⚠️ 이 저장소만 어댑터를 세워 테스트한다
///
/// 다른 `Http*Repository`는 실서버로 확인한다. 여기만 예외인 이유는 **틀렸을 때
/// 화면에 아무 표시도 나지 않기 때문**이다 — 닉네임이 겹쳐 저장이 안 됐는데
/// 성공으로 처리되면, 사용자는 프로필이 있는 줄 알고 앱을 쓴다. 서버에는 없다.
///
/// 서버가 `ALREADY_ONBOARDED`(성공으로 흡수)와 `NICKNAME_ALREADY_EXISTS`(실패)를
/// **같은 409로** 던지므로, 가르는 근거는 `code` 하나뿐이다.
void main() {
  final profile = OnboardingProfile(
    nickname: '러너42',
    gender: Gender.female,
    birthday: DateTime(1998, 3, 12),
    paceSecondsPerKm: 360,
    heightCm: 168,
    weightKg: 57,
  );

  /// 서버가 [status]와 [body]로 답하는 저장소를 만든다.
  Future<HttpOnboardingRepository> repositoryAnswering(
    int status, {
    Map<String, Object?> body = const {},
  }) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://test.invalid'))
      ..httpClientAdapter = _CannedAdapter(status, jsonEncode(body));
    final store = InMemoryTokenStore();
    // 토큰이 없으면 저장소가 서버를 부르기 전에 멈춘다.
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'access',
      refreshToken: 'refresh',
      isOnboarded: false,
    );
    return HttpOnboardingRepository(dio, store, _UnusedAuthRepository());
  }

  Future<OnboardingFailure?> failureOf(
    Future<HttpOnboardingRepository> pending,
  ) async {
    final repository = await pending;
    try {
      await repository.submit(profile);
      return null;
    } on OnboardingException catch (error) {
      return error.failure;
    }
  }

  test('201이면 성공한다', () async {
    final failure = await failureOf(
      repositoryAnswering(201, body: {'userId': 'u-1', 'nickname': '러너42'}),
    );

    expect(failure, isNull);
  });

  test('409 ALREADY_ONBOARDED는 성공으로 흡수한다', () async {
    // 이미 채운 사람이 폼을 한 번 더 지났을 뿐이다. 도메인상 성공이다.
    final failure = await failureOf(
      repositoryAnswering(409, body: {'code': 'ALREADY_ONBOARDED'}),
    );

    expect(failure, isNull);
  });

  test('⚠️ 409 NICKNAME_ALREADY_EXISTS는 실패다', () async {
    // 여기가 깨지면 **저장되지 않은 프로필로 홈에 들어간다.**
    // 화면에는 아무 이상도 보이지 않아 한참 뒤에 발견하게 된다.
    final failure = await failureOf(
      repositoryAnswering(409, body: {'code': 'NICKNAME_ALREADY_EXISTS'}),
    );

    expect(failure, OnboardingFailure.nicknameTaken);
  });

  test('⚠️ 모르는 409도 실패로 본다', () async {
    // 409는 성공의 증거가 아니다. 판단할 수 없으면 다시 시도하게 하는 쪽이,
    // 저장되지 않은 프로필로 앱을 쓰게 하는 것보다 낫다.
    final failure = await failureOf(
      repositoryAnswering(409, body: {'code': 'SOMETHING_NEW'}),
    );

    expect(failure, OnboardingFailure.unknown);
  });

  test('400은 형식 거절이다', () async {
    final failure = await failureOf(
      repositoryAnswering(400, body: {'code': 'INVALID_REQUEST'}),
    );

    expect(failure, OnboardingFailure.validation);
  });

  test('5xx는 서버 잘못이다', () async {
    final failure = await failureOf(repositoryAnswering(503));

    expect(failure, OnboardingFailure.server);
  });
}

/// 무엇을 물어도 정해진 답 하나를 돌려준다.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.status, this.body);

  final int status;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// 갱신까지 갈 일이 없는 경로만 시험한다 — 401을 흉내 내지 않는다.
class _UnusedAuthRepository implements AuthRepository {
  Never _unused() => throw UnimplementedError();

  @override
  Future<AuthTokens> refresh(String refreshToken) => _unused();
  @override
  Future<CurrentUser> fetchCurrentUser(String accessToken) => _unused();
  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => _unused();
  @override
  Future<AuthSession> signUp({
    required String verificationTicket,
    required String password,
  }) => _unused();
  @override
  Future<AuthSession> signInWithOauth({
    required OauthProvider provider,
    required OauthAuthorization authorization,
  }) => _unused();
  @override
  Future<void> sendVerificationCode(String email) => _unused();
  @override
  Future<String> verifyCode({required String email, required String code}) =>
      _unused();
  @override
  Future<void> signOut() => _unused();
}
