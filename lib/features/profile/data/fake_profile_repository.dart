import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/domain/profile_failure.dart';
import 'package:runiverse/features/profile/domain/profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_summary.dart';

/// 서버 없이 화면과 상태 전이를 돌려보기 위한 가짜.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.nickname,
    this.profileImageUrl,
    this.introduction,
    this.friendCount = 0,
    this.failure,
    this.editFailure,
  });

  final String? nickname;
  final String? profileImageUrl;
  final String? introduction;
  final int friendCount;

  /// 주면 그 이유로 실패한다. **서버가 아직 없는 상황**을 만드는 데 쓴다.
  final ProfileFailure? failure;

  /// 주면 프로필 수정이 그 이유로 실패한다.
  final ProfileEditFailure? editFailure;

  /// 몇 번 불렸는가. 부르지 말아야 할 때 부르지 않는지 보는 데 쓴다.
  var calls = 0;

  @override
  Future<ProfileSummary> fetch(String userId) async {
    calls++;
    final reason = failure;
    if (reason != null) throw ProfileException(reason);
    return ProfileSummary(
      userId: userId,
      nickname: nickname,
      profileImageUrl: profileImageUrl,
      introduction: introduction,
      friendCount: friendCount,
    );
  }

  /// 마지막으로 받은 수정 요청. **무엇을 보냈고 무엇을 뺐는지** 보는 데 쓴다.
  Map<String, Object?>? updated;

  @override
  Future<void> updateProfile({
    String? introduction,
    DateTime? birthday,
    double? weightKg,
    double? heightCm,
  }) async {
    updated = {
      'introduction': ?introduction,
      'birthday': ?birthday,
      'weightKg': ?weightKg,
      'heightCm': ?heightCm,
    };
    final reason = editFailure;
    if (reason != null) throw ProfileEditException(reason);
  }
}
