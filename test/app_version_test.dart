import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/version/app_version.dart';
import 'package:runiverse/features/app_update/domain/app_update_status.dart';

/// 버전 비교와 업데이트 판정.
///
/// ## 왜 이것부터 못 박는가
///
/// 서버가 이 값으로 **구버전의 모든 요청을 403으로 막는다.** 비교가 틀리면
/// 멀쩡한 최신 앱이 업데이트 화면에 갇히고, 거기서는 아무것도 할 수 없다.
/// 화면도 헤더도 이 판정 위에 얹힌다.
void main() {
  group('읽기', () {
    test('세 부분을 정수로 읽는다', () {
      final version = AppVersion.parse('1.2.3');

      expect(version, const AppVersion(1, 2, 3));
    });

    test('빌드 번호가 붙어 있어도 이름만 읽는다', () {
      // `pubspec`에서 직접 읽는 경로가 생기면 `1.0.0+7` 꼴로 들어온다.
      expect(AppVersion.parse('1.0.0+7'), const AppVersion(1, 0, 0));
    });

    test('⚠️ 형식이 아니면 null이다 — 0.0.0으로 누르지 않는다', () {
      // `0.0.0`으로 누르면 **어떤 최소 버전에도 못 미치는 값**이 되어,
      // 값을 못 읽었을 뿐인 사용자가 영영 업데이트 화면에 갇힌다.
      for (final broken in [
        null,
        '',
        '1.0',
        '1.0.0.0',
        'v1.0.0',
        '1.0.x',
        // ⚠️ `int.tryParse`가 받아주는 것들. 이것만 믿으면 통과한다.
        '1.+2.3',
        '1.-2.3',
        '1. 2.3',
        // 부분마다 9자리까지다.
        '1.0.1234567890',
      ]) {
        expect(AppVersion.parse(broken), isNull, reason: '"$broken"');
      }
    });
  });

  group('비교', () {
    test('⚠️ 1.10.0이 1.9.0보다 높다 — 문자열로 견주면 뒤집힌다', () {
      // 명세가 따로 못 박은 지점이다. `'1' < '9'`라 문자열 비교는 거꾸로 간다.
      final ten = AppVersion.parse('1.10.0')!;
      final nine = AppVersion.parse('1.9.0')!;

      expect(ten > nine, isTrue);
      expect(ten.toString().compareTo(nine.toString()) < 0, isTrue);
    });

    test('major가 minor·patch를 이긴다', () {
      expect(const AppVersion(2, 0, 0) > const AppVersion(1, 99, 99), isTrue);
    });

    test('같으면 >=가 참이다', () {
      expect(const AppVersion(1, 0, 0) >= const AppVersion(1, 0, 0), isTrue);
      expect(const AppVersion(1, 0, 0) < const AppVersion(1, 0, 0), isFalse);
    });

    test('서버에 싣는 꼴은 빌드 번호가 없다', () {
      expect(AppVersion.parse('1.0.0+7').toString(), '1.0.0');
    });
  });

  group('판정', () {
    const policy = AppVersionPolicy(
      minimum: AppVersion(1, 1, 0),
      latest: AppVersion(1, 2, 0),
    );

    test('최소 미만이면 막는다', () {
      final status = policy.statusFor(const AppVersion(1, 0, 9));

      expect(status, AppUpdateStatus.required);
      expect(status.blocks, isTrue);
    });

    test('⚠️ 최소와 같으면 막지 않는다 — 경계다', () {
      // "미만"이라 같은 값은 통과다. 여기를 뒤집으면 **최소 버전으로 막 올린
      // 사람**이 그대로 갇힌다.
      final status = policy.statusFor(const AppVersion(1, 1, 0));

      expect(status, AppUpdateStatus.recommended);
      expect(status.blocks, isFalse);
    });

    test('최신 미만이면 권할 뿐 막지 않는다', () {
      expect(
        policy.statusFor(const AppVersion(1, 1, 9)),
        AppUpdateStatus.recommended,
      );
    });

    test('최신 이상이면 아무것도 띄우지 않는다', () {
      expect(
        policy.statusFor(const AppVersion(1, 2, 0)),
        AppUpdateStatus.current,
      );
      expect(
        policy.statusFor(const AppVersion(2, 0, 0)),
        AppUpdateStatus.current,
      );
    });

    test('⚠️ 설치 버전을 못 읽었으면 막지 않는다', () {
      // 모르는 것과 낡은 것은 다르다. 모르는 것을 낡았다고 판정하면 버전을
      // 못 읽는 기기의 사용자가 **업데이트를 해도 풀리지 않는 화면**에 갇힌다.
      expect(policy.statusFor(null), AppUpdateStatus.current);
    });
  });

  group('응답 읽기', () {
    test('두 값을 읽는다', () {
      final policy = AppVersionPolicy.of({
        'minimumVersion': '1.1.0',
        'latestVersion': '1.2.0',
      });

      expect(policy?.minimum, const AppVersion(1, 1, 0));
      expect(policy?.latest, const AppVersion(1, 2, 0));
    });

    test('⚠️ 하나라도 못 읽으면 null이다', () {
      // 반쪽 기준으로 판정하면 막아야 할 앱을 통과시키거나 그 반대가 된다.
      expect(AppVersionPolicy.of({'minimumVersion': '1.1.0'}), isNull);
      expect(AppVersionPolicy.of({'latestVersion': '1.2.0'}), isNull);
      expect(AppVersionPolicy.of(null), isNull);
      expect(
        AppVersionPolicy.of({'minimumVersion': '1.1.0', 'latestVersion': 'x'}),
        isNull,
      );
    });
  });
}
