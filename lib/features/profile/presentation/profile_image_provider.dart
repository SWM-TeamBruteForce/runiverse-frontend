import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/profile/data/gallery_photo_picker.dart';
import 'package:runiverse/features/profile/data/http_profile_image_repository.dart';
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_repository.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';

/// ⚠️ **이 파일은 `presentation`에 있으면서 `data`를 import한다.** 의존 방향
/// (`presentation → domain ← data`)의 예외인데, 구현체를 고르는 일은 어딘가에서
/// 반드시 해야 하고 그 자리가 여기다 — `onboarding_provider.dart`와 같은 규칙이다.
/// 화면 파일은 여전히 `data`를 모른다.
final profileImageRepositoryProvider = Provider<ProfileImageRepository>(
  (ref) => HttpProfileImageRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(authRepositoryProvider),
  ),
);

/// 사진을 어디서 고르는가.
///
/// ⚠️ **위젯 테스트는 이것을 override해야 한다.** 앨범을 여는 것은 플랫폼 채널이라
/// 테스트 환경에서 `MissingPluginException`이 난다.
final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => const GalleryPhotoPicker(),
);

final profileImageControllerProvider =
    NotifierProvider<ProfileImageController, ProfileImageState>(
      ProfileImageController.new,
    );

/// 프로필 사진을 읽고 · 바꾸고 · 지운다.
///
/// ## 스스로 불러오지 않는다
///
/// [build]는 [ProfileImageLoading]만 세우고 서버를 부르지 않는다. 화면이 열릴 때
/// [load]를 부른다 — 열람 주소는 **만료되는 값**이라 화면이 열리는 시점에 받아야
/// 하고, 그 시점을 아는 것은 화면이다.
///
/// ## 실패를 던지지 않고 돌려준다
///
/// [change]·[remove]는 성공하면 `null`, 실패하면 이유를 돌려준다.
/// `AuthController`와 같은 규칙이다 — 잡는 곳을 화면 하나로 모은다.
class ProfileImageController extends Notifier<ProfileImageState> {
  @override
  ProfileImageState build() => const ProfileImageLoading();

  ProfileImageRepository get _repository =>
      ref.read(profileImageRepositoryProvider);

  /// 지금 사진을 물어 상태를 세운다. 화면이 열릴 때 부른다.
  Future<void> load() async {
    try {
      state = ProfileImageReady(url: await _repository.fetchUrl());
    } on ProfileImageException catch (error) {
      state = ProfileImageFailed(error.failure);
    }
  }

  /// 앨범에서 골라 바꾼다. 성공하면 `null`.
  ///
  /// **취소해도 `null`을 돌려준다.** 취소는 실패가 아니라 아무 일도 일어나지
  /// 않은 것이다 — 여기서 이유를 돌려주면 화면이 스낵바를 띄운다.
  Future<ProfileImageFailure?> change() async {
    final PickedImage? picked;
    try {
      picked = await ref.read(photoPickerProvider).pick();
    } on ProfileImageException catch (error) {
      // 형식·크기가 조건에 맞지 않다. 서버에 가기 전에 걸린 것이다.
      return error.failure;
    }
    if (picked == null) return null;

    final image = picked;
    return _busy(() async {
      await _repository.upload(image);
      // 확정 응답에는 키만 온다. 그릴 주소는 다시 물어야 한다.
      return _repository.fetchUrl();
    });
  }

  /// 지우고 기본 이미지로 돌아간다. 성공하면 `null`.
  Future<ProfileImageFailure?> remove() => _busy(() async {
    await _repository.remove();
    // 지운 뒤의 답은 `null`이라는 것을 안다. 왕복 한 번을 아낀다.
    return null;
  });

  /// 도는 동안 [ProfileImageReady.busy]를 켜 두고, 끝나면 새 주소로 세운다.
  ///
  /// ## 실패하면 **원래 상태로 되돌린다**
  ///
  /// 사진을 지우거나 [ProfileImageFailed]로 넘기지 않는다. 네트워크가 잠깐 끊긴
  /// 것 때문에 멀쩡히 있는 사진이 화면에서 사라지면, 사용자는 사진이 지워진 줄 안다.
  ///
  /// ⚠️ **올리기가 성공하고 주소 조회만 실패해도 실패로 보고한다.** 서버에는 이미
  /// 저장됐는데 화면은 옛 사진을 그린다. 한 번 더 올리면 맞춰지고, 그때 남는 것은
  /// 쓰이지 않는 S3 객체 하나뿐이라 여기서 더 붙잡지 않는다.
  Future<ProfileImageFailure?> _busy(Future<String?> Function() call) async {
    final current = state;
    final before = current is ProfileImageReady
        ? current
        : const ProfileImageReady();

    state = before.copyWith(busy: true);
    try {
      state = ProfileImageReady(url: await call());
      return null;
    } on ProfileImageException catch (error) {
      state = before.copyWith(busy: false);
      return error.failure;
    }
  }
}
