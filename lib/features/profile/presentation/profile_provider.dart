import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/http_profile_repository.dart';
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
