import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/dio_client.dart';
import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/core/version/app_version_headers.dart';
import 'package:runiverse/core/version/installed_app_version.dart';

/// 앱 버전 헤더와 403 판정.
///
/// ## ⚠️ 이 헤더가 차단의 스위치다
///
/// 서버는 **헤더가 없으면 거절하지 않고 그대로 처리한다**(공통 규칙). 지금껏
/// 구버전 앱이 멀쩡히 돈 이유가 그것이다. 헤더를 싣는 순간부터 최소 버전에
/// 못 미치는 앱은 `/app/version`을 뺀 모든 경로에서 403을 받는다.
void main() {
  setUp(InstalledAppVersion.resetForTest);
  tearDown(InstalledAppVersion.resetForTest);

  group('헤더 만들기', () {
    test('버전과 플랫폼을 함께 싣는다', () {
      InstalledAppVersion.setForTest(const AppVersion(1, 2, 3));

      final headers = AppVersionHeaders.current;

      expect(headers[AppVersionHeaders.versionKey], '1.2.3');
      // 서버가 받는 값은 `IOS`/`ANDROID` 둘뿐이다.
      expect(headers[AppVersionHeaders.platformKey], anyOf('IOS', 'ANDROID'));
    });

    test('⚠️ 버전을 못 읽었으면 아예 싣지 않는다', () {
      // 지어낸 값을 실으면 **통과했을 요청이 403으로 막힌다.** 서버는 헤더가
      // 없으면 그냥 통과시키므로, 모르면 비우는 쪽이 안전하다.
      InstalledAppVersion.setForTest(null);

      expect(AppVersionHeaders.current, isEmpty);
    });

    test('빌드 번호는 빠진다', () {
      InstalledAppVersion.setForTest(AppVersion.parse('1.0.0+7'));

      expect(AppVersionHeaders.current[AppVersionHeaders.versionKey], '1.0.0');
    });
  });

  group('403 판정', () {
    test('APP_UPDATE_REQUIRED면 참이다', () {
      expect(isUpdateRequired(403, {'code': 'APP_UPDATE_REQUIRED'}), isTrue);
    });

    test('⚠️ 다른 403은 아니다 — 권한 없는 리소스도 403이다', () {
      // 전부 업데이트로 보면 멀쩡한 앱이 선다. 작업 가이드가 못 박은 지점이다.
      expect(isUpdateRequired(403, {'code': 'FORBIDDEN'}), isFalse);
      expect(isUpdateRequired(403, null), isFalse);
      expect(isUpdateRequired(403, 'APP_UPDATE_REQUIRED'), isFalse);
    });

    test('⚠️ 다른 상태 코드는 아니다', () {
      // 401·500 본문에 같은 코드가 섞여 와도 403이 아니면 아니다.
      expect(isUpdateRequired(401, {'code': 'APP_UPDATE_REQUIRED'}), isFalse);
      expect(isUpdateRequired(null, {'code': 'APP_UPDATE_REQUIRED'}), isFalse);
    });
  });

  group('dio 인터셉터', () {
    /// 인터셉터만 떼어 단 dio. `createDio()`는 서버 주소가 없으면 멈춘다.
    (Dio, _RecordingAdapter) dioAnswering(
      int status,
      Object? body, {
      required void Function() onUpdateRequired,
    }) {
      final adapter = _RecordingAdapter(status, body);
      final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'))
        ..httpClientAdapter = adapter
        ..interceptors.add(updateRequiredInterceptor(onUpdateRequired));
      return (dio, adapter);
    }

    test('⚠️ 403 APP_UPDATE_REQUIRED를 알린다', () async {
      var told = 0;
      final (dio, _) = dioAnswering(403, const {
        'code': 'APP_UPDATE_REQUIRED',
      }, onUpdateRequired: () => told++);

      await expectLater(
        dio.get<void>('/anything'),
        throwsA(isA<DioException>()),
      );

      expect(told, 1);
    });

    test('⚠️ 다른 403은 알리지 않는다', () async {
      var told = 0;
      final (dio, _) = dioAnswering(403, const {
        'code': 'FORBIDDEN',
      }, onUpdateRequired: () => told++);

      await expectLater(
        dio.get<void>('/anything'),
        throwsA(isA<DioException>()),
      );

      expect(told, 0);
    });

    test('⚠️ 오류를 삼키지 않는다', () async {
      // 알리기만 하고 흘려보내야 한다. 여기서 삼키면 부르던 쪽이 영영 답을
      // 못 받고 화면이 로딩에 멈춘다.
      final (dio, _) = dioAnswering(403, const {
        'code': 'APP_UPDATE_REQUIRED',
      }, onUpdateRequired: () {});

      await expectLater(
        dio.get<void>('/anything'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });
  });

  /// 헤더를 **세 곳 모두** 싣는가.
  ///
  /// REST·SSE·WebSocket 중 하나라도 빠지면 그 경로만 검사를 안 받아
  /// **구버전 앱이 반쯤 도는** 상태가 된다. 셋 다 플랫폼이나 서버 주소를
  /// 요구해서 테스트에서 실제로 열 수 없으므로 **소스를 읽어 확인한다**
  /// (`theme_generation_test`와 같은 방식).
  group('세 곳에 다 싣는다', () {
    const places = {
      'REST': 'lib/core/network/dio_client.dart',
      'SSE': 'lib/features/matching/data/sse_match_stream.dart',
      'WebSocket': 'lib/core/network/ws_client.dart',
    };

    for (final place in places.entries) {
      test('⚠️ ${place.key}', () {
        final source = File(place.value).readAsStringSync();

        expect(
          source.contains('AppVersionHeaders.current'),
          isTrue,
          reason:
              '${place.value}가 앱 버전 헤더를 싣지 않는다. '
              '한 곳만 빠져도 그 경로는 구버전 검사를 받지 않는다.',
        );
      });
    }

    test('⚠️ S3 업로드에는 싣지 않는다', () {
      // 우리 서버가 아니다. 서명된 URL에 모르는 헤더를 더하면 서명이 어긋난다.
      final source = File(
        'lib/features/profile/data/http_profile_image_repository.dart',
      ).readAsStringSync();

      expect(source.contains('AppVersionHeaders'), isFalse);
    });
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.status, this.body);

  final int status;
  final Object? body;

  RequestOptions? sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent = options;
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
