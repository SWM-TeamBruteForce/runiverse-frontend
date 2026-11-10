import 'package:runiverse/features/home/domain/weather.dart';

/// 지금 날씨를 주는 곳.
abstract interface class WeatherRepository {
  /// [latitude]·[longitude]의 지금 날씨. 실패하면 던진다 — 부르는 쪽이 자리를 비운다.
  Future<Weather> current({
    required double latitude,
    required double longitude,
  });
}
