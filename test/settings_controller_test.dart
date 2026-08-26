import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/settings/data/fake_settings_repository.dart';
import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';
import 'package:runiverse/features/settings/presentation/settings_provider.dart';

/// 설정 — **낙관적 반영이 제대로 되돌아오는가.**
///
/// 토글을 누르면 화면이 먼저 바뀌고 뒤에서 `PATCH`가 나간다. 서버가 거절하면
/// 되돌려야 하는데, **되돌리지 않으면 사용자는 껐다고 생각하고 나간다.**
/// 그 뒤로 화면과 서버가 영영 갈라진다.
void main() {
  ProviderContainer makeContainer(FakeSettingsRepository repository) =>
      ProviderContainer.test(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );

  /// 응답이 늦어야 **먼저 바뀌었는지**를 볼 수 있다. 즉시 답하면 화면이
  /// 먼저 바뀐 것인지 응답을 받고 바뀐 것인지 구분되지 않는다.
  FakeSettingsRepository slow({SettingsFailure? updateFailure}) =>
      FakeSettingsRepository(
        latency: const Duration(milliseconds: 30),
        updateFailure: updateFailure,
      );

  group('낙관적 반영', () {
    test('응답을 기다리지 않고 화면이 먼저 바뀐다', () async {
      final container = makeContainer(slow());
      final notifier = container.read(settingsControllerProvider.notifier);
      await notifier.load();

      // ⚠️ **일부러 await 하지 않는다.** 여기서 기다리면 이 테스트가 검사하려는
      // 순간이 지나가 버린다.
      final pending = notifier.setAlertConsent(false);

      expect(
        container.read(settingsControllerProvider).settings?.alertConsent,
        isFalse,
      );
      await pending;
    });

    test('⚠️ 실패하면 누르기 전 값으로 되돌린다', () async {
      final container = makeContainer(
        slow(updateFailure: SettingsFailure.network),
      );
      final notifier = container.read(settingsControllerProvider.notifier);
      await notifier.load();

      final failure = await notifier.setAlertConsent(false);

      expect(failure, SettingsFailure.network);
      expect(
        container.read(settingsControllerProvider).settings?.alertConsent,
        isTrue,
      );
    });

    test('공개 범위도 실패하면 되돌린다', () async {
      final container = makeContainer(
        slow(updateFailure: SettingsFailure.server),
      );
      final notifier = container.read(settingsControllerProvider.notifier);
      await notifier.load();

      await notifier.setVisibility(ProfileVisibility.followers);

      expect(
        container.read(settingsControllerProvider).settings?.visibility,
        ProfileVisibility.public,
      );
    });

    test('한 필드만 바꿔도 나머지는 그대로다', () async {
      // 서버는 부분 수정이어도 **전체 설정**을 돌려준다. 그것을 통째로 덮어쓰는데,
      // 이때 보내지 않은 필드가 기본값으로 밀리면 안 된다.
      final container = makeContainer(
        FakeSettingsRepository(
          latency: Duration.zero,
          settings: const AppSettings(
            alertConsent: false,
            visibility: ProfileVisibility.public,
          ),
        ),
      );
      final notifier = container.read(settingsControllerProvider.notifier);
      await notifier.load();

      await notifier.setVisibility(ProfileVisibility.followers);

      final settings = container.read(settingsControllerProvider).settings;
      expect(settings?.visibility, ProfileVisibility.followers);
      expect(settings?.alertConsent, isFalse);
    });

    test('⚠️ 아직 못 읽었으면 요청을 만들지 않는다', () async {
      // 지금 값을 모르면 실패해도 **되돌릴 자리가 없다.**
      final repository = slow();
      final container = makeContainer(repository);

      final failure = await container
          .read(settingsControllerProvider.notifier)
          .setAlertConsent(false);

      expect(failure, isNull);
      expect(repository.updateCalls, 0);
    });
  });

  group('조회', () {
    test('계정을 못 읽어도 설정은 그린다', () async {
      // 두 API는 서로 모른다. 하나가 죽었다고 알림 토글까지 감출 이유가 없다.
      final container = makeContainer(
        FakeSettingsRepository(
          latency: Duration.zero,
          accountFailure: SettingsFailure.server,
        ),
      );

      await container.read(settingsControllerProvider.notifier).load();

      final state = container.read(settingsControllerProvider);
      expect(state.account, isNull);
      expect(state.settings, isNotNull);
      // 절반이라도 읽었으면 오류 화면이 아니다.
      expect(state.isEmpty, isFalse);
    });

    test('설정을 못 읽어도 계정은 그린다', () async {
      final container = makeContainer(
        FakeSettingsRepository(
          latency: Duration.zero,
          settingsFailure: SettingsFailure.server,
        ),
      );

      await container.read(settingsControllerProvider.notifier).load();

      final state = container.read(settingsControllerProvider);
      expect(state.account, isNotNull);
      expect(state.settings, isNull);
      expect(state.isEmpty, isFalse);
    });

    test('둘 다 실패해야 오류 화면이다', () async {
      final container = makeContainer(
        FakeSettingsRepository(
          latency: Duration.zero,
          accountFailure: SettingsFailure.network,
          settingsFailure: SettingsFailure.network,
        ),
      );

      await container.read(settingsControllerProvider.notifier).load();

      final state = container.read(settingsControllerProvider);
      expect(state.isEmpty, isTrue);
      expect(state.failure, SettingsFailure.network);
    });

    test('⚠️ 다시 불러 성공하면 실패가 지워진다', () async {
      // `copyWith`에서 실패를 `??`로 이어받으면 한 번 실패한 뒤로 영영 남는다.
      //
      // ⚠️ **같은 저장소가 답을 바꿔야 한다.** 새 인스턴스로 갈아 끼우면
      // 처음부터 실패가 없던 것을 보게 되어 아무것도 검사하지 못한다.
      final repository = FakeSettingsRepository(
        latency: Duration.zero,
        accountFailure: SettingsFailure.network,
        settingsFailure: SettingsFailure.network,
      );
      final container = makeContainer(repository);
      final notifier = container.read(settingsControllerProvider.notifier);
      await notifier.load();
      expect(container.read(settingsControllerProvider).failure, isNotNull);

      // 서버가 살아났다.
      repository.accountFailure = null;
      repository.settingsFailure = null;
      await notifier.load();

      expect(container.read(settingsControllerProvider).failure, isNull);
      expect(container.read(settingsControllerProvider).isEmpty, isFalse);
    });
  });
}
