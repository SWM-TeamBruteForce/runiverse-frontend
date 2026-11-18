import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/home/data/open_meteo_weather_repository.dart';
import 'package:runiverse/features/home/domain/weather.dart';

/// Open-Meteo 현재 날씨 — **무엇을 보내고 무엇을 읽는가.**
///
/// ⚠️ 보내는 좌표가 약 1km로 줄어 있어야 한다. 외부 서비스에 정밀한 위치를
/// 남기지 않는다.
void main() {
  (OpenMeteoWeatherRepository, _RecordingAdapter) repositoryAnswering(
    Object? body,
  ) {
    final adapter = _RecordingAdapter(body);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.open-meteo.com'))
      ..httpClientAdapter = adapter;
    return (OpenMeteoWeatherRepository(dio: dio), adapter);
  }

  // 2026-11-10 실제 응답에서 값만 바꿨다.
  const answer = {
    'latitude': 37.55,
    'longitude': 127.0,
    'current': {
      'time': '2026-11-10T02:00',
      'interval': 900,
      'temperature_2m': 17.6,
      'weather_code': 3,
    },
  };

  for (final successfulAttempt in [0, 1, 2, 3]) {
    test('우회 순서와 DNS 복귀: 성공 위치 $successfulAttempt', () async {
      final calls = <String?>[];
      final repository = OpenMeteoWeatherRepository(
        createDio: (address) =>
            Dio(BaseOptions(baseUrl: 'https://api.open-meteo.com'))
              ..interceptors.add(
                InterceptorsWrapper(
                  onRequest: (options, handler) {
                    calls.add(address);
                    expect(options.uri.host, 'api.open-meteo.com');
                    expect(options.queryParameters['latitude'], 37.57);
                    if (calls.length - 1 < successfulAttempt) {
                      handler.reject(
                        DioException(
                          requestOptions: options,
                          type: DioExceptionType.connectionTimeout,
                        ),
                      );
                    } else {
                      handler.resolve(
                        Response(requestOptions: options, data: answer),
                      );
                    }
                  },
                ),
              ),
      );
      final request = repository.current(
        latitude: 37.56789,
        longitude: 126.97123,
      );
      if (successfulAttempt == 3) {
        await expectLater(request, throwsA(isA<DioException>()));
      } else {
        expect((await request).temperature, 18);
      }
      expect(
        calls,
        [
          '167.114.211.86',
          '157.90.83.168',
          null,
        ].take(successfulAttempt == 3 ? 3 : successfulAttempt + 1).toList(),
      );
    });
  }

  for (final (label, error, retried) in [
    (
      '응답을 받던 중 끊김은 다음 경로로',
      const HttpException('Connection closed while receiving data'),
      true,
    ),
    (
      'TLS 협상 중 끊김은 다음 경로로',
      const HandshakeException('Connection terminated during handshake'),
      true,
    ),
    (
      '인증서 검증 실패는 멈춘다',
      const HandshakeException(
        'Handshake error in client',
        OSError('CERTIFICATE_VERIFY_FAILED: unable to get local issuer'),
      ),
      false,
    ),
  ]) {
    test(label, () async {
      var calls = 0;
      final repository = OpenMeteoWeatherRepository(
        createDio: (_) => Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                calls++;
                handler.reject(
                  DioException(requestOptions: options, error: error),
                );
              },
            ),
          ),
      );
      await expectLater(
        repository.current(latitude: 37.5, longitude: 127),
        throwsA(isA<DioException>()),
      );
      expect(calls, retried ? 3 : 1);
    });
  }

  for (final status in [400, 429, 503]) {
    test('HTTP $status 재시도 정책', () async {
      var calls = 0;
      final repository = OpenMeteoWeatherRepository(
        createDio: (_) => Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                calls++;
                handler.reject(
                  DioException.badResponse(
                    statusCode: status,
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: status,
                    ),
                  ),
                );
              },
            ),
          ),
      );
      await expectLater(
        repository.current(latitude: 37.5, longitude: 127),
        throwsA(isA<DioException>()),
      );
      expect(calls, status == 503 ? 3 : 1);
    });
  }

  test('⚠️ 줄인 좌표와 필요한 두 값만 묻는다', () async {
    final (repository, adapter) = repositoryAnswering(answer);

    await repository.current(latitude: 37.56789, longitude: 126.97123);

    final sent = adapter.sent!;
    expect(sent.path, '/v1/forecast');
    expect(sent.queryParameters['latitude'], 37.57);
    expect(sent.queryParameters['longitude'], 126.97);
    expect(sent.queryParameters['current'], 'temperature_2m,weather_code');
  });

  test('기온은 반올림하고 코드는 하늘로 읽는다', () async {
    final (repository, _) = repositoryAnswering(answer);

    final weather = await repository.current(latitude: 37.5, longitude: 127);

    expect(weather.temperature, 18);
    expect(weather.sky, WeatherSky.cloudy);
  });

  test('값이 비면 던진다 — 자리를 비우게 한다', () async {
    final (repository, _) = repositoryAnswering({
      'current': {'temperature_2m': null, 'weather_code': 0},
    });

    expect(
      repository.current(latitude: 37.5, longitude: 127),
      throwsFormatException,
    );
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.body);

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
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
