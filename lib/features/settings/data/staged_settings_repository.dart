import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_repository.dart';

/// **배포된 API만 서버로 보내고, 나머지는 가짜가 답한다.**
///
/// ## ⚠️ 이것은 임시다
///
/// 진짜로 부를 수 없는 것을 부르면 화면이 통째로 오류가 된다. 그렇다고 되는
/// 것까지 가짜로 두면 **되는 기능을 안 쓰는 것**이라, 둘을 갈라 끼운다.
///
/// ## ⚠️ 남은 둘도 서버는 이미 떠 있다
///
/// 설정 조회(55)·변경(56)은 명세상 **개발완료**인데 아직 가짜가 답한다.
/// 탈퇴만 붙이면서 확인한 사실이라 이 PR 범위 밖으로 두었다 — 둘을 붙이는
/// 순간 설정 화면 전체의 동작이 바뀌므로 따로 본다.
///
/// 예전 주석은 넷 다 "개발전"이라고 적고 있었는데 **셋이 이미 완료였다.**
/// 서버 현황을 주석으로 들고 있으면 이렇게 낡는다 — 붙일 때마다 명세를 본다.
///
/// ## 둘을 붙이면 이 파일을 지운다
///
/// `settings_provider.dart`가 [live]를 그대로 쓰게 바꾸고 이 클래스를 삭제한다.
/// 지울 때를 알아보게 하려고 따로 두었다 — `HttpSettingsRepository`에 `if`를
/// 심으면 나중에 무엇이 임시였는지 찾지 못한다.
class StagedSettingsRepository implements SettingsRepository {
  const StagedSettingsRepository({required this.live, required this.fake});

  /// 진짜 서버. 지금은 비밀번호 변경과 탈퇴가 간다.
  final SettingsRepository live;

  /// 배포되지 않은 것을 대신 답한다.
  final SettingsRepository fake;

  /// ✅ 비밀번호 변경 — 개발완료.
  @override
  Future<void> changePassword({
    required String current,
    required String next,
  }) => live.changePassword(current: current, next: next);

  /// ⚠️ 명세 55번 — **개발완료인데 아직 가짜다.**
  @override
  Future<AppSettings> fetchSettings() => fake.fetchSettings();

  /// ⚠️ 명세 56번 — **개발완료인데 아직 가짜다.**
  @override
  Future<AppSettings> updateSettings({
    bool? alertConsent,
    ProfileVisibility? visibility,
  }) => fake.updateSettings(alertConsent: alertConsent, visibility: visibility);

  /// ✅ 명세 57번 — 개발완료. `DELETE /api/v1/users/me`
  @override
  Future<void> withdraw() => live.withdraw();
}
