import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/auth_repository.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_repository.dart';

/// 진짜 서버를 부르는 [ProfileImageRepository].
///
/// ## 올리는 데 세 번을 부른다
///
/// 1. `POST .../profile-image/presigned-url` — 우리 서버에게 **올릴 자리**를 받는다
/// 2. `PUT <uploadUrl>` — **S3에 직접** 올린다. 우리 서버를 거치지 않는다
/// 3. `PATCH .../profile-image` — 우리 서버에게 **다 올렸다**고 알린다
///
/// 2번이 성공하고 3번이 실패하면 S3에 주인 없는 파일이 남는다. 앱에서는 지울 수
/// 없다 — 서버가 만료 정책으로 치우는 일이고, 사용자에게는 실패로 보이면 된다.
///
/// ## ⚠️ 2번은 [_uploadDio]로 보낸다
///
/// `dio_client`의 [Dio]에는 `baseUrl`이 박혀 있고, 여기서 `Authorization`을 얹으면
/// **S3가 그 헤더까지 서명 검증에 넣어 403을 준다.** 아무것도 붙지 않은 [Dio]를
/// 따로 쓴다.
class HttpProfileImageRepository implements ProfileImageRepository {
  HttpProfileImageRepository(
    this._dio,
    this._store,
    this._auth, {
    Dio? uploadDio,
  }) : _uploadDio = uploadDio ?? Dio();

  final Dio _dio;

  /// S3 전용. `baseUrl`도 인터셉터도 없다. 위 ⚠️ 참조.
  final Dio _uploadDio;

  final TokenStore _store;
  final AuthRepository _auth;

  /// ⚠️ **인증을 걸지 않는다.** 명세의 사진 4종 중 이것만 `권한: NO`다.
  /// [_authed]로 감싸면 붙는 401 재시도 경로가 **영영 실행되지 않는 죽은 코드**로
  /// 남는다. `userId`는 여전히 필요해서 저장소에서 읽는다.
  @override
  Future<String?> fetchUrl() async {
    final stored = await _store.read();
    final userId = stored.userId;
    if (userId == null) {
      throw const ProfileImageException(ProfileImageFailure.sessionExpired);
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(_userPath(userId));
      // 사진을 올린 적이 없으면 서버가 `null`을 담아 200을 준다. 실패가 아니다.
      final url = response.data?['profileImageUrl'];
      return url is String ? url : null;
    } on DioException catch (error) {
      throw ProfileImageException(_failureOf(error));
    }
  }

  @override
  Future<void> upload(PickedImage image) async {
    // 파일을 먼저 읽는다. 발급을 받아 두고 읽기에 실패하면 쓰지 않을 서명만 남는다.
    //
    // ⚠️ **`Uint8List`여야 한다.** dio는 `Uint8List`만 그대로 흘려보내고,
    // 그냥 `List<int>`면 `toString()`을 거쳐 `[137, 80, ...]`이라는 **글자**가
    // 올라간다. 길이도 내용도 서명과 어긋나 403이 되는데, 원인이 전혀 보이지 않는다.
    final Uint8List bytes;
    try {
      bytes = await File(image.path).readAsBytes();
    } on FileSystemException {
      throw const ProfileImageException(ProfileImageFailure.upload);
    }

    // 읽어 보니 고를 때와 크기가 다르다. 서명은 [PickedImage.sizeBytes]로 받게
    // 되므로 그대로 올리면 403이다. 여기서 멈춰야 원인이 가까운 곳에 남는다.
    if (bytes.length != image.sizeBytes) {
      throw const ProfileImageException(ProfileImageFailure.upload);
    }

    final issued = await _requestUploadUrl(image);
    await _putToS3(issued.uploadUrl, bytes, image.mimeType);
    await _confirm(issued.key);
  }

  @override
  Future<void> remove() => _authed((userId, token) async {
    await _dio.delete<Object?>(
      _mePath,
      options: Options(headers: _bearer(token)),
    );
  });

  /// 1단계. 올릴 자리와 키를 받는다.
  ///
  /// 여기 보내는 두 값이 **서명에 그대로 들어간다.** 2단계에서 같은 값을 헤더로
  /// 보내지 않으면 S3가 거절한다.
  Future<({String key, String uploadUrl})> _requestUploadUrl(
    PickedImage image,
  ) {
    return _authed((userId, token) async {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_mePath/presigned-url',
        data: {'mimeType': image.mimeType, 'fileSizeBytes': image.sizeBytes},
        options: Options(headers: _bearer(token)),
      );
      final key = response.data?['profileImageKey'];
      final uploadUrl = response.data?['uploadUrl'];
      if (key is! String || uploadUrl is! String) {
        // 200인데 몸통이 다르다. 이대로 2단계로 가면 빈 주소에 올리게 된다.
        throw const ProfileImageException(ProfileImageFailure.unknown);
      }
      return (key: key, uploadUrl: uploadUrl);
    });
  }

  /// 2단계. S3에 직접 올린다.
  ///
  /// `Content-Length`는 dio가 [Uint8List] 길이로 자동으로 붙인다 — 직접 넣지 않는다.
  /// 두 군데서 정하면 어긋날 자리가 생긴다.
  Future<void> _putToS3(
    String uploadUrl,
    Uint8List bytes,
    String mimeType,
  ) async {
    try {
      await _uploadDio.put<Object?>(
        uploadUrl,
        data: bytes,
        options: Options(
          contentType: mimeType,
          // S3는 성공에 빈 몸통을 준다. json으로 파싱하려 들면 그때 깨진다.
          responseType: ResponseType.plain,
        ),
      );
    } on DioException {
      // 여기서 오는 403은 서명 불일치다. 사용자에게는 구분해줄 것이 없고,
      // 우리 서버 실패와 섞이지만 않으면 된다.
      throw const ProfileImageException(ProfileImageFailure.upload);
    }
  }

  /// 3단계. 올렸다고 알린다.
  ///
  /// 서버는 이 키를 믿지 않는다 — 주인이 맞는지, S3에 진짜 있는지, 크기와 타입이
  /// 맞는지 다시 본다(`ChangeProfileImageHandler`). 그래서 여기 400이 오면
  /// **2단계가 사실은 실패했을 수 있다.**
  Future<void> _confirm(String key) => _authed((userId, token) async {
    await _dio.patch<Object?>(
      _mePath,
      data: {'profileImageKey': key},
      options: Options(headers: _bearer(token)),
    );
  });

  /// 인증이 필요한 셋(47·48·50)이 쓰는 경로. **토큰 주체가 곧 대상**이라
  /// 식별자를 받지 않는다 — 명세의 "본인만 접근하면 `/users/me/...`" 규칙이다.
  static const _mePath = '/api/v1/users/me/profile-image';

  /// 조회(49)만 다르다. **타인의 사진도 볼 수 있어야 해서** 식별자를 받는다.
  static String _userPath(String userId) =>
      '/api/v1/users/$userId/profile-image';

  static Map<String, String> _bearer(String token) => {
    'Authorization': 'Bearer $token',
  };

  /// 저장소에서 `userId`와 토큰을 꺼내 [call]을 부른다. 401이면 **한 번만** 갱신하고
  /// 다시 부른다.
  ///
  /// 올리는 세 단계를 통째로 감싸지 않고 서버 호출마다 따로 감싼다. 통째로 감싸면
  /// 3단계의 401 때문에 **S3에 한 번 더 올리게 된다.**
  Future<T> _authed<T>(
    Future<T> Function(String userId, String accessToken) call,
  ) async {
    final stored = await _store.read();
    final userId = stored.userId;
    final accessToken = stored.accessToken;
    if (userId == null || accessToken == null) {
      throw const ProfileImageException(ProfileImageFailure.sessionExpired);
    }

    try {
      return await call(userId, accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw ProfileImageException(_failureOf(error));
      }
      try {
        return await call(userId, await _refreshed(stored.refreshToken));
      } on DioException catch (retried) {
        throw ProfileImageException(_failureOf(retried));
      }
    }
  }

  /// 새 access 토큰을 받아 저장하고 돌려준다. `HttpOnboardingRepository`와 같다.
  Future<String> _refreshed(String? refreshToken) async {
    if (refreshToken == null) {
      throw const ProfileImageException(ProfileImageFailure.sessionExpired);
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
      throw ProfileImageException(
        error.failure == AuthFailure.network
            ? ProfileImageFailure.network
            : ProfileImageFailure.sessionExpired,
      );
    }
  }

  /// 상태 코드를 1차 근거로 삼는다. `HttpOnboardingRepository`와 같은 규칙이다.
  ProfileImageFailure _failureOf(DioException error) {
    if (error.type != DioExceptionType.badResponse) {
      return ProfileImageFailure.network;
    }

    final status = error.response?.statusCode ?? 0;
    // ⚠️ 없는 사용자를 물어도 500이 온다 — 서버가 `ProfileNotFoundException`을
    // 매핑하지 않아서다. 그래서 500을 404와 구분할 수 없다.
    if (status >= 500) return ProfileImageFailure.server;
    if (status == 401) return ProfileImageFailure.sessionExpired;
    return ProfileImageFailure.unknown;
  }
}
