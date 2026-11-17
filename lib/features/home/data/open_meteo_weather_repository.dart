import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:runiverse/features/home/domain/weather.dart';
import 'package:runiverse/features/home/domain/weather_repository.dart';

/// Open-Meteo로 지금 날씨를 받는다. 키가 없는 무료 API다.
///
/// 서버도 기록 날씨를 같은 곳에서 받는다. 홈 날씨는 서버 API가 없고 앱이 직접
/// 부른다(백엔드 `api-spec.md` 3절).
///
/// ## ⚠️ 아무것도 붙지 않은 [Dio]로 부른다
///
/// 우리 서버용 `createDio()`는 서버 주소와 토큰을 다룬다. 외부 서비스에 우리
/// 토큰이 실려 나가면 안 된다(`UiWatchPhotoMaker`와 같은 이유).
///
/// ## ⚠️ 화면에 보여 주는 곳 옆에 출처를 둔다
///
/// API 데이터가 CC BY 4.0이라 보여 주는 자리 옆에 링크가 있어야 한다
/// (open-meteo.com/en/licence). 홈은 날씨를 누르면 뜨는 시트가 그 자리다.
class OpenMeteoWeatherRepository implements WeatherRepository {
  OpenMeteoWeatherRepository({
    Dio? dio,
    Dio Function(String? address)? createDio,
  }) : _clients = dio != null
           ? [dio]
           : [
               for (final address in _addresses)
                 (createDio ?? _createDio)(address),
             ];

  // TODO(되돌리기): Open-Meteo 장애가 끝나면 `[null]`로 되돌리고 고정 IP를 지운다.
  // https://github.com/open-meteo/open-meteo/issues/2329
  // 고정 IP는 영구 엔드포인트가 아니다.
  // 두 우회 경로가 실패하면 마지막 null에서 기존 DNS 연결을 사용한다.
  static const _addresses = ['167.114.211.86', '157.90.83.168', null];

  static Dio _createDio(String? address) {
    final dio = Dio(_options);
    if (address != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (_) => 'DIRECT';
          client.connectionFactory = (uri, proxyHost, proxyPort) async {
            // URL/Host/SNI와 인증서 검증은 원래 도메인을 유지한다.
            // 리다이렉트로 다른 호스트에 갈 경우 해당 호스트의 DNS를 쓴다.
            final task = await Socket.startConnect(
              uri.host == 'api.open-meteo.com' ? address : uri.host,
              uri.port,
            );
            Socket? connected;
            var cancelled = false;
            final socket = task.socket.then((socket) async {
              connected = socket;
              if (cancelled) {
                socket.destroy();
                throw const SocketException('Weather connection cancelled');
              }
              if (uri.scheme != 'https') return socket;
              // ⚠️ 알려진 한계: `secure`는 원래 소켓에서 연결을 떼어 가져가서,
              // 협상이 끝나기 전에 취소되면 아래 `destroy`가 닫지 못한다. TCP는
              // 받고 TLS에서 멈추는 서버면 요청 한 번에 연결 하나가 남는다.
              // 밖에서 협상 중인 TLS를 닫을 공개 API가 없고, 날씨는 많아야
              // 30분에 한 번 부르는 데다 임시 우회라 받아들인다.
              final secure = await SecureSocket.secure(socket, host: uri.host);
              connected = secure;
              if (cancelled) secure.destroy();
              return secure;
            });
            return ConnectionTask.fromSocket(socket, () {
              cancelled = true;
              task.cancel();
              connected?.destroy();
            });
          };
          return client;
        },
      );
    }
    return dio;
  }

  /// `dio`의 기본값은 무제한 대기다. 날씨 하나 때문에 오래 붙잡지 않는다.
  static BaseOptions get _options => BaseOptions(
    baseUrl: 'https://api.open-meteo.com',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  );

  final List<Dio> _clients;

  Future<Response<Map<String, dynamic>>> _fetch(
    Map<String, dynamic> query,
  ) async {
    for (var i = 0; i < _clients.length; i++) {
      try {
        return await _clients[i].get<Map<String, dynamic>>(
          '/v1/forecast',
          queryParameters: query,
        );
      } on DioException catch (error) {
        // 요청 오류·호출 한도(429)·취소·잘못된 인증서는 재시도하지 않는다.
        final retryable = switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.connectionError => true,
          DioExceptionType.badResponse =>
            (error.response?.statusCode ?? 0) >= 500,
          DioExceptionType.unknown => switch (error.error) {
            SocketException() => true,
            // TLS 협상 중 상대가 끊은 것은 연결 장애다 — 다음 경로로 간다.
            // 인증서 검증 실패(`CERTIFICATE_VERIFY_FAILED`)는 넘기지 않는다.
            HandshakeException(:final message, :final osError) =>
              !'$message ${osError?.message}'.contains('CERTIFICATE'),
            _ => false,
          },
          _ => false,
        };
        if (!retryable || i == _clients.length - 1) rethrow;
      }
    }
    throw StateError('날씨 요청 경로가 없다');
  }

  @override
  Future<Weather> current({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _fetch({
      // 정밀한 좌표를 외부에 남기지 않는다.
      'latitude': coarseCoordinate(latitude),
      'longitude': coarseCoordinate(longitude),
      // 필요한 두 값만 받는다. 응답이 400바이트 안쪽이다.
      'current': 'temperature_2m,weather_code',
    });

    final current = response.data?['current'];
    if (current is! Map<String, dynamic>) {
      throw const FormatException('Open-Meteo 응답에 current가 없다');
    }
    final temperature = current['temperature_2m'];
    final code = current['weather_code'];
    if (temperature is! num || code is! num) {
      throw FormatException('Open-Meteo 값이 비었다 · $current');
    }

    return Weather(
      sky: WeatherSky.fromWmo(code.toInt()),
      temperature: temperature.round(),
    );
  }
}
