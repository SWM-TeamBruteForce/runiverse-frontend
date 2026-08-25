import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/settings/data/fake_settings_repository.dart';
import 'package:runiverse/features/settings/data/http_settings_repository.dart';
import 'package:runiverse/features/settings/data/staged_settings_repository.dart';
import 'package:runiverse/features/settings/domain/account_info.dart';
import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/domain/password_change_failure.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';
import 'package:runiverse/features/settings/domain/settings_repository.dart';

/// 설정 저장소.
///
/// ## ⚠️ 서버가 뜨면 여기를 바꾼다
///
/// 지금은 [StagedSettingsRepository]가 배포된 것만 서버로 보낸다.
/// 55·57·58번과 탈퇴가 배포되면 **이 한 줄을 `HttpSettingsRepository`로 바꾸고**
/// `staged_settings_repository.dart`와 가짜를 지운다.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => StagedSettingsRepository(
    live: HttpSettingsRepository(
      ref.watch(dioProvider),
      ref.watch(tokenStoreProvider),
      ref.watch(authRepositoryProvider),
    ),
    // ⚠️ `Provider`가 이 인스턴스를 하나만 만들어 들고 있는다. 그래야 토글을
    // 켜고 화면을 나갔다 들어와도 켜진 채로 남는다.
    fake: FakeSettingsRepository(),
  ),
);

/// 화면이 보는 상태.
///
/// [account]와 [settings]가 **따로** 있는 이유는 두 API가 따로 오기 때문이다.
/// 하나가 실패해도 다른 하나는 그린다 — 계정 조회가 실패했다고 알림 토글까지
/// 감출 이유가 없다.
class SettingsState {
  const SettingsState({
    this.account,
    this.settings,
    this.failure,
    this.loading = false,
  });

  final AccountInfo? account;
  final AppSettings? settings;

  /// 마지막 조회 실패. 둘 중 하나라도 실패하면 값이 있다.
  final SettingsFailure? failure;

  final bool loading;

  /// 아무것도 못 읽었는가. 화면의 `error` 분기 조건이다.
  ///
  /// ⚠️ **이때도 로그아웃 버튼은 살아 있어야 한다.** 세션이 이상해서 조회가
  /// 실패하는 경우가 있는데, 그때 로그아웃까지 막히면 앱에서 나갈 방법이 없다.
  bool get isEmpty => account == null && settings == null;

  SettingsState copyWith({
    AccountInfo? account,
    AppSettings? settings,
    SettingsFailure? failure,
    bool? loading,
  }) => SettingsState(
    account: account ?? this.account,
    settings: settings ?? this.settings,
    // ⚠️ `??`를 쓰지 않는다. 실패를 **지울** 수 있어야 해서다 —
    // `failure ?? this.failure`로 두면 한 번 실패한 뒤로 영영 실패가 남는다.
    failure: failure,
    loading: loading ?? this.loading,
  );
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
      SettingsController.new,
    );

/// 설정을 읽고 바꾼다.
///
/// ## 토글과 칩은 낙관적으로 반영한다
///
/// 누르면 **즉시 화면이 바뀌고** 뒤에서 `PATCH`를 보낸다. 실패하면 되돌리고
/// 화면이 스낵바를 띄운다. 스위치를 누르고 스피너를 보며 기다리는 것은
/// 설정 화면에서 특히 나쁘다.
class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() => const SettingsState();

  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  /// 계정과 설정을 함께 읽는다.
  ///
  /// **두 요청은 서로 모른다.** 순서대로 기다리면 그냥 두 배 느리다.
  Future<void> load() async {
    state = state.copyWith(loading: true);

    final ((account, accountFailure), (settings, settingsFailure)) = await (
      _attempt(_repository.fetchAccount()),
      _attempt(_repository.fetchSettings()),
    ).wait;

    state = SettingsState(
      account: account,
      settings: settings,
      failure: accountFailure ?? settingsFailure,
    );
  }

  /// 알림을 받겠다는 의사를 바꾼다. 실패하면 그 이유를 돌려준다.
  ///
  /// ⚠️ 이 값이 `true`라고 알림이 오지는 않는다. 앱에 알림을 띄우는 코드가
  /// 아직 없다(설계 문서 3절).
  Future<SettingsFailure?> setAlertConsent(bool value) =>
      _update(alertConsent: value);

  /// 공개 범위를 바꾼다. 실패하면 그 이유를 돌려준다.
  Future<SettingsFailure?> setVisibility(ProfileVisibility value) =>
      _update(visibility: value);

  /// 낙관적 반영의 실체.
  ///
  /// **되돌리려면 "보내기 전 값"을 들고 있어야 한다.** 보낸 값을 들고 있으면
  /// 되돌릴 곳을 모른다.
  Future<SettingsFailure?> _update({
    bool? alertConsent,
    ProfileVisibility? visibility,
  }) async {
    final previous = state.settings;
    // 아직 못 읽었다. 바꿀 대상이 없으니 요청도 만들지 않는다.
    if (previous == null) return null;

    state = state.copyWith(
      settings: previous.copyWith(
        alertConsent: alertConsent,
        visibility: visibility,
      ),
    );

    try {
      final updated = await _repository.updateSettings(
        alertConsent: alertConsent,
        visibility: visibility,
      );
      // **응답으로 통째로 덮는다.** 서버가 부분 수정이어도 전체 설정을 돌려주므로,
      // 연타해서 응답 순서가 뒤바뀌어도 마지막 응답이 화면을 정리한다.
      state = state.copyWith(settings: updated);
      return null;
    } on SettingsException catch (error) {
      state = state.copyWith(settings: previous);
      return error.failure;
    }
  }

  /// 비밀번호를 바꾼다. 실패하면 그 이유를 돌려준다.
  ///
  /// 성공해도 **로그아웃되지 않는다.** 서버가 기존 토큰을 그대로 둔다.
  Future<PasswordChangeFailure?> changePassword({
    required String current,
    required String next,
  }) async {
    try {
      await _repository.changePassword(current: current, next: next);
      return null;
    } on PasswordChangeException catch (error) {
      return error.failure;
    }
  }

  /// 계정을 지운다. **되돌릴 수 없다.**
  ///
  /// 성공하면 서버 세션이 이미 죽어 있다. 그래서 `signOut()`이 아니라
  /// **로컬만 비우는 경로**로 나간다 — 실패할 호출을 한 번 더 보내지 않는다.
  Future<SettingsFailure?> withdraw() async {
    try {
      await _repository.withdraw();
      await ref.read(authControllerProvider.notifier).forgetSession();
      return null;
    } on SettingsException catch (error) {
      return error.failure;
    }
  }

  /// 실패를 예외가 아니라 값으로 바꾼다.
  ///
  /// `.wait`는 하나라도 던지면 `ParallelWaitError`가 되어 **성공한 쪽 결과까지
  /// 잃는다.** 여기서 먼저 잡아 두면 둘을 따로 다룰 수 있다.
  Future<(T?, SettingsFailure?)> _attempt<T>(Future<T> future) async {
    try {
      return (await future, null);
    } on SettingsException catch (error) {
      return (null, error.failure);
    }
  }
}
