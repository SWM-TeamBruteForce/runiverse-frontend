import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/watch_version_store.dart';
import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/domain/app_update_status.dart';
import 'package:runiverse/features/app_update/presentation/app_update_provider.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/app_update/presentation/watch_version_provider.dart';

/// 워치 최소 버전을 **언제 받고 무엇을 남기는가.**
///
/// 워치 연동은 이 값으로 `WATCH_SYNC` 를 판정한다. 값을 잃으면 워치가 기준을 받을
/// 때까지 연결되지 않는다.
void main() {
  late _HeldWatchVersions versions;
  late InMemoryWatchVersionStore store;

  ProviderContainer start({AppVersion? stored}) {
    versions = _HeldWatchVersions()..watchMinimum = const AppVersion(1, 2, 0);
    store = InMemoryWatchVersionStore(stored);
    return ProviderContainer(
      overrides: [
        appVersionRepositoryProvider.overrideWithValue(versions),
        watchVersionStoreProvider.overrideWithValue(store),
      ],
    );
  }

  test('⚠️ 폰 판정은 워치 기준을 기다리지 않고, 받은 기준은 뒤에 남긴다', () async {
    final container = start();
    addTearDown(container.dispose);
    versions.hold = Completer<void>();

    await container.read(appUpdateProvider.notifier).check();

    // 워치 값이 아직 안 왔어도 폰은 들어간다.
    expect(container.read(appUpdateProvider), isA<AppUpdateChecked>());
    expect(versions.watchFetchCount, 1);
    expect(container.read(watchVersionProvider), isNull);

    versions.hold!.complete();
    await container.read(watchVersionProvider.notifier).refresh();

    expect(container.read(watchVersionProvider), const AppVersion(1, 2, 0));
    expect(await store.minimum(), const AppVersion(1, 2, 0));
  });

  test('앱으로 돌아와 다시 물을 때도 워치 기준을 받는다', () async {
    final container = start();
    addTearDown(container.dispose);
    final updates = container.read(appUpdateProvider.notifier);
    await updates.check();
    await container.read(watchVersionProvider.notifier).refresh();

    versions.watchMinimum = const AppVersion(1, 3, 0);
    await updates.recheck();
    await container.read(watchVersionProvider.notifier).refresh();

    expect(versions.watchFetchCount, 2);
    expect(container.read(watchVersionProvider), const AppVersion(1, 3, 0));
  });

  test('워치 기준을 못 받아도 폰 판정은 끝난다', () async {
    final container = start();
    addTearDown(container.dispose);
    versions.watchFailure = Exception('offline');

    await container.read(appUpdateProvider.notifier).check();

    expect(container.read(appUpdateProvider), isA<AppUpdateChecked>());
  });

  test('버려진 뒤 늦게 온 기준은 건드리지 않는다', () async {
    final container = start();
    versions.hold = Completer<void>();
    final pending = container.read(watchVersionProvider.notifier).refresh();

    container.dispose();
    versions.hold!.complete();

    // 버려진 provider 의 state 를 쓰면 여기서 던진다.
    await pending;
    expect(await store.minimum(), isNull);
  });

  test('남겨 둔 값을 읽는 도중 버려져도 던지지 않는다', () async {
    final held = Completer<AppVersion?>();
    final container = ProviderContainer(
      overrides: [
        appVersionRepositoryProvider.overrideWithValue(_HeldWatchVersions()),
        watchVersionStoreProvider.overrideWithValue(_HeldStore(held)),
      ],
    );
    final pending = container.read(watchVersionProvider.notifier).minimum();

    container.dispose();
    held.complete(const AppVersion(1, 2, 0));

    // 버려진 provider 의 state 를 읽거나 쓰면 여기서 던진다.
    expect(await pending, isNull);
  });

  test('읽는 중에 다시 물어도 같은 읽기를 기다려 남겨 둔 값을 받는다', () async {
    final held = Completer<AppVersion?>();
    final container = ProviderContainer(
      overrides: [
        appVersionRepositoryProvider.overrideWithValue(_HeldWatchVersions()),
        watchVersionStoreProvider.overrideWithValue(_HeldStore(held)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(watchVersionProvider.notifier);

    final first = controller.minimum();
    final second = controller.minimum();
    held.complete(const AppVersion(1, 2, 0));

    expect(await first, const AppVersion(1, 2, 0));
    // 따로 읽기 전이라고 `null` 을 받으면 저장값이 있는데도 답을 미룬다.
    expect(await second, const AppVersion(1, 2, 0));
  });

  test('남겨 둔 기준을 읽는다', () async {
    final container = start(stored: const AppVersion(1, 1, 0));
    addTearDown(container.dispose);

    final minimum = await container
        .read(watchVersionProvider.notifier)
        .minimum();

    expect(minimum, const AppVersion(1, 1, 0));
  });

  test('⚠️ 못 받으면 갖고 있던 기준을 지우지 않는다', () async {
    final container = start(stored: const AppVersion(1, 1, 0));
    addTearDown(container.dispose);
    final controller = container.read(watchVersionProvider.notifier);
    await controller.minimum();
    versions.watchFailure = Exception('offline');

    await controller.refresh();

    expect(await controller.minimum(), const AppVersion(1, 1, 0));
    expect(await store.minimum(), const AppVersion(1, 1, 0));
  });

  test('기준이 내려가면 내려간 값을 남긴다', () async {
    final container = start(stored: const AppVersion(1, 3, 0));
    addTearDown(container.dispose);
    final controller = container.read(watchVersionProvider.notifier);

    await controller.refresh();

    expect(await controller.minimum(), const AppVersion(1, 2, 0));
    expect(await store.minimum(), const AppVersion(1, 2, 0));
  });

  test('겹쳐 불러도 한 번만 묻는다', () async {
    final container = start();
    addTearDown(container.dispose);
    final controller = container.read(watchVersionProvider.notifier);

    await Future.wait([controller.refresh(), controller.refresh()]);

    expect(versions.watchFetchCount, 1);
  });
}

/// 남겨 둔 값 읽기를 [_held] 가 끝날 때까지 잡아 둔다.
class _HeldStore implements WatchVersionStore {
  _HeldStore(this._held);

  final Completer<AppVersion?> _held;

  @override
  Future<AppVersion?> minimum() => _held.future;

  @override
  Future<void> rememberMinimum(AppVersion minimum) async {}
}

/// [hold] 를 세우면 워치 기준 답을 그것이 끝날 때까지 잡아 둔다.
class _HeldWatchVersions extends FakeAppVersionRepository {
  Completer<void>? hold;

  /// 잡아 두지 않으면 받은 Future 를 그대로 돌려준다. 사이에 한 번이라도 쉬면 실패한
  /// 답이 리스너 없이 남아 처리 안 된 오류가 된다.
  @override
  Future<AppVersionPolicy> fetchWatch() async {
    final policy = super.fetchWatch();
    final held = hold;
    if (held == null) return policy;
    await held.future;
    return policy;
  }
}
