import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
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
    this.nicknameFailure,
    this.editFailure,
  });

  final String? nickname;
  final String? profileImageUrl;
  final String? introduction;
  final int friendCount;

  /// 주면 그 이유로 실패한다. **서버가 아직 없는 상황**을 만드는 데 쓴다.
  final ProfileFailure? failure;

  /// 주면 닉네임 변경이 그 이유로 실패한다.
  final NicknameChangeFailure? nicknameFailure;

  /// 주면 프로필 수정이 그 이유로 실패한다.
  final ProfileEditFailure? editFailure;

  /// 몇 번 불렸는가. 부르지 말아야 할 때 부르지 않는지 보는 데 쓴다.
  var calls = 0;

  /// 마지막으로 바꾸라고 받은 이름. **보낸 값이 맞는지** 보는 데 쓴다.
  String? changedTo;

  /// 중복확인이 무엇이라 답할지. `null`이면 "물어보지 못했다"가 된다.
  bool? available = true;

  /// 중복확인을 몇 번 물었는가. **묻지 말아야 할 때 묻지 않는지** 보는 데 쓴다.
  var availabilityCalls = 0;

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

  @override
  Future<bool?> isNicknameAvailable(String nickname) async {
    availabilityCalls++;
    return available;
  }

  @override
  Future<String> changeNickname(String nickname) async {
    changedTo = nickname;
    final reason = nicknameFailure;
    if (reason != null) throw NicknameChangeException(reason);
    // 서버는 확정한 값을 돌려준다. 가짜도 그렇게 군다 — 화면이 **응답을**
    // 쓰는지 **보낸 값을** 쓰는지가 테스트에서 갈리지 않으면 의미가 없다.
    return nickname;
  }
}
