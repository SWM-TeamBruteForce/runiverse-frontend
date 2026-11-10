import 'dart:math' as math;

/// 하늘 상태. 홈 위 줄에 `맑음 18°`의 앞부분으로 쓴다.
///
/// Open-Meteo가 주는 WMO 4677 코드를 일곱으로 줄인다. 이슬비·소나기·어는 비는
/// 전부 `비`다 — 한 줄짜리 자리에서 가를 이유가 없다.
enum WeatherSky {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  rain,
  snow,
  thunder;

  /// WMO 코드를 옮긴다. **목록에 없는 코드는 `null`이다** — 그때 화면은 기온만
  /// 그린다. 범위로 받으면 Open-Meteo가 쓰지 않는 번호까지 엉뚱한 하늘이 된다.
  static WeatherSky? fromWmo(int code) => switch (code) {
    0 => clear,
    1 || 2 => partlyCloudy,
    3 => cloudy,
    45 || 48 => fog,
    51 || 53 || 55 || 56 || 57 => rain,
    61 || 63 || 65 || 66 || 67 => rain,
    80 || 81 || 82 => rain,
    71 || 73 || 75 || 77 || 85 || 86 => snow,
    95 || 96 || 99 => thunder,
    _ => null,
  };
}

/// 지금 날씨.
class Weather {
  const Weather({required this.sky, required this.temperature});

  /// 모르는 코드면 `null`. 기온만 보여 준다.
  final WeatherSky? sky;

  /// 섭씨. 반올림한 정수로 든다 — 화면이 소수를 쓰지 않는다.
  final int temperature;
}

/// 밖으로 보내는 좌표의 정밀도를 줄인다. 기본은 소수 둘째 자리 — 약 1km다.
///
/// 날씨 격자가 그보다 성겨서 받는 날씨는 같고, **외부 서비스에 남는 위치만
/// 덜 정밀해진다.** 동네 이름은 셋째 자리(약 100m)를 쓴다 — 둘째 자리로는
/// 서울시청(중구)이 종로구로 나왔다(2026-11-10 에뮬레이터).
/// Open-Meteo 날씨 지도에서 이 자리를 가운데로 연다. 날씨 출처 링크다.
///
/// `#확대/위도/경도`. 9는 시·군이 한 화면에 드는 크기다. 좌표는 날씨를 받을
/// 때와 같은 정밀도로 줄인다 — 브라우저가 Open-Meteo에 보내는 값이 된다.
String openMeteoMapUrl({required double latitude, required double longitude}) =>
    'https://maps.open-meteo.com/'
    '#9/${coarseCoordinate(latitude)}/${coarseCoordinate(longitude)}';

double coarseCoordinate(double degrees, {int decimals = 2}) {
  final scale = math.pow(10, decimals);
  return (degrees * scale).round() / scale;
}
