import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/profile/data/http_profile_image_repository.dart';
import 'package:runiverse/features/profile/data/ui_image_cropper.dart';
import 'package:runiverse/features/profile/domain/cover_crop.dart';
import 'package:runiverse/features/profile/domain/image_cropper.dart';
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
    ref.watch(tokenRefresherProvider),
    kind: ProfileImageKind.background,
  ),
);

/// 저장할 때 **보이는 부분만 잘라 낸다.**
///
/// ⚠️ **위젯 테스트는 이것을 override해야 한다.** JPEG로 바꾸는 것은 플랫폼
/// 플러그인이라 테스트 환경에서 `MissingPluginException`이 난다.
final imageCropperProvider = Provider<ImageCropper>(
  (ref) => const UiImageCropper(),
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
  /// 계정 차수. 계정을 떠날 때마다 올라간다 — 그 전에 떠난 요청의 답을 가린다.
  ///
  /// ⚠️ 답을 받아 [state]를 바꾸는 곳은 모두 이것부터 본다.
  var _accountEpoch = 0;

  @override
  ProfileImageState build() {
    // ⚠️ **계정을 떠나면 차수를 올리고 들고 있던 주소를 버린다.** 이 provider는
    // 로그아웃해도 살아 있어서, 다음 사람이 프로필 탭을 열면 첫 화면에 앞 사람의
    // 배경이 뜬다 — 새로 묻는 것은 그 화면이 그려진 뒤다.
    //
    // 들어올 때(로그아웃 → 계정)는 비우지 않는다. 떠날 때 이미 비웠다.
    ref.listen(
      authControllerProvider.select(
        (auth) => auth is AuthSignedIn ? auth.userId : null,
      ),
      (previous, _) {
        if (previous == null) return;
        _accountEpoch++;
        state = const ProfileImageLoading();
      },
    );
    return const ProfileImageLoading();
  }

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
    final epoch = _accountEpoch;
    try {
      final url = await _repository.fetchUrl();
      // ⚠️ 기다리는 사이 계정을 떠났으면 앞 사람의 배경이다. 커버에 남기지 않는다.
      if (epoch != _accountEpoch) return;
      state = ProfileImageReady(url: url);
    } on ProfileImageException catch (error) {
      if (epoch != _accountEpoch) return;
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
    PhotoPicked(:final image, :final alignY) => _busy(() async {
      // ⚠️ **보이던 부분만 올린다.** 서버에는 위치를 담을 자리가 없어서,
      // 미리보기에서 옮긴 위치는 잘라 낸 그림으로만 남는다.
      final cropper = ref.read(imageCropperProvider);
      final cropped = await cropper.crop(
        image,
        aspectRatio: CoverCrop.aspectRatio,
        alignY: alignY,
      );
      try {
        await _repository.upload(cropped);
      } finally {
        // 다시 누르면 원본에서 새로 자른다. 자른 파일은 남겨 둘 이유가 없다.
        await cropper.discard(cropped);
      }
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
    final epoch = _accountEpoch;
    final current = state;
    final before = current is ProfileImageReady
        ? current
        : const ProfileImageReady();

    state = before.copyWith(busy: true);
    try {
      final url = await call();
      // ⚠️ 기다리는 사이 계정을 떠났으면 바뀐 것은 앞 사람 배경이다. 다음 사람
      // 커버에 얹지 않는다. 서버는 받아 줬으니 성공으로 돌려준다.
      if (epoch != _accountEpoch) return null;
      state = ProfileImageReady(url: url);
      // 새 주소다. 이것이 만료될 때도 한 번은 다시 받아야 한다.
      _canRetry = true;
      return null;
    } on ProfileImageException catch (error) {
      // 계정을 떠났으면 되돌릴 원래 상태도 앞 사람 것이다.
      if (epoch == _accountEpoch) state = before.copyWith(busy: false);
      return error.failure;
    }
  }
}
