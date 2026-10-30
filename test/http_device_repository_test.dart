import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/notification/data/http_device_repository.dart';
import 'package:runiverse/features/notification/domain/device_repository.dart';

/// 푸시 기기 등록 REST. 명세 2-1.
void main() {
  DioException badResponse(int status, {Object? body}) => DioException(
    requestOptions: RequestOptions(path: '/api/v1/users/me/devices'),
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: RequestOptions(path: '/api/v1/users/me/devices'),
      statusCode: status,
      data: body,
    ),
  );

  DeviceFailure failureOf(DioException error) =>
      HttpDeviceRepository.exceptionOf(error).failure;

  group('실패를 가른다', () {
    test('응답이 없거나 5xx면 망 문제다', () {
      final timeout = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );

      expect(failureOf(timeout), DeviceFailure.network);
      expect(failureOf(badResponse(503)), DeviceFailure.network);
    });

    test('⚠️ 403 APP_UPDATE_REQUIRED만 업데이트다', () {
      expect(
        failureOf(badResponse(403, body: {'code': 'APP_UPDATE_REQUIRED'})),
        DeviceFailure.updateRequired,
      );
      // 권한 없는 리소스도 403이다.
      expect(
        failureOf(badResponse(403, body: {'code': 'FORBIDDEN'})),
        DeviceFailure.unknown,
      );
    });

    test('400은 다시 보내도 같은 답이다', () {
      // 버전을 못 읽어 헤더가 빠지면 서버가 400으로 막는다.
      expect(
        failureOf(badResponse(400, body: {'code': 'INVALID_REQUEST'})),
        DeviceFailure.unknown,
      );
    });
  });

  test('본문에는 기기 식별자와 토큰만 싣는다', () async {
    // 플랫폼·앱 버전은 서버가 헤더에서 읽는다.
    final sent = <RequestOptions>[];
    final dio = Dio()..httpClientAdapter = _RecordingAdapter(sent);
    final store = InMemoryTokenStore();
    await store.saveTokens(accessToken: 'a', refreshToken: 'r');
    final repo = HttpDeviceRepository(
      dio,
      store,
      TokenRefresher(FakeAuthRepository(), store),
    );

    await repo.register(deviceId: 'device-1', pushToken: 'fcm-1');

    expect(sent.single.method, 'POST');
    expect(sent.single.path, '/api/v1/users/me/devices');
    expect(sent.single.headers['Authorization'], 'Bearer a');
    expect(jsonDecode(jsonEncode(sent.single.data)), {
      'deviceId': 'device-1',
      'pushToken': 'fcm-1',
    });
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.sent);

  final List<RequestOptions> sent;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}
