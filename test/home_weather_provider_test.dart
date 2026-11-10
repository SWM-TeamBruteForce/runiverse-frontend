import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/home/domain/place_repository.dart';
import 'package:runiverse/features/home/domain/weather.dart';
import 'package:runiverse/features/home/domain/weather_repository.dart';
import 'package:runiverse/features/home/presentation/home_weather_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 홈 날씨 자리 — **언제 무엇을 보이고, 언제 다시 받는가.**
///
/// 권한은 여기서 묻지 않는다. 묻는 쪽은 `home_permission_provider_test.dart`가 본다.
void main() {
  late FakeLocationRepository location;
  late _FakeWeatherRepository weather;
  late _FakePlaceRepository place;
  late DateTime now;

  ProviderContainer start({LocationAccess access = LocationAccess.granted}) {
    location = FakeLocationRepository(access: access)
      ..position = GeoPoint(
        latitude: 37.5665,
        longitude: 126.978,
        recordedAt: DateTime(2026, 11, 10, 9),
      );
    weather = _FakeWeatherRepository();
    place = _FakePlaceRepository();
    now = DateTime(2026, 11, 10, 9);
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(location),
        weatherRepositoryProvider.overrideWithValue(weather),
        placeRepositoryProvider.overrideWithValue(place),
        weatherClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  HomeWeatherState stateOf(ProviderContainer container) =>
      container.read(homeWeatherProvider);

  group('보이는 것', () {
    test('권한이 있으면 날씨를 받는다', () async {
      final container = start();

      await container.read(homeWeatherProvider.notifier).refresh();

      final state = stateOf(container);
      expect(state, isA<HomeWeatherShown>());
      expect((state as HomeWeatherShown).weather.temperature, 18);
      expect(state.place, '서울 중구');
      expect(location.ensureAccessCount, 0, reason: '날씨는 권한을 묻지 않는다');
    });

    test('⚠️ 동네 이름을 못 받아도 날씨는 보인다', () async {
      final container = start();
      place.fail = true;

      await container.read(homeWeatherProvider.notifier).refresh();

      final state = stateOf(container);
      expect(state, isA<HomeWeatherShown>());
      expect((state as HomeWeatherShown).place, isNull);
    });

    test('권한이 없으면 비워 두고, 묻지도 받지도 않는다', () async {
      for (final access in [
        LocationAccess.denied,
        LocationAccess.deniedForever,
        LocationAccess.serviceDisabled,
      ]) {
        final container = start(access: access);

        await container.read(homeWeatherProvider.notifier).refresh();

        expect(stateOf(container), isA<HomeWeatherHidden>(), reason: '$access');
        expect(location.ensureAccessCount, 0, reason: '$access');
        expect(weather.calls, 0, reason: '$access');
      }
    });

    test('⚠️ 권한을 허용한 뒤 다시 보면 날씨를 받는다', () async {
      // 셸이 홈에서 권한을 물은 뒤 다시 부른다.
      final container = start(access: LocationAccess.denied);
      final controller = container.read(homeWeatherProvider.notifier);
      await controller.refresh();
      location.access = LocationAccess.granted;

      await controller.refresh();

      expect(stateOf(container), isA<HomeWeatherShown>());
    });

    test('위치를 못 구하면 비워 둔다', () async {
      final container = start();
      location.position = null;

      await container.read(homeWeatherProvider.notifier).refresh();

      expect(stateOf(container), isA<HomeWeatherHidden>());
      expect(weather.calls, 0);
    });

    test('날씨를 못 받으면 비워 둔다', () async {
      final container = start();
      weather.fail = true;

      await container.read(homeWeatherProvider.notifier).refresh();

      expect(stateOf(container), isA<HomeWeatherHidden>());
    });
  });

  group('다시 받기', () {
    test('30분 안에는 다시 부르지 않는다', () async {
      final container = start();
      final controller = container.read(homeWeatherProvider.notifier);

      await controller.refresh();
      now = now.add(const Duration(minutes: 29));
      await controller.refresh();

      expect(weather.calls, 1);
    });

    test('30분이 지나면 다시 부른다', () async {
      final container = start();
      final controller = container.read(homeWeatherProvider.notifier);

      await controller.refresh();
      now = now.add(const Duration(minutes: 30));
      await controller.refresh();

      expect(weather.calls, 2);
    });

    test('겹쳐 부르면 한 번만 받는다', () async {
      final container = start();
      final controller = container.read(homeWeatherProvider.notifier);

      await Future.wait([controller.refresh(), controller.refresh()]);

      expect(weather.calls, 1);
    });

    test('⚠️ 다시 받다 실패하면 옛 날씨를 남기지 않는다', () async {
      final container = start();
      final controller = container.read(homeWeatherProvider.notifier);

      await controller.refresh();
      now = now.add(const Duration(hours: 1));
      weather.fail = true;
      await controller.refresh();

      expect(stateOf(container), isA<HomeWeatherHidden>());
    });

    test('권한을 끄고 돌아오면 날씨를 내린다', () async {
      final container = start();
      final controller = container.read(homeWeatherProvider.notifier);

      await controller.refresh();
      location.access = LocationAccess.deniedForever;
      await controller.refresh();

      expect(stateOf(container), isA<HomeWeatherHidden>());
    });

    test('⚠️ 날씨를 받는 사이 권한을 끄고 돌아오면, 끝난 뒤 다시 보고 내린다', () async {
      final container = start();
      final controller = container.read(homeWeatherProvider.notifier);
      weather.hold = Completer<void>();

      final first = controller.refresh();
      await pumpEventQueue();
      // 받는 중에 위치를 끄고 앱으로 돌아온다 — 셸이 다시 부른다.
      location.access = LocationAccess.deniedForever;
      final second = controller.refresh();
      weather.hold!.complete();
      await Future.wait([first, second]);

      expect(stateOf(container), isA<HomeWeatherHidden>());
    });

    testWidgets('⚠️ 동네 이름이 3초 넘게 안 오면 날씨만 그린다', (tester) async {
      final container = start();
      place.hang = true;

      unawaited(container.read(homeWeatherProvider.notifier).refresh());
      await tester.pump(const Duration(seconds: 4));

      final state = stateOf(container);
      expect(state, isA<HomeWeatherShown>());
      expect((state as HomeWeatherShown).place, isNull);
    });
  });
}

class _FakePlaceRepository implements PlaceRepository {
  bool fail = false;

  /// 끝나지 않는 지오코더. 시간 제한을 확인하는 데 쓴다.
  bool hang = false;

  @override
  Future<String?> nameOf({
    required double latitude,
    required double longitude,
  }) {
    if (hang) return Completer<String?>().future;
    if (fail) return Future.error(Exception('지오코더 실패'));
    return Future.value('서울 중구');
  }
}

class _FakeWeatherRepository implements WeatherRepository {
  int calls = 0;
  bool fail = false;

  /// 있으면 응답이 이것을 기다린다.
  Completer<void>? hold;

  @override
  Future<Weather> current({
    required double latitude,
    required double longitude,
  }) async {
    calls++;
    await hold?.future;
    if (fail) throw Exception('네트워크 실패');
    return const Weather(sky: WeatherSky.clear, temperature: 18);
  }
}
