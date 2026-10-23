import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/core/version/installed_app_version.dart';

/// 설치된 앱의 버전 이름을 읽는 자리.
///
/// `main()`이 화면을 세우기 전에 부른다. **여기서 던지면 앱이 아예 안 선다.**
void main() {
  setUp(InstalledAppVersion.resetForTest);
  tearDown(InstalledAppVersion.resetForTest);

  test('⚠️ 플랫폼 채널이 없어도 던지지 않는다', () async {
    // 테스트 환경에는 채널이 없어 `PackageInfo.fromPlatform()`이 실패한다.
    // 기기에서도 같은 일이 날 수 있고, 그때 던지면 앱이 못 뜬다.
    await expectLater(InstalledAppVersion.load(), completes);
  });

  test('⚠️ 못 읽으면 null이다 — 0.0.0으로 누르지 않는다', () async {
    // `0.0.0`은 **어떤 최소 버전에도 못 미치는 값**이라, 값을 못 읽었을 뿐인
    // 사용자를 영영 업데이트 화면에 가둔다.
    await InstalledAppVersion.load();

    expect(InstalledAppVersion.current, isNull);
  });

  test('한 번 읽으면 들고 있는다', () async {
    InstalledAppVersion.setForTest(const AppVersion(1, 2, 3));

    // 이미 읽어 둔 값이 있으면 채널을 다시 부르지 않는다.
    expect(await InstalledAppVersion.load(), const AppVersion(1, 2, 3));
    expect(InstalledAppVersion.current, const AppVersion(1, 2, 3));
  });
}
