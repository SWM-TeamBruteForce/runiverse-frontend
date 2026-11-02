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
  const FriendRecommendation({required this.entry, this.reason});

  final FriendEntry entry;

  /// 왜 권하는가. **모르는 값이면 `null`이다.**
  ///
  /// ⚠️ **그 사람을 빼지 않는다.** 운영 설정이 바뀌어 기준이 하나 늘면, 빼는
  /// 쪽은 추천 화면을 통째로 비워 "추천할 러너를 아직 못 찾았어요"라고
  /// 거짓말을 하게 된다. 줄은 세우고 이유 한 줄만 비운다.
  final FriendReason? reason;
}
