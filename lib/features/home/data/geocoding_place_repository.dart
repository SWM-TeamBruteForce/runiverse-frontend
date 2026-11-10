import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:runiverse/features/home/domain/place.dart';
import 'package:runiverse/features/home/domain/place_repository.dart';
import 'package:runiverse/features/home/domain/weather.dart';

/// 기기 지오코더로 동네 이름을 받는다. 키가 필요 없다.
///
/// ## ⚠️ 폰 안에서 끝나지 않는다
///
/// 안드로이드 `Geocoder`는 좌표를 **구글**로, iOS `CLGeocoder`는 **Apple**로
/// 보내 이름을 받는다. 개인정보처리방침에 고지해야 하는 전송이다. 줄인
/// 좌표(소수 셋째 자리, 약 100m)만 보낸다 — 날씨처럼 둘째 자리로 줄이면
/// 경계 근처에서 옆 구가 나온다.
///
/// 구글 서비스가 없는 안드로이드는 지오코더가 없다([Geocoding.isPresent]).
/// 그때는 이름 없이 날씨만 보인다.
class GeocodingPlaceRepository implements PlaceRepository {
  GeocodingPlaceRepository({Geocoding? geocoding})
    : _geocoding = geocoding ?? Geocoding(locale: const Locale('ko', 'KR'));

  final Geocoding _geocoding;

  @override
  Future<String?> nameOf({
    required double latitude,
    required double longitude,
  }) async {
    if (!await _geocoding.isPresent()) return null;

    final marks = await _geocoding.placemarkFromCoordinates(
      coarseCoordinate(latitude, decimals: 3),
      coarseCoordinate(longitude, decimals: 3),
    );
    return placeLabel([
      for (final mark in marks)
        PlaceParts(
          countryCode: mark.isoCountryCode,
          province: mark.administrativeArea,
          city: mark.locality,
          district: mark.subLocality,
        ),
    ]);
  }
}
