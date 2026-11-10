import 'package:dio/dio.dart';
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
  OpenMeteoWeatherRepository({Dio? dio}) : _dio = dio ?? Dio(_options);

  /// `dio`의 기본값은 무제한 대기다. 날씨 하나 때문에 오래 붙잡지 않는다.
  static BaseOptions get _options => BaseOptions(
    baseUrl: 'https://api.open-meteo.com',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  );

  final Dio _dio;

  @override
  Future<Weather> current({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/forecast',
      queryParameters: {
        // 정밀한 좌표를 외부에 남기지 않는다.
        'latitude': coarseCoordinate(latitude),
        'longitude': coarseCoordinate(longitude),
        // 필요한 두 값만 받는다. 응답이 400바이트 안쪽이다.
        'current': 'temperature_2m,weather_code',
      },
    );

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
