import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/settings/data/fake_settings_repository.dart';
import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/data/staged_settings_repository.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';

/// 어느 것이 **진짜 서버로 가는가.**
///
/// ## ⚠️ 이 그물이 없어서 탈퇴가 가짜에 묶여 있었다
///
/// 화면도 저장소도 다 만들어져 있었는데 [StagedSettingsRepository]가 가짜로
/// 돌리고 있었고, 그 사실을 보는 테스트가 없었다. 위젯 테스트는 전부 가짜를
/// 직접 끼워 넣어서 **이 배선 자체를 한 번도 지나지 않았다.**
///
/// 서버가 뜨는 순서대로 한 줄씩 옮겨 가는 파일이라, 옮겼는지 아닌지를
/// 여기서 본다. 넷이 다 `live`로 가면 이 파일과 함께 지운다.
void main() {
  late FakeSettingsRepository live;
  late FakeSettingsRepository fake;
  late StagedSettingsRepository staged;

  setUp(() {
    // 둘 다 가짜지만 **서로 다른 인스턴스**다. 어느 쪽이 불렸는지로 가른다.
    //
    // 조회에는 호출 횟수가 없어서 **값을 다르게 심어** 누가 답했는지 본다.
    live = FakeSettingsRepository(
      latency: Duration.zero,
      settings: const AppSettings(
        alertConsent: false,
        visibility: ProfileVisibility.followers,
      ),
    );
    fake = FakeSettingsRepository(latency: Duration.zero);
    staged = StagedSettingsRepository(live: live, fake: fake);
  });

  test('⚠️ 탈퇴는 진짜 서버로 간다', () async {
    // 가짜로 가면 **계정이 지워지지 않는데 지워졌다고 나온다.**
    await staged.withdraw();

    expect(live.withdrawCalls, 1);
    expect(fake.withdrawCalls, 0);
  });

  test('비밀번호 변경은 진짜 서버로 간다', () async {
    await staged.changePassword(current: 'old123!', next: 'new123!');

    expect(live.currentPassword, 'old123!');
    expect(fake.currentPassword, isNull);
  });

  test('설정 조회는 아직 가짜가 답한다', () async {
    // 명세상 개발완료지만 아직 옮기지 않았다. 옮기는 날 이 테스트가 뒤집힌다.
    final settings = await staged.fetchSettings();

    // 가짜의 기본값이다. `live`에는 반대로 심어 두었다.
    expect(settings.alertConsent, isTrue);
    expect(settings.visibility, ProfileVisibility.public);
  });

  test('설정 변경은 아직 가짜가 답한다', () async {
    await staged.updateSettings(visibility: ProfileVisibility.public);

    expect(fake.updateCalls, 1);
    expect(live.updateCalls, 0);
  });
}
