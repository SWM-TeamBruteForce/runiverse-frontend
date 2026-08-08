import 'package:runiverse/features/onboarding/domain/onboarding_profile.dart';
import 'package:runiverse/features/onboarding/domain/pace_level.dart';

/// `POST /users/onboarding`이 받는 몸통.
///
/// ## 앱과 서버가 다른 곳을 여기서만 메운다
///
/// 화면과 도메인은 앱의 사정대로 두고, **경계인 여기서만** 서버 규격으로 옮긴다.
/// 그래야 서버가 규격을 바꿔도 고칠 곳이 한 군데다.
///
/// 지금 메우는 차이는 셋이다 — 성별 표기, 날짜 형식, 그리고 페이스 필수 여부.
class OnboardingProfileDto {
  const OnboardingProfileDto({
    required this.nickname,
    required this.gender,
    required this.birthday,
    required this.averagePaceSecondsPerKm,
    required this.height,
    required this.weight,
  });

  /// 서버가 평균 페이스를 **필수**로 받아서, 재본 적 없는 사람에게 쓸 값.
  ///
  /// 앱 휠의 최대치(12분/km)다. 서버 허용 범위(120~1800초) 안에 있다.
  ///
  /// ⚠️ **서버가 nullable로 바뀌면 이 상수와 아래 `??`를 지운다.** 그때까지는
  /// 서버가 아는 값(720)과 앱이 보여주는 색(미정 코럴)이 다르다.
  static const unmeasuredPace = PaceRule.maxMinutes * 60; // 720

  final String nickname;
  final String gender;
  final String birthday;
  final int averagePaceSecondsPerKm;
  final int height;
  final int weight;

  factory OnboardingProfileDto.from(OnboardingProfile profile) =>
      OnboardingProfileDto(
        nickname: profile.nickname,
        gender: profile.gender.wireValue,
        birthday: _formatDate(profile.birthday),
        averagePaceSecondsPerKm: profile.paceSecondsPerKm ?? unmeasuredPace,
        height: profile.heightCm,
        weight: profile.weightKg,
      );

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'gender': gender,
    'birthday': birthday,
    'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
    'height': height,
    'weight': weight,
  };

  /// 서버 `LocalDate`가 받는 `yyyy-MM-dd`.
  ///
  /// 한 자리 월·일에 0을 채우지 않으면 파싱에 실패한다.
  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
