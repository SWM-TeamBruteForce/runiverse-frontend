import 'package:runiverse/features/friend/domain/friend_entry.dart';

/// 왜 이 사람을 권하는가. 서버가 주는 것은 둘뿐이다.
enum FriendReason {
  /// 가장 최근 매칭 러닝에서 함께 뛴 사람.
  ranTogether,

  /// 평균 페이스가 운영값(현재 ±20초/km) 안인 사람.
  ///
  /// ⚠️ **상대의 페이스 값은 안 내려온다.** 얼마나 비슷한지는 말할 수 없다.
  similarPace,
}

/// 추천 한 사람.
///
/// ⚠️ **[entry]의 관계는 늘 `none`이다.** 서버가 친구·요청이 오간 사람·나
/// 자신·온보딩 전인 사람을 빼고 준다. 그래서 추천 화면의 버튼은 하나다.
class FriendRecommendation {
  const FriendRecommendation({required this.entry, required this.reason});

  final FriendEntry entry;
  final FriendReason reason;
}
