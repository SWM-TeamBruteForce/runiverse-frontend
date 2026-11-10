import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/home/domain/weather.dart';

/// 홈 날씨 — WMO 코드를 무엇으로 읽고, 좌표를 얼마나 줄여 보내는가.
void main() {
  group('WMO 코드', () {
    test('Open-Meteo가 쓰는 코드를 일곱 하늘로 줄인다', () {
      const expected = {
        WeatherSky.clear: [0],
        WeatherSky.partlyCloudy: [1, 2],
        WeatherSky.cloudy: [3],
        WeatherSky.fog: [45, 48],
        WeatherSky.rain: [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82],
        WeatherSky.snow: [71, 73, 75, 77, 85, 86],
        WeatherSky.thunder: [95, 96, 99],
      };

      for (final MapEntry(key: sky, value: codes) in expected.entries) {
        for (final code in codes) {
          expect(WeatherSky.fromWmo(code), sky, reason: '$code');
        }
      }
    });

    test('⚠️ 목록에 없는 코드는 모른다고 한다 — 범위 사이 번호도', () {
      // 4는 맑음(0~3)과 안개(45) 사이, 60은 이슬비와 비 사이다.
      for (final code in [4, 44, 50, 60, 70, 90, 100, -1]) {
        expect(WeatherSky.fromWmo(code), isNull, reason: '$code');
      }
    });
  });

  group('날씨 지도 링크', () {
    test('⚠️ 이 자리를 가운데로 열고, 좌표는 날씨처럼 줄인다', () {
      expect(
        openMeteoMapUrl(latitude: 37.5665, longitude: 126.978),
        'https://maps.open-meteo.com/#9/37.57/126.98',
      );
    });
  });

  group('보내는 좌표', () {
    test('소수 둘째 자리로 반올림한다', () {
      expect(coarseCoordinate(37.56789), 37.57);
      expect(coarseCoordinate(126.97123), 126.97);
      expect(coarseCoordinate(-33.8689), -33.87);
    });

    test('동네 이름에는 셋째 자리까지 보낸다', () {
      // 둘째 자리(37.57, 126.98)로는 서울시청이 종로구로 나왔다.
      expect(coarseCoordinate(37.56654, decimals: 3), 37.567);
      expect(coarseCoordinate(126.97796, decimals: 3), 126.978);
    });
  });
}
