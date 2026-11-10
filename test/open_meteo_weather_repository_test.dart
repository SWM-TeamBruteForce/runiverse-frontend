import 'dart:convert';
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
