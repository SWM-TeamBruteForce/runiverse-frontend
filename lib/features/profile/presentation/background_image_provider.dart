import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/http_profile_image_repository.dart';
import 'package:runiverse/features/profile/domain/pending_photo.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_kind.dart';
import 'package:runiverse/features/profile/domain/profile_image_repository.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';

/// 배경 이미지를 다루는 저장소. **프로필 사진과 같은 클래스, 다른 종류**다.
///
/// 3단계 흐름·401 재시도·실패 분류가 통째로 같아서 복제하지 않는다. 갈리는 것은
/// 경로와 필드 이름뿐이고 그것은 [ProfileImageKind]가 들고 있다.
final backgroundImageRepositoryProvider = Provider<ProfileImageRepository>(
  (ref) => HttpProfileImageRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
    kind: ProfileImageKind.background,
  ),
);

final backgroundImageControllerProvider =
    NotifierProvider<BackgroundImageController, ProfileImageState>(
      BackgroundImageController.new,
    );

/// 배경 이미지를 읽고 · 바꾸고 · 지운다.
///
/// ## ⚠️ 왜 `ProfileImageController`를 같이 쓰지 않는가
///
/// 그쪽은 저장소 provider를 **메서드 안에서 직접 `ref.read`** 한다. 종류를 받게
/// 하려면 `family`로 바꾸거나 생성자를 열어야 하는데, 그러면 **이미 돌고 있는
/// 프로필 사진 경로**가 함께 바뀐다. 이 컨트롤러는 얇다 — 3단계도 401 재시도도
/// 실패 분류도 전부 저장소에 있다.
///
/// ## ⚠️ 고르는 길은 함께 쓴다
///
/// [photoPickerProvider]를 그대로 쓴다. 압축 기본값(짧은 변 1080)이 배경에도
/// 맞아서, 종류별 압축 값을 만들 이유가 없다.
class BackgroundImageController extends Notifier<ProfileImageState> {
  @override
  ProfileImageState build() => const ProfileImageLoading();

  ProfileImageRepository get _repository =>
      ref.read(backgroundImageRepositoryProvider);

  /// 주소를 한 번 더 받을 기회가 남았는가 — [retryOnce] 참조.
  var _canRetry = true;

  /// 지금 배경을 물어 상태를 세운다. 화면이 열릴 때 부른다.
  Future<void> load() async {
    _canRetry = true;
    await _fetch();
  }

  /// **깨졌을 때 한 번 더 받는다.**
  ///
  /// 조회 주소는 1시간이면 만료되고, 만료된 주소는 깨진 이미지가 된다. 커버가
  /// 비면 **"배경을 안 올린 사람"과 구분되지 않으므로** 깨짐을 신호로 삼아
  /// 스스로 복구한다.
  ///
  /// ⚠️ **한 번뿐이다.** 서버가 계속 실패를 주거나 주소가 또 만료되면 끝없이
  /// 두드리게 된다. 기회는 [load]와 성공한 [apply]에서만 돌아온다 — 사진을
  /// 바꾸면 그 주소는 새것이라 다음 만료에도 한 번은 받아야 한다.
  Future<void> retryOnce() async {
    if (!_canRetry) return;
    _canRetry = false;
    await _fetch();
  }

  /// **커버가 실제로 그려졌다.** 다음 만료를 메울 기회를 돌려준다.
  ///
  /// ⚠️ **[retryOnce]의 성공으로는 돌려주지 않는다.** 서버는 매번 새 주소를
  /// 주므로, 조회가 되는 한 예산이 계속 풀린다 — 그림이 깨지는 동안 조회 →
  /// 성공 → 다시 받기가 **무한히 돈다.** 그래서 신호는 "주소를 받았다"가
  /// 아니라 **"그림이 나왔다"**여야 한다.
  ///
  /// 이것이 없으면 오래 켜 둔 앱에서 **두 번째 만료부터 커버가 영영 기본
  /// 배경으로 남는다.**
  void markRendered() => _canRetry = true;

  Future<void> _fetch() async {
    try {
      state = ProfileImageReady(url: await _repository.fetchUrl());
    } on ProfileImageException catch (error) {
      state = ProfileImageFailed(error.failure);
    }
  }

  /// 앨범에서 **고르기만 한다. 올리지 않는다.**
  ///
  /// 프로필 사진과 같은 규칙이다 — 고른 것은 화면이 [PendingPhoto]로 들고
  /// 있다가 [apply]로 보낸다. **취소는 실패가 아니다.**
  Future<({PickedImage? image, ProfileImageFailure? failure})> pick() async {
    try {
      return (image: await ref.read(photoPickerProvider).pick(), failure: null);
    } on ProfileImageException catch (error) {
      return (image: null, failure: error.failure);
    }
  }

  /// 들고 있던 변경을 **실제로 보낸다.** 성공하면 `null`.
  Future<ProfileImageFailure?> apply(PendingPhoto photo) => switch (photo) {
    PhotoPicked(:final image) => _busy(() async {
      await _repository.upload(image);
      // 확정 응답에는 키만 온다. 그릴 주소는 다시 물어야 한다.
      return _repository.fetchUrl();
    }),
    PhotoRemoved() => _busy(() async {
      await _repository.remove();
      // 지운 뒤의 답은 `null`이라는 것을 안다. 왕복 한 번을 아낀다.
      return null;
    }),
  };

  /// 도는 동안 [ProfileImageReady.busy]를 켜 두고, 끝나면 새 주소로 세운다.
  ///
  /// **실패하면 원래 상태로 되돌린다** — 네트워크가 잠깐 끊긴 것 때문에 멀쩡한
  /// 배경이 화면에서 사라지면 사용자는 지워진 줄 안다.
  Future<ProfileImageFailure?> _busy(Future<String?> Function() call) async {
    final current = state;
    final before = current is ProfileImageReady
        ? current
        : const ProfileImageReady();

    state = before.copyWith(busy: true);
    try {
      state = ProfileImageReady(url: await call());
      // 새 주소다. 이것이 만료될 때도 한 번은 다시 받아야 한다.
      _canRetry = true;
      return null;
    } on ProfileImageException catch (error) {
      state = before.copyWith(busy: false);
      return error.failure;
    }
  }
}
