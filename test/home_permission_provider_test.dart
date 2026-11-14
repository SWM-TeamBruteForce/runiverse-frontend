import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/core/analytics/fake_analytics.dart';
import 'package:runiverse/core/storage/location_ask_store.dart';
import 'package:runiverse/features/home/presentation/home_permission_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_step_repository.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 홈에서 권한 묻기 — **언제 묻고, 언제 묻지 않는가.**
///
/// 기기당 한 번이다. 안드로이드는 두 번 거절하면 다시 물을 수 없어서, 홈에서
/// 두 번째 거절을 받으면 러닝 출발 때 물을 기회가 사라진다.
void main() {
  late FakeLocationRepository location;
  late FakeStepRepository steps;
  late _CountingAskStore asks;
  late FakeAnalytics analytics;

  HomePermissionAsker start({
    LocationAccess access = LocationAccess.denied,
    bool asked = false,
    bool failEnsure = false,
    bool grantOnAsk = false,
  }) {
    location = failEnsure
        ? _FailingLocation(access: access)
        : grantOnAsk
        ? _GrantOnAsk()
        : FakeLocationRepository(access: access);
    steps = FakeStepRepository();
    asks = _CountingAskStore(asked);
    analytics = FakeAnalytics();
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(location),
        stepRepositoryProvider.overrideWithValue(steps),
        locationAskStoreProvider.overrideWithValue(asks),
        analyticsProvider.overrideWithValue(analytics),
      ],
    );
    addTearDown(container.dispose);
    return container.read(homePermissionProvider);
  }

  test('처음이면 위치와 신체 활동을 묻는다', () async {
    final asker = start();

    final done = await asker.askOnce();

    expect(done, isTrue);
    expect(location.ensureAccessCount, 1);
    expect(steps.accessCalls, 1);
  });

  test('⚠️ 물었다는 것을 남긴 뒤에 묻는다', () async {
    final asker = start();
    asks.onMark = () {
      expect(location.ensureAccessCount, 0, reason: '묻기 전에 남긴다');
      expect(steps.accessCalls, 0, reason: '묻기 전에 남긴다');
    };

    await asker.askOnce();

    expect(asks.marks, 1);
  });

  test('⚠️ 이미 물었으면 다시 묻지 않는다', () async {
    final asker = start(asked: true);

    await asker.askOnce();

    expect(location.ensureAccessCount, 0);
    expect(steps.accessCalls, 0);
    expect(asks.marks, 0);
  });

  test('두 번 불러도 한 번만 묻는다', () async {
    final asker = start();

    await asker.askOnce();
    await asker.askOnce();

    expect(location.ensureAccessCount, 1);
    expect(steps.accessCalls, 1);
  });

  test('⚠️ 위치 기능이 꺼져 있으면 묻지 않고 기회도 쓰지 않는다', () async {
    // 꺼져 있으면 `ensureAccess`가 묻지도 않고 돌아온다. 미뤘다고 답해
    // 셸이 앱으로 돌아올 때 다시 부르게 한다.
    final asker = start(access: LocationAccess.serviceDisabled);

    final done = await asker.askOnce();

    expect(done, isFalse);
    expect(location.ensureAccessCount, 0);
    expect(steps.accessCalls, 0);
    expect(asks.marks, 0);
  });

  test('⚠️ 위치 기능을 켠 뒤 다시 부르면 그때 묻는다', () async {
    final asker = start(access: LocationAccess.serviceDisabled);
    await asker.askOnce();
    location.access = LocationAccess.denied;

    final done = await asker.askOnce();

    expect(done, isTrue);
    expect(location.ensureAccessCount, 1);
    expect(steps.accessCalls, 1);
  });

  test('위치를 이미 허용했거나 다시 물을 수 없으면 신체 활동만 묻는다', () async {
    for (final access in [
      LocationAccess.granted,
      LocationAccess.deniedForever,
    ]) {
      final asker = start(access: access);

      await asker.askOnce();

      expect(location.ensureAccessCount, 0, reason: '$access');
      expect(steps.accessCalls, 1, reason: '$access');
    }
  });

  test('⚠️ 저장하지 못하면 묻지 않는다 — 기기당 한 번을 지킬 수 없다', () async {
    final asker = start();
    asks.failWrite = true;

    final done = await asker.askOnce();

    // 미뤘다고 답하면 셸이 복귀할 때마다 다시 부른다.
    expect(done, isTrue);
    expect(location.ensureAccessCount, 0);
    expect(steps.accessCalls, 0);
  });

  test('⚠️ 저장값을 못 읽으면 물었다고 본다', () async {
    final asker = start();
    asks.failRead = true;

    final done = await asker.askOnce();

    expect(done, isTrue);
    expect(location.ensureAccessCount, 0);
    expect(steps.accessCalls, 0);
  });

  test('⚠️ 위치 요청이 실패해도 신체 활동은 묻는다', () async {
    // 이미 물었다고 남긴 뒤라, 여기서 멈추면 신체 활동을 물을 기회가 사라진다.
    final asker = start(failEnsure: true);

    final done = await asker.askOnce();

    expect(done, isTrue);
    expect(steps.accessCalls, 1);
  });

  group('permission_result', () {
    // 남은 순서대로 `권한:결과:자리`.
    List<String> logged() => [
      for (final e in analytics.events)
        if (e.$1 == 'permission_result')
          '${e.$2!['permission']}:${e.$2!['result']}:${e.$2!['asked_from']}',
    ];

    test('물은 결과를 자리 home으로 남긴다', () async {
      final asker = start();

      await asker.askOnce();

      expect(logged(), ['location:denied:home', 'activity:granted:home']);
    });

    test('⚠️ 묻기 전 상태가 아니라 물은 결과를 남긴다', () async {
      // 묻기 전엔 거절, 창에서 허용했다. 묻기 전 값을 남기면 denied가 된다.
      final asker = start(grantOnAsk: true);

      await asker.askOnce();

      expect(logged(), ['location:granted:home', 'activity:granted:home']);
    });

    test('위치를 묻지 않았으면 신체 활동만 남는다', () async {
      final asker = start(access: LocationAccess.granted);

      await asker.askOnce();

      expect(logged(), ['activity:granted:home']);
    });

    test('⚠️ 이미 물었으면 아무것도 남지 않는다', () async {
      final asker = start(asked: true);

      await asker.askOnce();

      expect(logged(), isEmpty);
    });

    test('위치 요청이 실패하면 신체 활동만 남는다', () async {
      final asker = start(failEnsure: true);

      await asker.askOnce();

      expect(logged(), ['activity:granted:home']);
    });
  });

  group('iOS', () {
    // iOS는 거절하면 곧바로 `deniedForever`라 `denied`면 아직 안 물은 것이다.
    // 저장값은 Keychain에 남아 앱을 지워도 살아남으므로 보지 않는다.
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('⚠️ 저장값이 남아 있어도 아직 안 물었으면 묻는다 — 다시 깐 기기', () async {
      final asker = start(asked: true);

      final done = await asker.askOnce();

      expect(done, isTrue);
      expect(location.ensureAccessCount, 1);
      expect(steps.accessCalls, 1);
      expect(asks.marks, 0, reason: 'iOS는 남기지 않는다');
    });

    test('이미 답했으면 묻지 않는다', () async {
      for (final access in [
        LocationAccess.granted,
        LocationAccess.deniedForever,
      ]) {
        final asker = start(access: access);

        final done = await asker.askOnce();

        expect(done, isTrue, reason: '$access');
        expect(location.ensureAccessCount, 0, reason: '$access');
        expect(steps.accessCalls, 0, reason: '$access');
      }
    });
  });
}

/// 위치 요청만 실패한다. 겹친 요청이 받는 "이미 진행 중" 오류를 흉내 낸다.
class _FailingLocation extends FakeLocationRepository {
  _FailingLocation({super.access});

  @override
  Future<LocationAccess> ensureAccess() async {
    ensureAccessCount++;
    throw Exception('요청이 이미 진행 중');
  }
}

/// 물으면 허용으로 바뀐다. 묻기 전 상태와 물은 결과를 가르는 데 쓴다.
class _GrantOnAsk extends FakeLocationRepository {
  _GrantOnAsk() : super(access: LocationAccess.denied);

  @override
  Future<LocationAccess> ensureAccess() async {
    ensureAccessCount++;
    return access = LocationAccess.granted;
  }
}

class _CountingAskStore implements LocationAskStore {
  _CountingAskStore(this._asked);

  bool _asked;
  int marks = 0;
  bool failRead = false;
  bool failWrite = false;

  /// 남기는 순간에 부른다. 순서를 확인하는 데 쓴다.
  void Function()? onMark;

  @override
  Future<bool> asked() async {
    if (failRead) throw Exception('읽기 실패');
    return _asked;
  }

  @override
  Future<void> markAsked() async {
    if (failWrite) throw Exception('쓰기 실패');
    onMark?.call();
    marks++;
    _asked = true;
  }
}
