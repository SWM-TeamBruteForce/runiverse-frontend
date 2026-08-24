import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/http_profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/domain/profile_failure.dart';
import 'package:runiverse/features/profile/domain/profile_repository.dart';
import 'package:runiverse/features/profile/domain/profile_summary.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => HttpProfileRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);

/// 서버에서 **읽을 수 없는** 신체 정보. 앱을 켜 둔 동안만 남는다.
///
/// ## 왜 기기에 저장하지 않나
///
/// 생년월일·키·몸무게를 주는 조회 API가 없다(36번은 `userId`·`nickname`·
/// `isOnboarded`뿐, 37번에도 없다). 기기에 영구 저장하면 **서버와 다른 진실이
/// 하나 더 생기고**, 다른 기기에서 값을 바꿨을 때 이쪽이 틀렸다는 것을 알 방법이
/// 없다. 방금 바꾼 값만 화면에 남기고, 앱을 다시 켜면 모르는 상태로 돌아간다.
///
/// ⚠️ 36번에 이 셋을 실어 달라고 요청하는 것이 진짜 해법이다. 붙으면 이 클래스는
/// [ProfileSummary]로 흡수된다.
class ProfileBody {
  const ProfileBody({this.birthday, this.heightCm, this.weightKg});

  final DateTime? birthday;
  final int? heightCm;
  final int? weightKg;
}

final profileBodyProvider =
    NotifierProvider<ProfileBodyController, ProfileBody>(
      ProfileBodyController.new,
    );

class ProfileBodyController extends Notifier<ProfileBody> {
  @override
  ProfileBody build() => const ProfileBody();

  /// 방금 저장에 성공한 값만 덮어쓴다. **주지 않은 것은 건드리지 않는다** —
  /// 부분 수정이라 안 보낸 필드는 서버에서도 그대로다.
  void remember({DateTime? birthday, int? heightCm, int? weightKg}) {
    state = ProfileBody(
      birthday: birthday ?? state.birthday,
      heightCm: heightCm ?? state.heightCm,
      weightKg: weightKg ?? state.weightKg,
    );
  }
}

/// 화면이 보는 상태.
///
/// `loading`을 따로 두지 않는다. **저장해 둔 값이 그 자리를 대신하기** 때문이다 —
/// 탭을 열자마자 지난번 닉네임이 보이고, 서버 응답이 오면 덮인다.
class ProfileSummaryState {
  const ProfileSummaryState({this.summary, this.failure, this.loading = false});

  final ProfileSummary? summary;

  /// 마지막 실패. 화면은 지금 이 값으로 갈라지지 않지만,
  /// 무엇이 실패했는지 모르면 나중에 쫓기 어렵다.
  final ProfileFailure? failure;

  final bool loading;
}

final profileSummaryControllerProvider =
    NotifierProvider<ProfileSummaryController, ProfileSummaryState>(
      ProfileSummaryController.new,
    );

/// 프로필 요약을 가져온다.
///
/// ## ⚠️ 서버가 실패해도 비우지 않는다
///
/// `GET /users/{userId}`는 명세상 아직 `개발중`이다. 배포 전에는 404나 500이
/// 오는데, 그때 화면을 비우면 **어제까지 보이던 닉네임이 사라진다.**
/// `/users/me`가 남긴 캐시가 그 자리를 지킨다.
class ProfileSummaryController extends Notifier<ProfileSummaryState> {
  @override
  ProfileSummaryState build() => const ProfileSummaryState();

  Future<void> load() async {
    final stored = await ref.read(tokenStoreProvider).read();
    final userId = stored.userId;
    if (userId == null) return;

    // 먼저 저장해 둔 값으로 그린다. 서버를 기다리는 동안 빈 화면을 보이지 않는다.
    final cached = _cached(userId, stored);
    state = ProfileSummaryState(summary: cached, loading: true);

    try {
      final summary = await ref.read(profileRepositoryProvider).fetch(userId);
      state = ProfileSummaryState(summary: summary);
    } on ProfileException catch (error) {
      state = ProfileSummaryState(summary: cached, failure: error.failure);
    }
  }

  /// 사진을 바꾸거나 지운 뒤 다시 부른다. **새 주소는 서버만 안다.**
  Future<void> reload() => load();

  /// 소개글·신체 정보를 한 번에 저장한다. 실패하면 그 이유를 준다.
  ///
  /// 성공하면 소개글은 화면·저장값에, 신체 정보는 [profileBodyProvider]에
  /// 남긴다. **51번 응답은 보낸 필드만 돌려주므로** 요약을 다시 받을 일이 없다.
  Future<ProfileEditFailure?> saveProfile({
    String? introduction,
    DateTime? birthday,
    int? heightCm,
    int? weightKg,
  }) async {
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            introduction: introduction,
            birthday: birthday,
            heightCm: heightCm?.toDouble(),
            weightKg: weightKg?.toDouble(),
          );
    } on ProfileEditException catch (error) {
      return error.failure;
    }

    ref
        .read(profileBodyProvider.notifier)
        .remember(birthday: birthday, heightCm: heightCm, weightKg: weightKg);

    if (introduction != null) await _applyIntroduction(introduction);
    return null;
  }

  /// 소개글을 화면과 저장값에 반영한다. **빈 문자열은 지운 것**이다.
  Future<void> _applyIntroduction(String introduction) async {
    final saved = introduction.isEmpty ? null : introduction;

    final store = ref.read(tokenStoreProvider);
    final stored = await store.read();
    final userId = stored.userId;
    if (userId != null) {
      await store.saveCurrentUser(
        userId: userId,
        isOnboarded: stored.isOnboarded,
        nickname: stored.nickname,
        profileImageUrl: stored.profileImageUrl,
        introduction: saved,
      );
    }

    final summary = state.summary;
    if (summary == null) return;
    state = ProfileSummaryState(
      summary: ProfileSummary(
        userId: summary.userId,
        nickname: summary.nickname,
        profileImageUrl: summary.profileImageUrl,
        introduction: saved,
        friendCount: summary.friendCount,
      ),
      failure: state.failure,
    );
  }

  /// 저장해 둔 `/users/me` 값을 화면이 쓸 모양으로 되살린다.
  ///
  /// 셋 다 비었으면 `null`을 준다 — 빈 껍데기를 주면 "받아왔는데 비어 있다"와
  /// "아직 못 받았다"가 구별되지 않는다.
  ProfileSummary? _cached(String userId, StoredAuth stored) {
    if (stored.nickname == null &&
        stored.profileImageUrl == null &&
        stored.introduction == null) {
      return null;
    }
    return ProfileSummary(
      userId: userId,
      nickname: stored.nickname,
      profileImageUrl: stored.profileImageUrl,
      introduction: stored.introduction,
      // 캐시에는 없는 값이다. `/users/me`가 주지 않는다.
      friendCount: 0,
    );
  }
}
