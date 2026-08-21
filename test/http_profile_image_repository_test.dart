import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/profile/data/http_profile_image_repository.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 프로필 사진 — **어느 경로로 나가는가.**
///
/// 4차 명세는 넷을 이렇게 나눈다. 인증이 필요한 셋은 `me`, 조회만 `{userId}`다.
///
/// | No | 메서드 | 경로 | 인증 |
/// |---|---|---|---|
/// | 47 | POST | `/users/me/profile-image/presigned-url` | 필요 |
/// | 48 | PATCH | `/users/me/profile-image` | 필요 |
/// | 49 | GET | `/users/{userId}/profile-image` | **없음** |
/// | 50 | DELETE | `/users/me/profile-image` | 필요 |
///
/// 서버를 띄우지 않고 dio 어댑터만 갈아끼워 **실제로 나가는 요청**을 본다.
void main() {
  late _RecordingAdapter api;
  late _RecordingAdapter s3;
  late InMemoryTokenStore store;

  Future<HttpProfileImageRepository> repository() async {
    api = _RecordingAdapter();
    s3 = _RecordingAdapter();
    store = InMemoryTokenStore();
    await store.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    return HttpProfileImageRepository(
      Dio(BaseOptions(baseUrl: 'http://test.invalid'))..httpClientAdapter = api,
      store,
      FakeAuthRepository(latency: Duration.zero),
      uploadDio: Dio()..httpClientAdapter = s3,
    );
  }

  /// 실제 파일을 만든다. 저장소가 경로를 읽어 바이트를 보내기 때문이다.
  Future<PickedImage> tempPng() async {
    final file = File('${Directory.systemTemp.path}/runiverse-test.png');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    return PickedImage.validated(path: file.path, sizeBytes: 4);
  }

  test('49번 조회는 {userId} 경로로 나간다', () async {
    final repo = await repository();
    api.jsonFor['/api/v1/users/u-1/profile-image'] = {
      'profileImageUrl': 'https://cdn.test/u-1.png',
    };

    final url = await repo.fetchUrl();

    expect(url, 'https://cdn.test/u-1.png');
    expect(api.pathOf('GET'), '/api/v1/users/u-1/profile-image');
  });

  test('⚠️ 49번은 인증이 필요 없다 — 토큰을 붙이지 않는다', () async {
    final repo = await repository();
    api.jsonFor['/api/v1/users/u-1/profile-image'] = {'profileImageUrl': null};

    await repo.fetchUrl();

    // 명세의 4종 중 이것만 `권한: NO`다. 토큰을 붙이면 401 재시도 경로가
    // **영영 실행되지 않는 죽은 코드**로 남는다.
    expect(api.headerOf('GET', 'Authorization'), isNull);
  });

  test('47·48번 업로드는 me 경로로 나간다', () async {
    final repo = await repository();
    api.jsonFor['/api/v1/users/me/profile-image/presigned-url'] = {
      'profileImageKey': 'profiles/u-1/a.png',
      'uploadUrl': 'https://s3.test/put',
    };
    api.jsonFor['/api/v1/users/me/profile-image'] = {
      'profileImageKey': 'profiles/u-1/a.png',
    };

    await repo.upload(await tempPng());

    expect(api.pathOf('POST'), '/api/v1/users/me/profile-image/presigned-url');
    expect(api.pathOf('PATCH'), '/api/v1/users/me/profile-image');
    // S3에는 요청한 형식 그대로 보낸다 — 서명에 포함되므로 어긋나면 403이다.
    expect(s3.headerOf('PUT', 'Content-Type'), 'image/png');
  });

  test('50번 삭제는 me 경로로 나간다', () async {
    final repo = await repository();
    api.jsonFor['/api/v1/users/me/profile-image'] = const <String, dynamic>{};

    await repo.remove();

    expect(api.pathOf('DELETE'), '/api/v1/users/me/profile-image');
  });
}

/// 나간 요청을 기록하고, 경로별로 정해둔 몸통을 200으로 돌려준다.
class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final jsonFor = <String, Map<String, dynamic>?>{};

  String? pathOf(String method) => _find(method)?.path;

  Object? headerOf(String method, String name) {
    final headers = _find(method)?.headers;
    if (headers == null) return null;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }

  RequestOptions? _find(String method) {
    for (final request in requests) {
      if (request.method.toUpperCase() == method) return request;
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(jsonFor[options.path] ?? const <String, dynamic>{}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
