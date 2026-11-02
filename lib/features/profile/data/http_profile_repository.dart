import 'package:dio/dio.dart';
import 'package:runiverse/features/friend/domain/friend_relation.dart';
import 'package:runiverse/core/storage/body_profile_remote.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/domain/profile_failure.dart';
import 'package:runiverse/features/profile/domain/profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_summary.dart';

/// 진짜 서버를 부르는 [ProfileRepository].
///
/// 401이면 **한 번만** 갱신하고 다시 부른다. `HttpProfileImageRepository`와
/// 같은 규칙이다. 갱신은 반드시 [TokenRefresher]를 거친다
/// (`docs/implementation-notes.md` 9-6).
class HttpProfileRepository implements ProfileRepository {
  HttpProfileRepository(this._dio, this._store, this._refresher);

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  static String _path(String userId) => '/api/v1/users/$userId';

  /// ⚠️ `me`다. 본인 것만 바꿀 수 있어 경로에 `userId`가 들어가지 않는다.
  static const _nicknamePath = '/api/v1/users/me/nickname';

  static const _availabilityPath = '/api/v1/users/nickname/availability';

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
        return await _get(userId, await _refreshed());
      } on DioException catch (retried) {
        throw ProfileException(_failureOf(retried));
      }
    }
  }

  @override
  Future<String> changeNickname(String nickname) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const NicknameChangeException(NicknameChangeFailure.sessionExpired);
    }

    try {
      return await _patchNickname(nickname, accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw NicknameChangeException(_nicknameFailureOf(error));
      }
      try {
        return await _patchNickname(
          nickname,
          // ⚠️ 갱신이 실패하면 [ProfileException]이 나온다. 시트는 그것을
          // 잡지 않으므로 여기서 이 경로의 말로 옮긴다.
          await _refreshedForNickname(),
        );
      } on DioException catch (retried) {
        throw NicknameChangeException(_nicknameFailureOf(retried));
      }
    }
  }

  /// ⚠️ **토큰을 붙이지 않는다.** 서버가 이 경로만 공개로 열어 뒀다
  /// (`SecurityConfig.PUBLIC_ENDPOINTS`). 그래서 만료·갱신을 다룰 것이 없다.
  @override
  Future<bool?> isNicknameAvailable(String nickname) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _availabilityPath,
        data: {'nickname': nickname},
      );
      final available = response.data?['available'];
      // 200인데 몸통이 다르다. `false`로 떨어뜨리면 멀쩡한 이름이 거절된다.
      return available is bool ? available : null;
    } on DioException {
      // 왜 못 물었는지 가르지 않는다. 화면이 할 일은 "확인하지 못했다" 하나다.
      return null;
    }
  }

  /// 신체 정보를 읽는다(51번). **`StoredBody`로 좁혀 담는다** — 응답의
  /// `introduction`·`gender`는 이 포트가 다루지 않는다([BodyProfileRemote]).
  @override
  Future<StoredBody> fetchBody() async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const ProfileException(ProfileFailure.sessionExpired);
    }

    try {
      return await _getBody(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw ProfileException(_failureOf(error));
      }
      try {
        return await _getBody(await _refreshed());
      } on DioException catch (retried) {
        throw ProfileException(_failureOf(retried));
      }
    }
  }

  Future<StoredBody> _getBody(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _profilePath,
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    final body = response.data;
    return StoredBody(
      // ⚠️ **`as String?`로 읽지 않는다.** 200인데 타입이 다르면 그 캐스팅이
      // 던지고, 프로필 편집은 그것을 *불러오기 실패*로 읽어 칸을 잠근다.
      // 모르는 값은 "없다"로 다룬다 — 그쪽이 서버가 말한 것에 더 가깝다.
      birthday: DateTime.tryParse(_stringOrNull(body?['birthday']) ?? ''),
      heightCm: _roundedOrNull(body?['heightCm']),
      weightKg: _roundedOrNull(body?['weightKg']),
    );
  }

  /// ⚠️ **`as int`로 읽으면 터진다.** 서버가 소수 한 자리로 저장해
  /// `70.5`가 온다(명세 51번). 앱의 선택기는 정수라 반올림해 담는다.
  ///
  /// 반올림이 값을 흘리지 않는다 — 앱은 정수만 보내므로, 소수가 들어 있다면
  /// 다른 데서 들어온 값이고 그때도 **고치지 않으면 보내지 않는다**
  /// (`ProfileEditPage`가 바뀐 것만 싣는다).
  static int? _roundedOrNull(Object? value) =>
      value is num ? value.round() : null;

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
        await _patchProfile(body, await _refreshedForEdit());
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

  Future<String> _refreshedForEdit() async {
    try {
      return await _refreshed();
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

  /// 409는 예외로 만들지 않고 받아서 [_resolveNicknameConflict]에 넘긴다.
  Future<String> _patchNickname(String nickname, String accessToken) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      _nicknamePath,
      data: {'nickname': nickname},
      options: Options(
        headers: {'Authorization': 'Bearer $accessToken'},
        validateStatus: (status) =>
            status != null && (status < 400 || status == 409),
      ),
    );
    if (response.statusCode == 409) _resolveNicknameConflict(response.data);

    // **서버가 확정한 값**을 쓴다. 보낸 값을 그대로 화면에 올리면 서버가
    // 다듬었을 때 화면과 서버가 갈라진다.
    final changed = response.data?['nickname'];
    if (changed is! String || changed.isEmpty) {
      // 200인데 몸통이 다르다. 바뀌었는지 알 수 없으니 성공이라고 말하지 않는다.
      throw const NicknameChangeException(NicknameChangeFailure.unknown);
    }
    return changed;
  }

  /// 409가 무엇을 뜻하는지 `code`로 가른다.
  ///
  /// ⚠️ **성공으로 흡수할 코드가 하나도 없다.** 온보딩(9번)의 409에는
  /// `ALREADY_ONBOARDED`처럼 도메인상 성공인 것이 섞여 있지만, 여기서는
  /// 어느 쪽이든 이름이 안 바뀐 것이다. 모르는 코드도 실패로 본다.
  Never _resolveNicknameConflict(Map<String, dynamic>? body) {
    switch (body?['code']) {
      case 'NICKNAME_ALREADY_EXISTS':
        throw const NicknameChangeException(NicknameChangeFailure.taken);
      case 'ONBOARDING_NOT_COMPLETED':
        throw const NicknameChangeException(NicknameChangeFailure.notOnboarded);
      default:
        throw const NicknameChangeException(NicknameChangeFailure.unknown);
    }
  }

  Future<String> _refreshedForNickname() async {
    try {
      return await _refreshed();
    } on ProfileException catch (error) {
      throw NicknameChangeException(
        error.failure == ProfileFailure.network
            ? NicknameChangeFailure.network
            : NicknameChangeFailure.sessionExpired,
      );
    }
  }

  NicknameChangeFailure _nicknameFailureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return NicknameChangeFailure.network;
    }
    final status = error.response?.statusCode ?? 0;
    // ⚠️ 400은 앱 규칙이 서버와 어긋났다는 신호다. 앱이 먼저 막고 있으니
    // 정상 경로에서는 나오지 않는다.
    if (status == 400) return NicknameChangeFailure.invalid;
    if (status == 401) return NicknameChangeFailure.sessionExpired;
    return NicknameChangeFailure.unknown;
  }

  Future<ProfileSummary> _get(String userId, String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _path(userId),
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return summaryOf(response.data);
  }

  /// 200인데 몸통이 기대와 다를 수 있다. `userId` 하나만 필수로 본다 —
  /// 나머지는 온보딩 전이면 정말로 `null`이다.
  ///
  /// **테스트가 직접 부른다.**
  static ProfileSummary summaryOf(Map<String, dynamic>? body) {
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
      // ⚠️ **없으면 거짓이다.** 못 읽었다고 내 것으로 읽으면 남의 화면에
      // "프로필 편집"이 뜬다.
      isMe: body?['isMe'] == true,
      // ⚠️ **1.2.0에서 `friendStatus`에서 개명됐다.** 값도 친구 API와 같은
      // 어휘로 합쳐졌다(`ACCEPTED` → `FRIEND`). 키를 안 고치면 관계가 늘
      // `null`로 읽혀 **친구인 사람에게 "친구 요청" 버튼이 뜬다.**
      //
      // `friendRelationOf`는 옛 어휘도 받는다 — 서버가 1.1.x를 내리는 동안
      // 섞일 수 있고, 받아 두는 비용이 없다.
      relation: friendRelationOf(body?['relationshipType']),
    );
  }

  static String? _stringOrNull(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  Future<String> _refreshed() async {
    final accessToken = await _refresher.refresh();
    if (accessToken == null) {
      throw const ProfileException(ProfileFailure.sessionExpired);
    }
    return accessToken;
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
