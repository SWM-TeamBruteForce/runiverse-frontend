/// 좌표 근처 주소 하나의 행정구역 칸. 기기 지오코더가 준 것을 옮겨 담는다.
///
/// 칸이 **들쭉날쭉하게 빈다.** 같은 좌표에 근처 주소가 여럿 오는데, 강남역은
/// 첫 결과에 구가 없고 수원은 첫 결과에 도가 없었다(2026-11-10 에뮬레이터).
class PlaceParts {
  const PlaceParts({this.countryCode, this.province, this.city, this.district});

  /// `KR`. 한국이 아니면 이름을 쓰지 않는다 — 아래 줄이는 규칙이 한국 것이다.
  final String? countryCode;

  /// 시·도. `서울특별시`, `경기도`.
  final String? province;

  /// 시·군. `수원시`, `양평군`. 특별시·광역시는 비어 온다.
  final String? city;

  /// 구. `중구`, `영통구`.
  final String? district;
}

/// 홈 위 줄의 동네 이름. `서울 중구`, `수원시 영통구`, `경기 양평군`.
///
/// 근처 주소 중 **구가 채워진 것을 먼저** 고르고, 없으면 시·군이 채워진 것을
/// 쓴다. 못 만들면 `null` — 화면은 날씨만 그린다.
///
/// ⚠️ 경계 근처에서는 결과끼리 다르다. 강남역 좌표는 첫 결과가 강남구
/// `역삼동`, 나머지가 `서초구`였다. 구가 있는 쪽을 고르므로 `서울 서초구`다.
String? placeLabel(List<PlaceParts> candidates) {
  final korean = candidates.where((p) => p.countryCode == 'KR').toList();

  for (final place in korean) {
    final district = _filled(place.district);
    if (district == null) continue;
    final metro = _metros[_filled(place.province)];
    // 특별시·광역시는 `서울 중구`, 도 안의 시는 `수원시 영통구`.
    final head = metro ?? _filled(place.city);
    if (head != null) return '$head $district';
  }

  for (final place in korean) {
    final province = _filled(place.province);
    final metro = _metros[province];
    // 구가 없는 특별자치시(세종)는 시 이름만 쓴다.
    if (metro != null) return metro;
    final city = _filled(place.city);
    if (city != null && province != null) {
      return '${_provinces[province] ?? province} $city';
    }
  }
  return null;
}

/// 빈 칸이 `null` 대신 `''`나 공백으로 올 수 있다. 그대로 쓰면 `수원시 `처럼
/// 이름이 잘리고, 뒤에 있는 멀쩡한 후보를 건너뛴다.
String? _filled(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// 특별시·광역시·특별자치시. 시안이 `서울 강남구`로 줄여 쓴다.
const _metros = {
  '서울특별시': '서울',
  '부산광역시': '부산',
  '대구광역시': '대구',
  '인천광역시': '인천',
  '광주광역시': '광주',
  '대전광역시': '대전',
  '울산광역시': '울산',
  '세종특별자치시': '세종',
};

/// 도. 줄임은 흔히 쓰는 두 글자다. 목록에 없으면 받은 이름 그대로 쓴다.
const _provinces = {
  '경기도': '경기',
  '강원도': '강원',
  '강원특별자치도': '강원',
  '충청북도': '충북',
  '충청남도': '충남',
  '전라북도': '전북',
  '전북특별자치도': '전북',
  '전라남도': '전남',
  '경상북도': '경북',
  '경상남도': '경남',
  '제주특별자치도': '제주',
};
