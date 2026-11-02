import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/settings/data/http_settings_repository.dart';
import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/domain/password_change_failure.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';
import 'package:runiverse/features/settings/domain/settings_repository.dart';

/// 설정 저장소.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => HttpSettingsRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
  ),
);

/// 화면이 보는 상태.
///
/// ## ⚠️ 계정 정보는 여기 없다
///
/// 이메일과 로그인 수단은 `GET /users/me`가 실어 오므로 **auth가 소유한다**
/// (`CurrentUser`). 전용 경로였던 `/users/me/account`는 없어졌다.
/// 화면은 두 곳을 따로 읽는다 — 계정 조회가 실패했다고 알림 토글까지 감추거나,
/// 그 반대가 되지 않는다.
class SettingsState {
  const SettingsState({this.settings, this.failure, this.loading = false});

  final AppSettings? settings;

  /// 마지막 조회 실패.
  final SettingsFailure? failure;

  final bool loading;

  /// 아무것도 못 읽었는가. 화면의 `error` 분기 조건이다.
  ///
  /// ⚠️ **이때도 로그아웃 버튼은 살아 있어야 한다.** 세션이 이상해서 조회가
  /// 실패하는 경우가 있는데, 그때 로그아웃까지 막히면 앱에서 나갈 방법이 없다.
  bool get isEmpty => settings == null;

  SettingsState copyWith({
    AppSettings? settings,
    SettingsFailure? failure,
    bool? loading,
  }) => SettingsState(
    settings: settings ?? this.settings,
    // ⚠️ `??`를 쓰지 않는다. 실패를 **지울** 수 있어야 해서다 —
    // `failure ?? this.failure`로 두면 한 번 실패한 뒤로 영영 실패가 남는다.
    failure: failure,
    loading: loading ?? this.loading,
  );
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);

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

  /// 설정을 읽는다.
  ///
  /// 계정 정보는 여기서 읽지 않는다 — `/users/me`가 이미 실어 왔다.
  Future<void> load() async {
    state = state.copyWith(loading: true);

    // 저장 중에 시작한 조회는 버린다. 서버가 그 저장을 처리하기 전에 읽었을
    // 수 있다 — 화면은 저장 응답이 정리한다.
    final sendingAtStart = _sending;
    final (settings, failure) = await _attempt(_repository.fetchSettings());
    if (sendingAtStart || _sending) {
      state = state.copyWith(loading: false);
      return;
    }

    state = SettingsState(settings: settings, failure: failure);
  }

  /// 알림을 받겠다는 의사를 바꾼다. 실패하면 그 이유를 돌려준다.
  ///
  /// ⚠️ 서버는 이 값이 `false`인 사람에게 푸시를 보내지 않는다. `true`여도
  /// 기기 알림 권한이 꺼져 있으면 오지 않는다(설계 문서 3절).
  Future<SettingsFailure?> setAlertConsent(bool value) =>
      _update(alertConsent: value);

  /// 공개 범위를 바꾼다. 실패하면 그 이유를 돌려준다.
  Future<SettingsFailure?> setVisibility(ProfileVisibility value) =>
      _update(visibility: value);

  /// 지금 `PATCH`가 나가 있는가. 한 번에 하나만 보낸다.
  bool _sending = false;

  /// 사용자가 눌렀지만 아직 보내지 않은 값. 보낼 때 꺼내 비운다.
  ///
  /// ⚠️ 화면 값(`state.settings`)을 쓰지 않는다. 그사이 [load]가 옛 값을
  /// 써 넣으면 그것을 사용자가 고른 값으로 알고 다시 보낸다.
  bool? _pendingAlertConsent;
  ProfileVisibility? _pendingVisibility;

  /// 낙관적 반영의 실체.
  ///
  /// **되돌리려면 "서버가 확인해 준 값"을 들고 있어야 한다.** 보낸 값을 들고
  /// 있으면 되돌릴 곳을 모른다.
  ///
  /// ## ⚠️ 연타해도 요청은 하나씩 나간다
  ///
  /// 요청을 겹쳐 보내면 서버가 처리하는 순서도, 응답이 도착하는 순서도
  /// 보장되지 않는다. 늦게 도착한 옛 응답이 화면을 덮으면 화면은 꺼짐인데
  /// 서버는 켜짐인 채로 남는다. 그래서 보내는 중에 누르면 화면을 바꾸고 누른
  /// 값을 기억해 두었다가, 응답이 오면 서버 값과 다를 때만 한 번 더 보낸다.
  Future<SettingsFailure?> _update({
    bool? alertConsent,
    ProfileVisibility? visibility,
  }) async {
    final shown = state.settings;
    // 아직 못 읽었다. 바꿀 대상이 없으니 요청도 만들지 않는다.
    if (shown == null) return null;

    state = state.copyWith(
      settings: shown.copyWith(
        alertConsent: alertConsent,
        visibility: visibility,
      ),
    );
    _pendingAlertConsent = alertConsent ?? _pendingAlertConsent;
    _pendingVisibility = visibility ?? _pendingVisibility;
    // 보내는 중이면 기억만 한다. 응답이 오면 아래 반복이 보낸다.
    if (_sending) return null;

    _sending = true;
    // 서버가 마지막으로 확인해 준 값. 실패하면 여기로 되돌린다.
    var confirmed = shown;
    try {
      while (true) {
        final pendingAlert = _pendingAlertConsent;
        final pendingVisibility = _pendingVisibility;
        _pendingAlertConsent = null;
        _pendingVisibility = null;
        final sendAlert = pendingAlert == confirmed.alertConsent
            ? null
            : pendingAlert;
        final sendVisibility = pendingVisibility == confirmed.visibility
            ? null
            : pendingVisibility;
        if (sendAlert == null && sendVisibility == null) break;
        // **응답으로 통째로 덮는다.** 서버는 부분 수정이어도 전체 설정을 돌려준다.
        confirmed = await _repository.updateSettings(
          alertConsent: sendAlert,
          visibility: sendVisibility,
        );
      }
      state = state.copyWith(settings: confirmed);
      return null;
    } on SettingsException catch (error) {
      // 화면을 되돌리므로 그사이 누른 값도 버린다.
      _pendingAlertConsent = null;
      _pendingVisibility = null;
      state = state.copyWith(settings: confirmed);
      return error.failure;
    } finally {
      _sending = false;
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
  ///
  /// ## ⚠️ 약관 동의를 여기서 지운다
  ///
  /// `forgetSession()`은 로그아웃도 쓰는 길이라 동의를 **일부러 남긴다**.
  /// 탈퇴만 다르다 — 계정이 사라졌으니 동의도 사라진 것이다. 남겨 두면 같은
  /// 소셜 계정으로 다시 들어온 사람이 **약관을 건너뛰고** 프로필 입력부터
  /// 보게 된다. 기기에서 눌러 보고 알았다.
  ///
  /// 실패하면 지우지 않는다. 계정이 그대로 있는데 동의만 없어지면 다음에
  /// 들어올 때 같은 것을 또 묻는다.
  Future<SettingsFailure?> withdraw() async {
    try {
      await _repository.withdraw();
      unawaited(ref.read(analyticsProvider).withdraw());
      await ref.read(consentStoreProvider).forgetTermsAgreement();
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
