import 'package:runiverse/features/onboarding/domain/gender.dart';

/// 프로필 등록(S04)에서 모은 값.
///
/// 순수 Dart다. 화면이 어떻게 모았는지(휠 시트인지 인라인 칩인지)를 여기서 알 필요가 없다.
class OnboardingProfile {
  const OnboardingProfile({
    required this.nickname,
    required this.gender,
    required this.birthday,
    required this.paceSecondsPerKm,
    required this.heightCm,
    required this.weightKg,
  });

  final String nickname;
  final Gender gender;
  final DateTime birthday;

  /// 1km당 초. **`null`은 '미측정'이지 '아직 안 물어봄'이 아니다.**
  ///
  /// 서버는 이 값을 필수로 받는다. 그 차이는 DTO에서 메운다 —
  /// 화면과 시그니처 컬러는 `null`을 그대로 본다.
  final int? paceSecondsPerKm;

  final int heightCm;
  final int weightKg;
}
