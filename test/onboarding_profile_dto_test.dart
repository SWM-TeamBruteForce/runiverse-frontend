import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/onboarding/data/onboarding_profile_dto.dart';
import 'package:runiverse/features/onboarding/domain/gender.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';

/// 프로필 직렬화 — 앱의 값이 서버 규격으로 어떻게 옮겨지는가.
///
/// 순수 함수라 위젯 없이 테스트한다. 여기서 지키는 것은
/// **화면은 `null`을 유지하고 전송할 때만 720으로 바뀐다**는 규칙이다.
void main() {
  OnboardingProfile profileWith({int? pace}) => OnboardingProfile(
    nickname: '러너42',
    gender: Gender.male,
    birthday: DateTime(1998, 4, 12),
    paceSecondsPerKm: pace,
    heightCm: 172,
    weightKg: 63,
  );

  test('성별은 대문자 영문으로 나간다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    expect(json['gender'], 'MALE');
  });

  test('여성도 서버 표기로 옮겨진다', () {
    final json = OnboardingProfileDto.from(
      OnboardingProfile(
        nickname: '러너42',
        gender: Gender.female,
        birthday: DateTime(1998, 4, 12),
        paceSecondsPerKm: 330,
        heightCm: 165,
        weightKg: 55,
      ),
    ).toJson();

    expect(json['gender'], 'FEMALE');
  });

  test('생년월일은 yyyy-MM-dd로 나간다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    // 한 자리 월·일에 0을 채우지 않으면 서버가 파싱하지 못한다.
    expect(json['birthday'], '1998-04-12');
  });

  test('페이스를 잰 사람은 그 값이 그대로 나간다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    expect(json['averagePaceSecondsPerKm'], 330);
  });

  test('페이스를 건너뛰면 1800으로 바뀌어 나간다', () {
    final json = OnboardingProfileDto.from(profileWith()).toJson();

    // 서버가 이 필드를 필수로 받는다. 화면은 null을 그대로 들고 있고
    // 여기서만 바꾼다 — 서버가 nullable이 되면 이 규칙만 지우면 된다.
    //
    // 값은 **서버 허용 범위의 상한**이다. 휠 최대치(720)를 쓰면 "12분/km로
    // 달리는 사람"이라는 실제 값처럼 읽히지만, 상한은 재본 적 없다는 표시로
    // 읽힌다 — 서버가 이후 자동 갱신하는 값이라 시작점이 낮을수록 손해다.
    expect(json['averagePaceSecondsPerKm'], 1800);
  });

  test('치환값은 서버가 받는 범위 안이다', () {
    final json = OnboardingProfileDto.from(profileWith()).toJson();
    final pace = json['averagePaceSecondsPerKm'] as int;

    // 서버 검증은 120~1800이다. 치환값이 그 밖으로 나가면 400을 받는다.
    expect(pace, greaterThanOrEqualTo(120));
    expect(pace, lessThanOrEqualTo(1800));
  });

  test('키와 몸무게는 서버 필드명으로 나간다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    // ⚠️ 서버가 받는 이름은 `heightCm`·`weightKg`다. `height`·`weight`로 보내면
    // 서버는 **필수 필드가 비었다고 보고 400으로 거절한다** —
    // "키는 필수입니다. 몸무게는 필수입니다." 실제로 그렇게 막혔다.
    expect(json['heightCm'], 172);
    expect(json['weightKg'], 63);
    expect(json.containsKey('height'), isFalse);
    expect(json.containsKey('weight'), isFalse);
  });

  test('보내는 키는 서버가 아는 여섯 개뿐이다', () {
    final json = OnboardingProfileDto.from(profileWith(pace: 330)).toJson();

    // 모르는 키를 얹으면 서버 설정에 따라 400이 날 수 있다.
    expect(json.keys.toSet(), {
      'nickname',
      'gender',
      'birthday',
      'averagePaceSecondsPerKm',
      'heightCm',
      'weightKg',
    });
  });
}
