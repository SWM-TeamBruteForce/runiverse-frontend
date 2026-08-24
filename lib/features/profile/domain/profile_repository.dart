import 'package:runiverse/features/profile/domain/profile_summary.dart';

/// 프로필 요약을 가져온다.
///
/// [userId]를 **인자로 받는다.** 저장소에서 꺼내 쓰면 남의 프로필을 열어도
/// 내 것이 나온다 — 본인·타인이 같은 화면을 쓰기 때문에 여기서 갈려야 한다.
abstract interface class ProfileRepository {
  Future<ProfileSummary> fetch(String userId);

}
