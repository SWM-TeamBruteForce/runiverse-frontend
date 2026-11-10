import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/location_ask_store.dart';
import 'package:runiverse/features/home/data/geocoding_place_repository.dart';
import 'package:runiverse/features/home/data/open_meteo_weather_repository.dart';
import 'package:runiverse/features/home/domain/place_repository.dart';
import 'package:runiverse/features/home/domain/weather.dart';
import 'package:runiverse/features/home/domain/weather_repository.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 날씨를 누가 줄 것인가. 지금은 Open-Meteo다.
///
/// ⚠️ `presentation`에 있으면서 `data`를 import한다 — `locationRepositoryProvider`와
/// 같은 예외다. 구현체를 고르는 자리가 여기다.
final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => OpenMeteoWeatherRepository(),
);

/// 동네 이름을 누가 줄 것인가. 지금은 기기 지오코더(구글·Apple)다.
final placeRepositoryProvider = Provider<PlaceRepository>(
  (ref) => GeocodingPlaceRepository(),
);

/// 홈에서 위치를 물었는지 기억하는 곳.
final locationAskStoreProvider = Provider<LocationAskStore>(
  (ref) => SecureLocationAskStore(),
);

/// 지금 몇 시인가. 테스트가 30분을 넘기려고 갈아 끼운다.
final weatherClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 홈 위 줄 왼쪽 자리.
///
/// ## 받는 중·실패를 따로 그리지 않는다
///
/// 셋 다 **빈 자리**([HomeWeatherHidden])다. 날씨는 있으면 좋은 정도라 도는
/// 표시나 오류 문구로 위 줄을 채울 이유가 없다 — 비어 있다가 받으면 채워진다.
sealed class HomeWeatherState {
  const HomeWeatherState();
}

/// 비워 둔다. 받는 중이거나, 못 받았거나, 권한이 없고 이미 물었다.
final class HomeWeatherHidden extends HomeWeatherState {
  const HomeWeatherHidden();
}

/// `위치 켜고 날씨 보기`. 권한이 없고 홈에서 아직 안 물었다.
final class HomeWeatherAsk extends HomeWeatherState {
  const HomeWeatherAsk();
}

/// `서울 중구 · 맑음 18°`. 동네 이름을 모르면 `맑음 18°`.
final class HomeWeatherShown extends HomeWeatherState {
  const HomeWeatherShown(
    this.weather, {
    required this.latitude,
    required this.longitude,
    this.place,
  });

  final Weather weather;

  /// 동네 이름. 해외·지오코더 없음·실패면 `null`.
  final String? place;

  /// 날씨를 받은 자리. 출처 시트가 날씨 지도를 이 자리로 연다.
  final double latitude;
  final double longitude;
}

/// 홈 날씨.
///
/// **셸에 붙인다** — `HomePage`가 아니다. 홈 탭은 다른 탭에 다녀와도 다시
/// 세워지지 않아서, 화면에 붙이면 처음 한 번만 받는다. 셸이 세워질 때·앱이
/// 돌아올 때·홈 탭을 누를 때 [refresh]를 부른다.
final homeWeatherProvider =
    NotifierProvider<HomeWeatherController, HomeWeatherState>(
      HomeWeatherController.new,
    );

class HomeWeatherController extends Notifier<HomeWeatherState> {
  /// 받은 날씨를 다시 쓰는 시간. Open-Meteo가 현재 날씨를 15분 단위로 바꾼다.
  ///
  /// **위치가 바뀌어도 이 안에서는 다시 받지 않는다.** 몇 km 안에서는 날씨가
  /// 같고, 움직일 때마다 부르면 걷기만 해도 요청이 쌓인다.
  static const _fresh = Duration(minutes: 30);

  /// [state]의 날씨를 받은 시각. 날씨가 없으면 `null`.
  DateTime? _fetchedAt;

  /// 돌고 있는 [refresh]. 겹친 호출은 이것을 기다린다.
  ///
  /// iOS는 권한 창이 떴다 닫히는 것만으로 앱이 `resumed`가 되어, 버튼의 갱신과
  /// 셸의 복귀 갱신이 겹친다.
  Future<void>? _running;

  /// 도는 중에 다시 불렸다. **끝난 뒤 한 번 더 본다** — 날씨를 받는 사이 위치를
  /// 끄고 돌아왔다면, 먼저 시작한 갱신은 그 사실을 모른다.
  var _again = false;

  /// 이 실행에서 버튼을 눌렀다.
  ///
  /// ⚠️ 저장값을 읽는 사이에 눌리면 늦게 끝난 갱신이 버튼을 되살린다. 저장소보다
  /// 먼저 이것을 본다.
  var _askedNow = false;

  /// 동네 이름을 기다리는 한도. 넘으면 이름 없이 날씨만 그린다.
  ///
  /// 지오코더 호출에는 시간 제한이 없다. 응답이 안 오면 날씨까지 막히고, 이
  /// 갱신이 끝나지 않아 다음 갱신도 줄을 선다.
  static const _placeLimit = Duration(seconds: 3);

  @override
  HomeWeatherState build() => const HomeWeatherHidden();

  LocationRepository get _location => ref.read(locationRepositoryProvider);
  LocationAskStore get _askStore => ref.read(locationAskStoreProvider);
  WeatherRepository get _weather => ref.read(weatherRepositoryProvider);
  PlaceRepository get _place => ref.read(placeRepositoryProvider);
  DateTime _now() => ref.read(weatherClockProvider)();

  /// 날씨를 다시 본다. 30분이 안 됐으면 부르지 않는다.
  Future<void> refresh() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _refreshUntilSettled().whenComplete(
      () => _running = null,
    );
  }

  Future<void> _refreshUntilSettled() async {
    do {
      _again = false;
      await _refresh();
    } while (_again);
  }

  Future<void> _refresh() async {
    try {
      final access = await _location.checkAccess();
      if (!access.isGranted) {
        _fetchedAt = null;
        // ⚠️ **`denied`일 때만 묻는다.** 위치 기능이 꺼졌으면(`serviceDisabled`)
        // `ensureAccess`가 묻지도 않고 돌아와 한 번뿐인 기회만 쓰고, iOS의
        // `deniedForever`는 물을 수 없다.
        final askable =
            access == LocationAccess.denied &&
            !_askedNow &&
            !await _askStore.asked();
        // 저장값을 기다리는 사이 눌렸을 수 있다. 한 번 더 본다.
        state = askable && !_askedNow
            ? const HomeWeatherAsk()
            : const HomeWeatherHidden();
        return;
      }

      final fetchedAt = _fetchedAt;
      if (state is HomeWeatherShown &&
          fetchedAt != null &&
          _now().difference(fetchedAt) < _fresh) {
        return;
      }

      final position = await _location.approximatePosition();
      if (position == null) {
        _hide();
        return;
      }
      // 동시에 보낸다. 지오코더는 앱을 켜고 첫 호출만 1.6초, 그 뒤로는
      // 0.5초 안쪽이라(에뮬레이터) 날씨(약 0.8초)를 거의 늦추지 않는다.
      final name = _nameOf(position.latitude, position.longitude);
      final weather = await _weather.current(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      state = HomeWeatherShown(
        weather,
        latitude: position.latitude,
        longitude: position.longitude,
        place: await name,
      );
      _fetchedAt = _now();
    } on Object catch (error) {
      // 저장값을 못 읽은 경우도 여기로 온다 — **물었다고 본다.** 못 읽었다고
      // 버튼을 띄우면 이미 물은 기기에서 두 번째 거절을 받을 수 있다.
      debugPrint('[weather] 날씨 자리를 비운다 · $error');
      _hide();
    }
  }

  /// 동네 이름. **실패해도 날씨는 보인다** — 이름은 덧붙이는 정보다.
  Future<String?> _nameOf(double latitude, double longitude) async {
    try {
      return await _place
          .nameOf(latitude: latitude, longitude: longitude)
          .timeout(_placeLimit);
    } on Object catch (error) {
      debugPrint('[weather] 동네 이름 없이 그린다 · $error');
      return null;
    }
  }

  /// 오래된 날씨를 남겨 두지 않는다. 다른 곳의 날씨일 수 있다.
  void _hide() {
    _fetchedAt = null;
    state = const HomeWeatherHidden();
  }

  /// `위치 켜고 날씨 보기`를 눌렀다.
  ///
  /// ⚠️ **물었다는 것을 먼저 남긴다.** 권한 창이 떠 있는 동안 앱이 꺼지면 남길
  /// 기회가 없다. 남기지 못하면 묻지 않는다 — 기기당 한 번을 지킬 수 없다.
  Future<void> ask() async {
    if (state is! HomeWeatherAsk) return;
    _askedNow = true;
    // 바로 감춘다. 권한 창이 뜨기 전에 한 번 더 눌리지 않게.
    state = const HomeWeatherHidden();

    final LocationAccess access;
    try {
      await _askStore.markAsked();
      access = await _location.ensureAccess();
    } on Object catch (error) {
      debugPrint('[weather] 위치 권한을 묻지 못했다 · $error');
      return;
    }
    if (!access.isGranted) return;

    // 권한 창이 닫히며 시작된 복귀 갱신은 **허용 전에** 상태를 읽었을 수 있다.
    // 도는 중이면 [refresh]가 끝난 뒤 한 번 더 보게 한다.
    await refresh();
  }
}
