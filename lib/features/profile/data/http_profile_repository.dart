import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/domain/profile_failure.dart';
import 'package:runiverse/features/profile/domain/profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_summary.dart';

/// 진짜 서버를 부르는 [ProfileRepository].
///
/// 401이면 **한 번만** 갱신하고 다시 부른다. `HttpProfileImageRepository`와
/// 같은 규칙이다.
class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._dio, this._store, this._auth);

  final Dio _dio;
  final TokenStore _store;
  final AuthRepository _auth;

  static String _path(String userId) => '/api/v1/users/$userId';

  static const _profilePath = '/api/v1/users/me/profile';

  @override
  Future<ProfileSummary> fetch(String userId) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const ProfileException(ProfileFailure.sessionExpired);
    }

    try {
      return await _get(userId, accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw ProfileException(_failureOf(error));
      }
      try {
        return await _get(userId, await _refreshed(stored.refreshToken));
      } on DioException catch (retried) {
        throw ProfileException(_failureOf(retried));
      }
    }
  }

  @override
  Future<void> updateProfile({
    String? introduction,
    DateTime? birthday,
    double? weightKg,
    double? heightCm,
  }) async {
    final body = <String, dynamic>{
      // ⚠️ `?`는 `null`만 걸러낸다. `''`는 그대로 실려 나가고, 서버는 그것을
      // **소개글 삭제**로 읽는다 — 둘을 같이 다루면 지울 방법이 없어진다.
      'introduction': ?introduction,
      if (birthday != null) 'birthday': _dateOf(birthday),
      'weightKg': ?weightKg,
      'heightCm': ?heightCm,
    };
    // 바꿀 것이 없다. 요청을 만들지 않는다 — 서버에 갔다 와도 결과가 같다.
    if (body.isEmpty) return;

    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const ProfileEditException(ProfileEditFailure.sessionExpired);
    }

    try {
      await _patchProfile(body, accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw ProfileEditException(_editFailureOf(error));
      }
      try {
        await _patchProfile(body, await _refreshedForEdit(stored.refreshToken));
      } on DioException catch (retried) {
        throw ProfileEditException(_editFailureOf(retried));
      }
    }
  }

  Future<void> _patchProfile(
    Map<String, dynamic> body,
    String accessToken,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      _profilePath,
      data: body,
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        validateStatus: (status) =>
            status != null && (status < 400 || status == 409),
      ),
    );
    // 409는 하나뿐이지만 코드를 확인한다. 모르는 409를 성공으로 흘리면
    // **바뀌지 않은 값이 화면에 바뀐 것처럼 남는다.**
    if (response.statusCode == 409) {
      throw ProfileEditException(
        response.data?['code'] == 'ONBOARDING_NOT_COMPLETED'
            ? ProfileEditFailure.notOnboarded
            : ProfileEditFailure.unknown,
      );
    }
  }

  /// `YYYY-MM-DD`. 달력 날짜라 시각·타임존이 붙지 않는다.
  static String _dateOf(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}'
      '-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';

  Future<String> _refreshedForEdit(String? refreshToken) async {
    try {
      return await _refreshed(refreshToken);
    } on ProfileException catch (error) {
      throw ProfileEditException(
        error.failure == ProfileFailure.network
            ? ProfileEditFailure.network
            : ProfileEditFailure.sessionExpired,
      );
    }
  }

  ProfileEditFailure _editFailureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return ProfileEditFailure.network;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 400) return ProfileEditFailure.invalid;
    if (status == 401) return ProfileEditFailure.sessionExpired;
    return ProfileEditFailure.unknown;
  }

  Future<ProfileSummary> _get(String userId, String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _path(userId),
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return _summaryOf(response.data);
  }

  /// 200인데 몸통이 기대와 다를 수 있다. `userId` 하나만 필수로 본다 —
  /// 나머지는 온보딩 전이면 정말로 `null`이다.
  ProfileSummary _summaryOf(Map<String, dynamic>? body) {
    final userId = body?['userId'];
    if (userId is! String) {
      throw const ProfileException(ProfileFailure.unknown);
    }
    final friendCount = body?['friendCount'];
    return ProfileSummary(
      userId: userId,
      nickname: _stringOrNull(body?['nickname']),
      profileImageUrl: _stringOrNull(body?['profileImageUrl']),
      introduction: _stringOrNull(body?['introduction']),
      // 없으면 0으로 둔다. 셀 수 없다는 것과 아무도 없다는 것은 화면에서
      // 같은 그림이고, `null`을 흘려보내면 그릴 때마다 물어야 한다.
      friendCount: friendCount is int ? friendCount : 0,
    );
  }

  static String? _stringOrNull(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const ProfileException(ProfileFailure.sessionExpired);
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
      throw ProfileException(
        error.failure == AuthFailure.network
            ? ProfileFailure.network
            : ProfileFailure.sessionExpired,
      );
    }
  }

  ProfileFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return ProfileFailure.network;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 404) return ProfileFailure.notFound;
    if (status == 401) return ProfileFailure.sessionExpired;
    if (status >= 500) return ProfileFailure.server;
    return ProfileFailure.unknown;
  }
}
