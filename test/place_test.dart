import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/home/domain/place.dart';

/// 홈 위 줄의 동네 이름 — 들쭉날쭉한 지오코더 결과에서 무엇을 고르는가.
///
/// 입력은 2026-11-10 에뮬레이터에서 실제로 받은 결과를 줄인 것이다.
void main() {
  PlaceParts kr({String? province, String? city, String? district}) =>
      PlaceParts(
        countryCode: 'KR',
        province: province,
        city: city,
        district: district,
      );

  test('특별시·광역시의 구는 줄인 시 이름을 붙인다', () {
    expect(placeLabel([kr(province: '서울특별시', district: '중구')]), '서울 중구');
    expect(placeLabel([kr(province: '부산광역시', district: '해운대구')]), '부산 해운대구');
  });

  test('⚠️ 첫 결과에 구가 없으면 구가 있는 결과를 고른다 — 강남역', () {
    expect(
      placeLabel([
        kr(province: '서울특별시'), // 역삼동만 왔다
        kr(province: '서울특별시', district: '서초구'),
      ]),
      '서울 서초구',
    );
  });

  test('⚠️ 도 안의 시에 있는 구는 시 이름을 붙인다 — 수원', () {
    expect(
      placeLabel([
        kr(city: '수원시'), // 도가 비어 왔다
        kr(province: '경기도', city: '수원시', district: '영통구'),
      ]),
      '수원시 영통구',
    );
  });

  test('⚠️ 빈 문자열·공백 칸은 없는 칸으로 보고 다음 후보로 간다', () {
    expect(
      placeLabel([
        kr(province: '경기도', city: '수원시', district: ''),
        kr(province: '경기도', city: '수원시', district: ' 영통구 '),
      ]),
      '수원시 영통구',
    );
    expect(placeLabel([kr(province: '  ', city: '양평군')]), isNull);
  });

  test('구가 없는 시·군은 줄인 도 이름을 붙인다', () {
    expect(placeLabel([kr(province: '경기도', city: '양평군')]), '경기 양평군');
  });

  test('구가 없는 특별자치시는 시 이름만 쓴다', () {
    expect(placeLabel([kr(province: '세종특별자치시')]), '세종');
  });

  test('줄임 목록에 없는 도는 받은 이름 그대로 쓴다', () {
    expect(placeLabel([kr(province: '새도', city: '새시')]), '새도 새시');
  });

  test('한국이 아니거나 칸이 비면 이름을 만들지 않는다', () {
    expect(
      placeLabel([
        const PlaceParts(countryCode: 'JP', province: '東京都', district: '港区'),
      ]),
      isNull,
    );
    expect(placeLabel([kr(city: '수원시')]), isNull, reason: '도도 구도 없다');
    expect(placeLabel([]), isNull);
  });
}
