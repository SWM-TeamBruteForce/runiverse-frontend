import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/profile/data/http_profile_image_repository.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_kind.dart';

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

  Future<HttpProfileImageRepository> repository({Dio? uploadDio}) async {
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
      TokenRefresher(FakeAuthRepository(latency: Duration.zero), store),
      uploadDio: uploadDio ?? (Dio()..httpClientAdapter = s3),
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

  /// 배경 이미지 — **같은 길, 다른 이름** (1.1.1 배경 가이드).
  ///
  /// ## ⚠️ 두 Key는 서로 못 바꾼다
  ///
  /// 프로필 Key로 배경을 등록하면 서버가 `INVALID_BACKGROUND_IMAGE`를 준다.
  /// 경로든 필드든 하나라도 프로필 쪽이 새어 나가면 그 러닝이 아니라 **그
  /// 사용자의 배경이 영영 안 올라간다** — 화면에는 "실패"만 뜬다.
  group('배경 이미지', () {
    Future<HttpProfileImageRepository> background() async {
      // 같은 어댑터·저장소를 세우고 종류만 배경으로 바꾼다.
      await repository();
      return HttpProfileImageRepository(
        Dio(BaseOptions(baseUrl: 'http://test.invalid'))
          ..httpClientAdapter = api,
        store,
        TokenRefresher(FakeAuthRepository(latency: Duration.zero), store),
        uploadDio: Dio()..httpClientAdapter = s3,
        kind: ProfileImageKind.background,
      );
    }

    test('조회는 배경 경로로 나간다', () async {
      final repo = await background();
      api.jsonFor['/api/v1/users/u-1/background-image'] = {
        'backgroundImageUrl': 'https://cdn.test/cover.jpg',
      };

      expect(await repo.fetchUrl(), 'https://cdn.test/cover.jpg');
      expect(api.pathOf('GET'), '/api/v1/users/u-1/background-image');
    });

    test('⚠️ 배경 조회에도 토큰을 붙이지 않는다', () async {
      // 공개 API라도 헤더가 있으면 토큰을 검사한다 — 만료된 것이 붙으면 401이다.
      final repo = await background();
      api.jsonFor['/api/v1/users/u-1/background-image'] = {
        'backgroundImageUrl': null,
      };

      await repo.fetchUrl();

      expect(api.headerOf('GET', 'Authorization'), isNull);
    });

    test('⚠️ 올리기는 배경 경로와 배경 필드로만 나간다', () async {
      final repo = await background();
      api.jsonFor['/api/v1/users/me/background-image/presigned-url'] = {
        'backgroundImageKey': 'backgrounds/u-1/a.png',
        'uploadUrl': 'https://s3.test/put',
      };

      await repo.upload(await tempPng());

      expect(
        api.pathOf('POST'),
        '/api/v1/users/me/background-image/presigned-url',
      );
      expect(api.pathOf('PATCH'), '/api/v1/users/me/background-image');
      expect(api.bodyOf('PATCH'), {
        'backgroundImageKey': 'backgrounds/u-1/a.png',
      });
    });

    test('⚠️ 발급 요청의 크기·형식이 고른 파일과 같다', () async {
      // 서명이 이 두 값으로 만들어진다. 하나라도 다르면 S3가 403을 준다.
      final repo = await background();
      api.jsonFor['/api/v1/users/me/background-image/presigned-url'] = {
        'backgroundImageKey': 'backgrounds/u-1/a.png',
        'uploadUrl': 'https://s3.test/put',
      };

      await repo.upload(await tempPng());

      expect(api.bodyOf('POST'), {'mimeType': 'image/png', 'fileSizeBytes': 4});
      expect(s3.headerOf('PUT', 'Content-Type'), 'image/png');
    });

    test('삭제는 배경 경로로 나간다', () async {
      final repo = await background();
      api.jsonFor['/api/v1/users/me/background-image'] =
          const <String, dynamic>{};

      await repo.remove();

      expect(api.pathOf('DELETE'), '/api/v1/users/me/background-image');
    });
  });

  /// ⚠️ **S3 전용 [Dio]가 영영 기다리지 않는가.**
  ///
  /// `dio`의 기본값은 **무제한 대기**다. 이 [Dio]는 `baseUrl`도 인터셉터도
  /// 일부러 비워서 만드는데(`Authorization`을 얹으면 S3가 403을 준다), 그걸
  /// 비우면서 타임아웃까지 같이 빠졌다. 망이 죽으면 2단계 `PUT`이 끝나지
  /// 않고 **편집 화면의 저장 회전 표시도 멈추지 않는다** — 기기에서 겪었다.
  group('⚠️ 업로드가 영영 기다리지 않는다', () {
    test('기본 설정에 타임아웃 셋이 다 있다', () {
      final options = HttpProfileImageRepository.uploadOptions;

      expect(options.connectTimeout, isNotNull, reason: '붙는 데까지');
      expect(options.sendTimeout, isNotNull, reason: '사진을 올리는 동안');
      expect(options.receiveTimeout, isNotNull, reason: '답을 기다리는 동안');
    });

    test('⚠️ 기본으로 만든 Dio에 그 설정이 실제로 걸린다', () async {
      // 설정 객체만 검사하면 **"값은 맞는데 아무 데도 안 쓰는"** 상태를 못
      // 잡는다 — 생성자에서 `Dio()`로 만들던 것이 정확히 그 상태였다.
      final tokens = InMemoryTokenStore();
      final repo = HttpProfileImageRepository(
        Dio(),
        tokens,
        TokenRefresher(FakeAuthRepository(latency: Duration.zero), tokens),
      );

      expect(repo.uploadDio.options.connectTimeout, isNotNull);
      expect(repo.uploadDio.options.sendTimeout, isNotNull);
      expect(repo.uploadDio.options.receiveTimeout, isNotNull);
    });

    test('⚠️ 보내는 시간만 더 길게 잡는다', () {
      // 사진 본문이 올라가는 구간이다. 나머지와 같은 값으로 묶으면 느린
      // 망에서 **멀쩡한 업로드가 잘린다.**
      final options = HttpProfileImageRepository.uploadOptions;

      expect(options.sendTimeout!, greaterThan(options.receiveTimeout!));
      expect(options.sendTimeout!, greaterThan(options.connectTimeout!));
    });

    test('⚠️ 시간이 다하면 올리기 실패로 나온다', () async {
      // ⚠️ **진짜 소켓을 띄운다.** 타임아웃을 거는 것은 dio가 아니라 그 아래
      // HTTP 어댑터라, 가짜 어댑터를 끼우면 **시간이 영영 안 간다** — 처음에
      // 그렇게 썼다가 테스트가 30초를 통째로 기다렸다.
      //
      // 받아만 주고 한 글자도 돌려주지 않는 서버다. 망이 죽은 것이 아니라
      // **S3가 조용한** 상황을 흉내 낸다.
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => socket.close());
      final held = <Socket>[];
      socket.listen(held.add);
      addTearDown(() {
        for (final s in held) {
          s.destroy();
        }
      });

      final repo = await repository(
        // 진짜 값(60초)을 쓰면 테스트가 그만큼 선다. **길이가 아니라 걸려
        // 있다는 것**을 본다 — 진짜 값은 위 두 테스트가 지킨다.
        uploadDio: Dio(
          BaseOptions(receiveTimeout: const Duration(milliseconds: 100)),
        ),
      );
      api.jsonFor['/api/v1/users/me/profile-image/presigned-url'] = {
        'profileImageKey': 'k-1',
        'uploadUrl': 'http://127.0.0.1:${socket.port}/put',
      };

      await expectLater(
        repo.upload(await tempPng()),
        throwsA(
          isA<ProfileImageException>().having(
            (e) => e.failure,
            'failure',
            ProfileImageFailure.upload,
          ),
        ),
      );
    });
  });
}

/// 나간 요청을 기록하고, 경로별로 정해둔 몸통을 200으로 돌려준다.
class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final jsonFor = <String, Map<String, dynamic>?>{};

  String? pathOf(String method) => _find(method)?.path;

  /// 나간 몸통. **필드 이름이 종류마다 다르므로** 키까지 본다.
  Object? bodyOf(String method) => _find(method)?.data;

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
