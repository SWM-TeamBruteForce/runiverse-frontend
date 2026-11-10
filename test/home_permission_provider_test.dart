import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  HomePermissionAsker start({
    LocationAccess access = LocationAccess.denied,
    bool asked = false,
  }) {
    location = FakeLocationRepository(access: access);
    steps = FakeStepRepository();
    asks = _CountingAskStore(asked);
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(location),
        stepRepositoryProvider.overrideWithValue(steps),
        locationAskStoreProvider.overrideWithValue(asks),
      ],
    );
    addTearDown(container.dispose);
    return container.read(homePermissionProvider);
  }

  test('처음이면 위치와 신체 활동을 묻는다', () async {
    final asker = start();

    await asker.askOnce();

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
    // 꺼져 있으면 `ensureAccess`가 묻지도 않고 돌아온다. 다음에 다시 본다.
    final asker = start(access: LocationAccess.serviceDisabled);

    await asker.askOnce();

    expect(location.ensureAccessCount, 0);
    expect(steps.accessCalls, 0);
    expect(asks.marks, 0);
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

    await asker.askOnce();

    expect(location.ensureAccessCount, 0);
    expect(steps.accessCalls, 0);
  });

  test('⚠️ 저장값을 못 읽으면 물었다고 본다', () async {
    final asker = start();
    asks.failRead = true;

    await asker.askOnce();

    expect(location.ensureAccessCount, 0);
    expect(steps.accessCalls, 0);
  });
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
