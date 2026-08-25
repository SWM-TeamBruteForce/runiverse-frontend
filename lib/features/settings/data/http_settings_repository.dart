import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/settings/domain/account_info.dart';
import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/domain/login_type.dart';
import 'package:runiverse/features/settings/domain/password_change_failure.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';
import 'package:runiverse/features/settings/domain/settings_repository.dart';

/// 진짜 서버를 부르는 [SettingsRepository].
///
/// 401이면 **한 번만** 갱신하고 다시 부른다 — `HttpProfileRepository`와 같은 규칙이다.
/// **[changePassword]만 예외다.** 아래를 보라.
class HttpSettingsRepository implements SettingsRepository {
  HttpSettingsRepository(this._dio, this._store, this._auth);

  final Dio _dio;
  final TokenStore _store;
  final AuthRepository _auth;

  static const _accountPath = '/api/v1/users/me/account';
  static const _settingsPath = '/api/v1/users/me/settings';
  static const _passwordPath = '/api/v1/users/me/password';

  /// ⚠️ **4차 API 명세서에 없는 경로다.** 2.5차에 있던 것을 그대로 쓴다.
  /// 기능정의서도 *"권장, 실제 경로 협의 필요"*라고만 적었다. 바뀌면 이 줄이다.
  static const _withdrawPath = '/api/v1/users/me';

  @override
  Future<AccountInfo> fetchAccount() => _authorized((token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _accountPath,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final email = response.data?['email'];
    // 200인데 몸통이 다르다. 이메일이 없으면 계정 섹션에 그릴 것이 없다.
    if (email is! String || email.isEmpty) {
      throw const SettingsException(SettingsFailure.unknown);
    }
    return AccountInfo(
      email: email,
      // 모르는 값이면 `null`이 되고, 비밀번호 메뉴가 숨는다.
      loginType: LoginType.fromWire(_stringOrNull(response.data?['loginType'])),
    );
  });

  @override
  Future<AppSettings> fetchSettings() => _authorized((token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _settingsPath,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return _settingsOf(response.data);
  });

  @override
  Future<AppSettings> updateSettings({
    bool? alertConsent,
    ProfileVisibility? visibility,
  }) {
    final body = <String, dynamic>{
      'alertConsent': ?alertConsent,
      if (visibility != null) 'profileVisibility': visibility.wireValue,
    };

    return _authorized((token) async {
      final response = await _dio.patch<Map<String, dynamic>>(
        _settingsPath,
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      // **응답을 그대로 쓴다.** 보낸 값을 쓰면 연타했을 때 화면과 서버가 갈라진다.
      return _settingsOf(response.data);
    });
  }

  @override
  Future<void> withdraw() => _authorized((token) async {
    await _dio.delete<void>(
      _withdrawPath,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  });

  /// ## ⚠️ 여기만 401 재시도 규칙이 다르다
  ///
  /// 서버는 **현재 비밀번호가 틀린 것도 401**로 답한다
  /// (`INVALID_CURRENT_PASSWORD`). 이것을 세션 만료로 보고 갱신 후 재시도하면
  /// 같은 답이 한 번 더 오고, 그사이 토큰만 회전된다. 결국 비밀번호를 틀린
  /// 사람이 로그아웃될 수도 있다.
  ///
  /// 그래서 `code`를 먼저 보고 **재시도할 401인지 가른다.**
  @override
  Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const PasswordChangeException(PasswordChangeFailure.sessionExpired);
    }

    final body = {'currentPassword': current, 'newPassword': next};
    try {
      await _patchPassword(body, accessToken);
    } on DioException catch (error) {
      final failure = _passwordFailureOf(error);
      // 세션 만료가 아니면 그대로 올린다 — 갱신해도 답이 달라지지 않는다.
      if (failure != PasswordChangeFailure.sessionExpired) {
        throw PasswordChangeException(failure);
      }
      try {
        await _patchPassword(
          body,
          await _refreshedForPassword(stored.refreshToken),
        );
      } on DioException catch (retried) {
        throw PasswordChangeException(_passwordFailureOf(retried));
      }
    }
  }

  Future<void> _patchPassword(
    Map<String, dynamic> body,
    String accessToken,
  ) async {
    await _dio.patch<void>(
      _passwordPath,
      data: body,
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
  }

  /// 401이면 한 번만 갱신하고 다시 부른다.
  ///
  /// 토큰을 [call]에 넘기는 이유는, 갱신한 뒤 **같은 요청을 새 토큰으로**
  /// 다시 보내야 해서다. 요청을 통째로 함수로 받으면 그게 자연스럽다.
  Future<T> _authorized<T>(Future<T> Function(String accessToken) call) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const SettingsException(SettingsFailure.sessionExpired);
    }

    try {
      return await call(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw SettingsException(_failureOf(error));
      }
      try {
        return await call(await _refreshed(stored.refreshToken));
      } on DioException catch (retried) {
        throw SettingsException(_failureOf(retried));
      }
    }
  }

  /// 200인데 몸통이 기대와 다를 수 있다.
  ///
  /// 두 필드 모두 명세상 필수다. 하나라도 읽지 못하면 **기본값으로 때우지 않는다** —
  /// 서버가 `false`를 보냈는데 `true`로 그리면 사용자는 끈 적 없는 설정이
  /// 켜져 있는 것을 본다.
  AppSettings _settingsOf(Map<String, dynamic>? body) {
    final alertConsent = body?['alertConsent'];
    final visibility = ProfileVisibility.fromWire(
      _stringOrNull(body?['profileVisibility']),
    );
    if (alertConsent is! bool || visibility == null) {
      throw const SettingsException(SettingsFailure.unknown);
    }
    return AppSettings(alertConsent: alertConsent, visibility: visibility);
  }

  static String? _stringOrNull(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const SettingsException(SettingsFailure.sessionExpired);
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
      throw SettingsException(
        error.failure == AuthFailure.network
            ? SettingsFailure.network
            : SettingsFailure.sessionExpired,
      );
    }
  }

  /// 갱신이 실패하면 [SettingsException]이 나온다. 비밀번호 화면은 그것을
  /// 잡지 않으므로 여기서 이 경로의 말로 옮긴다.
  Future<String> _refreshedForPassword(String? refreshToken) async {
    try {
      return await _refreshed(refreshToken);
    } on SettingsException catch (error) {
      throw PasswordChangeException(
        error.failure == SettingsFailure.network
            ? PasswordChangeFailure.network
            : PasswordChangeFailure.sessionExpired,
      );
    }
  }

  SettingsFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return SettingsFailure.network;
    }
    final status = error.response?.statusCode ?? 0;
    if (status == 401) return SettingsFailure.sessionExpired;
    if (status >= 500) return SettingsFailure.server;
    return SettingsFailure.unknown;
  }

  /// 같은 401이 두 가지 뜻이라 `code`로 가른다.
  PasswordChangeFailure _passwordFailureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return PasswordChangeFailure.network;
    }
    final data = error.response?.data;
    final code = data is Map ? data['code'] : null;
    final status = error.response?.statusCode ?? 0;

    if (status == 401) {
      return code == 'INVALID_CURRENT_PASSWORD'
          ? PasswordChangeFailure.wrongCurrentPassword
          : PasswordChangeFailure.sessionExpired;
    }
    if (status == 409) return PasswordChangeFailure.notLocalAccount;
    if (status == 400) return PasswordChangeFailure.invalidNewPassword;
    if (status >= 500) return PasswordChangeFailure.server;
    return PasswordChangeFailure.unknown;
  }
}
