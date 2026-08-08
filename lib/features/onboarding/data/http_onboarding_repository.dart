import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/onboarding/data/onboarding_profile_dto.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_repository.dart';

/// 진짜 서버를 부르는 [OnboardingRepository].
///
/// ## 인터셉터를 쓰지 않는다
///
/// `Authorization` 헤더가 필요한 요청은 지금 이것 하나뿐이다. 인터셉터를 만들면
/// 요청마다 저장소를 읽거나 토큰 캐시를 따로 관리해야 하는데, 대상이 하나인
/// 상태에서는 **관리할 것만 늘어난다.** 인증 요청이 늘어나는 시점에 올린다.
///
/// ## 왜 `AuthRepository`를 받는가
///
/// access 토큰은 30분이라 프로필을 천천히 채우는 동안 만료될 수 있다. 그때 401을
/// 그대로 돌려주면 **다섯 개를 다 입력한 사람의 값이 날아간다.** 여기서 갱신 한 번을
/// 하고 다시 보낸다.
///
/// ## 409를 예외로 받지 않는다
///
/// [_post]가 `validateStatus`로 409를 통과시킨다. 예외로 받으면 "이미 온보딩됨"을
/// 흡수하는 흐름과 "access 만료라 갱신" 흐름이 **한 `catch` 안에 섞인다.**
class HttpOnboardingRepository implements OnboardingRepository {
  HttpOnboardingRepository(this._dio, this._store, this._auth);

  final Dio _dio;
  final TokenStore _store;
  final AuthRepository _auth;

  static const _path = '/api/v1/users/onboarding';

  @override
  Future<void> submit(OnboardingProfile profile) async {
    final body = OnboardingProfileDto.from(profile).toJson();

    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      // 토큰 없이 부르면 서버가 401을 준다. 그 전에 멈춘다 —
      // 원인이 "로그인이 안 되어 있다"인데 서버 응답을 뒤지게 된다.
      throw const OnboardingException(OnboardingFailure.sessionExpired);
    }

    try {
      await _post(body, accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw OnboardingException(_failureOf(error));
      }
      // access가 만료됐다. 갱신하고 한 번만 다시 보낸다.
      try {
        await _post(body, await _refreshed(stored.refreshToken));
      } on DioException catch (retried) {
        throw OnboardingException(_failureOf(retried));
      }
    }
  }

  /// 409는 성공으로 흡수하므로 dio가 예외로 만들지 않게 한다.
  Future<void> _post(Map<String, dynamic> body, String accessToken) => _dio
      .post<Object?>(
        _path,
        data: body,
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          validateStatus: (status) =>
              status != null && (status < 400 || status == 409),
        ),
      )
      .then((_) {});

  /// 새 access 토큰을 받아 저장하고 돌려준다.
  ///
  /// 갱신에 실패하면 되살릴 방법이 없다 — 다시 로그인해야 한다.
  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const OnboardingException(OnboardingFailure.sessionExpired);
    }
    try {
      final tokens = await _auth.refresh(refreshToken);
      // ⚠️ 회전된 refreshToken도 반드시 덮어쓴다. 안 하면 다음 갱신이 죽는다.
      await _store.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens.accessToken;
    } on AuthException catch (error) {
      throw OnboardingException(
        error.failure == AuthFailure.network
            ? OnboardingFailure.network
            : OnboardingFailure.sessionExpired,
      );
    }
  }

  /// 서버가 준 응답을 앱의 실패 이유로 옮긴다.
  ///
  /// **상태 코드를 1차 근거로 삼는다.** `code` 노출 정책이 바뀌어도 동작한다.
  OnboardingFailure _failureOf(DioException error) {
    // 응답 자체가 없는 경우 — 연결 실패, 시간 초과.
    if (error.type != DioExceptionType.badResponse) {
      return OnboardingFailure.network;
    }

    final response = error.response;
    final status = response?.statusCode ?? 0;
    if (status >= 500) return OnboardingFailure.server;

    if (status == 400) {
      // 사유는 `message`에만 있는데 그것을 갈라 읽으면 서버가 문구를 고칠 때
      // 조용히 깨진다. 화면에는 앱 문구를 쓰고, 여기서는 단서만 남긴다.
      if (kDebugMode) {
        final body = response?.data;
        debugPrint('[api] 온보딩 거절: ${body is Map ? body['message'] : ''}');
      }
      return OnboardingFailure.validation;
    }

    if (status == 401) return OnboardingFailure.sessionExpired;
    return OnboardingFailure.unknown;
  }
}
