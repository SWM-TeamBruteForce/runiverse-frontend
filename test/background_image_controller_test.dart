import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/profile/data/fake_profile_image_repository.dart';
import 'package:runiverse/features/profile/domain/cover_crop.dart';
import 'package:runiverse/features/profile/domain/image_cropper.dart';
import 'package:runiverse/features/profile/domain/pending_photo.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_repository.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';

/// 배경 이미지 상태 — **주소를 언제 다시 받는가.**
///
/// ## ⚠️ 이 값만 스스로 챙겨야 한다
///
/// 프로필 사진 주소는 요약(`GET /users/me`)에 얹혀 오지만 **배경은 요약에
/// 없다.** 조회 주소는 1시간이면 만료되고, 만료된 주소는 깨진 이미지가 된다 —
/// 그런데 커버가 비면 **"배경을 안 올린 사람"과 구분되지 않는다.**
///
/// 그래서 깨짐을 신호로 한 번 더 받는다. **한 번뿐이다** — 서버가 계속 실패를
/// 주면 끝없이 두드린다.
void main() {
  late FakeProfileImageRepository repository;
  late _FakeCropper cropper;

  ProviderContainer makeContainer() {
    repository = FakeProfileImageRepository(latency: Duration.zero);
    cropper = _FakeCropper();
    return ProviderContainer.test(
      overrides: [
        backgroundImageRepositoryProvider.overrideWithValue(repository),
        imageCropperProvider.overrideWithValue(cropper),
      ],
    );
  }

  BackgroundImageController controllerOf(ProviderContainer container) =>
      container.read(backgroundImageControllerProvider.notifier);

  ProfileImageState stateOf(ProviderContainer container) =>
      container.read(backgroundImageControllerProvider);

  PickedImage image() =>
      PickedImage.validated(path: '/tmp/cover.jpg', sizeBytes: 1024);

  test('조회하면 주소를 세운다', () async {
    final container = makeContainer();
    repository.url = 'https://cdn.test/cover.jpg';

    await controllerOf(container).load();

    expect(
      stateOf(container),
      isA<ProfileImageReady>().having(
        (s) => s.url,
        'url',
        'https://cdn.test/cover.jpg',
      ),
    );
  });

  test('⚠️ 올린 적이 없는 것은 실패가 아니다', () async {
    // 대부분이 여기 해당한다. 실패로 섞으면 기본 배경 자리에 오류가 뜬다.
    final container = makeContainer();
    repository.url = null;

    await controllerOf(container).load();

    expect(
      stateOf(container),
      isA<ProfileImageReady>().having((s) => s.url, 'url', isNull),
    );
  });

  test('조회가 실패하면 실패 상태가 된다', () async {
    final container = ProviderContainer.test(
      overrides: [
        backgroundImageRepositoryProvider.overrideWithValue(
          FakeProfileImageRepository(
            latency: Duration.zero,
            failWith: ProfileImageFailure.network,
          ),
        ),
      ],
    );

    await controllerOf(container).load();

    expect(stateOf(container), isA<ProfileImageFailed>());
  });

  test('올리면 새 주소를 다시 받아 세운다', () async {
    // 확정 응답에는 키만 온다 — 그릴 주소는 다시 물어야 한다.
    final container = makeContainer();
    repository.url = 'https://cdn.test/old.jpg';
    await controllerOf(container).load();

    final failure = await controllerOf(container).apply(PhotoPicked(image()));

    expect(failure, isNull);
    expect(repository.uploaded, isNotNull);
    expect(
      stateOf(container),
      isA<ProfileImageReady>().having((s) => s.url, 'url', repository.url),
    );
    expect(repository.url, isNot('https://cdn.test/old.jpg'));
  });

  group('⚠️ 보이던 부분만 올린다', () {
    // 서버에는 위치를 담을 자리가 없다. 미리보기에서 옮긴 위치는 잘라 낸
    // 그림으로만 남는다.

    test('고른 위치대로 커버 비율로 잘라 올린다', () async {
      final container = makeContainer();
      await controllerOf(container).load();

      await controllerOf(container).apply(PhotoPicked(image(), alignY: -0.5));

      expect(cropper.alignY, -0.5);
      expect(cropper.aspectRatio, CoverCrop.aspectRatio);
      expect(repository.uploaded?.path, _FakeCropper.croppedPath);
    });

    test('올리고 나면 자른 파일을 버린다', () async {
      // 저장할 때마다 새로 자른다. 버리지 않으면 임시 폴더에 쌓인다.
      final container = makeContainer();
      await controllerOf(container).load();

      await controllerOf(container).apply(PhotoPicked(image()));

      expect(cropper.discarded, _FakeCropper.croppedPath);
    });

    test('⚠️ 자르지 못하면 올리지 않고 원래 주소를 둔다', () async {
      // 자르지 않은 채로 올리면 보던 것과 다른 그림이 올라간다.
      final container = makeContainer();
      repository.url = 'https://cdn.test/cover.jpg';
      await controllerOf(container).load();
      cropper.failWith = ProfileImageFailure.unsupportedFormat;

      final failure = await controllerOf(container).apply(PhotoPicked(image()));

      expect(failure, ProfileImageFailure.unsupportedFormat);
      expect(repository.uploaded, isNull);
      expect(
        stateOf(container),
        isA<ProfileImageReady>().having(
          (s) => s.url,
          'url',
          'https://cdn.test/cover.jpg',
        ),
      );
    });
  });

  test('기본으로 되돌리면 주소가 비워진다', () async {
    final container = makeContainer();
    repository.url = 'https://cdn.test/cover.jpg';
    await controllerOf(container).load();

    await controllerOf(container).apply(const PhotoRemoved());

    expect(repository.removed, isTrue);
    expect(
      stateOf(container),
      isA<ProfileImageReady>().having((s) => s.url, 'url', isNull),
    );
  });

  test('⚠️ 올리기가 실패해도 원래 주소가 남는다', () async {
    // 네트워크가 잠깐 끊긴 것 때문에 배경이 사라지면 지워진 줄 안다.
    //
    // ⚠️ 조회는 되고 올리기만 실패하는 저장소가 필요하다. 공용 가짜는 실패를
    // 하나로만 들고 있어 조회까지 함께 실패한다.
    final cropper = _FakeCropper();
    final container = ProviderContainer.test(
      overrides: [
        backgroundImageRepositoryProvider.overrideWithValue(
          _UploadFailsRepository('https://cdn.test/cover.jpg'),
        ),
        imageCropperProvider.overrideWithValue(cropper),
      ],
    );
    await controllerOf(container).load();

    final failure = await controllerOf(container).apply(PhotoPicked(image()));

    expect(failure, ProfileImageFailure.upload);
    // 실패해도 자른 파일은 버린다. 다시 누르면 원본에서 새로 자른다.
    expect(cropper.discarded, _FakeCropper.croppedPath);
    expect(
      stateOf(container),
      isA<ProfileImageReady>().having(
        (s) => s.url,
        'url',
        'https://cdn.test/cover.jpg',
      ),
    );
  });

  group('⚠️ 깨졌을 때 다시 받기', () {
    test('한 번은 다시 받는다', () async {
      final container = makeContainer();
      await controllerOf(container).load();
      final before = repository.fetchCalls;

      await controllerOf(container).retryOnce();

      expect(repository.fetchCalls, before + 1);
    });

    test('⚠️ 두 번은 받지 않는다', () async {
      // 만료가 되풀이되면 끝없이 두드린다.
      final container = makeContainer();
      await controllerOf(container).load();
      final before = repository.fetchCalls;

      await controllerOf(container).retryOnce();
      await controllerOf(container).retryOnce();

      expect(repository.fetchCalls, before + 1);
    });

    test('새로 올리면 다시 받을 기회가 돌아온다', () async {
      // 사진을 바꾸면 그 주소는 새것이다. 다음 만료에도 한 번은 받아야 한다.
      final container = makeContainer();
      await controllerOf(container).load();
      await controllerOf(container).retryOnce();
      await controllerOf(container).apply(PhotoPicked(image()));
      final before = repository.fetchCalls;

      await controllerOf(container).retryOnce();

      expect(repository.fetchCalls, before + 1);
    });

    test('⚠️ 그림이 나오면 다음 만료를 메울 기회가 돌아온다', () async {
      // 한 번으로 묶는 것은 **연달아 실패하는** 주소를 끝없이 두드리지 않으려는
      // 것이다. 성공까지 예산으로 세면 오래 켜 둔 앱에서 **두 번째 만료부터는
      // 영영 안 돌아온다** — 배경을 올린 사람에게 기본 단색이 뜬다.
      final container = makeContainer();
      await controllerOf(container).load();
      await controllerOf(container).retryOnce();
      controllerOf(container).markRendered();
      final before = repository.fetchCalls;

      await controllerOf(container).retryOnce();

      expect(repository.fetchCalls, before + 1);
    });

    test('⚠️ 조회가 성공한 것만으로는 기회가 안 돌아온다', () async {
      // 서버는 매번 **새 주소**를 준다. 조회 성공으로 예산을 풀면 그림이 계속
      // 깨지는 동안 조회 → 성공 → 다시 받기가 무한히 돈다.
      final container = makeContainer();
      await controllerOf(container).load();
      await controllerOf(container).retryOnce(); // 성공적으로 새 주소를 받았다
      final before = repository.fetchCalls;

      await controllerOf(container).retryOnce();

      expect(repository.fetchCalls, before);
    });

    test('아직 조회한 적이 없으면 그냥 받는다', () async {
      // 화면이 열리기 전에 이미지가 깨질 일은 없지만, 받은 적이 없는데
      // 막아 버리면 그 세션에서 배경이 영영 안 뜬다.
      final container = makeContainer();

      await controllerOf(container).retryOnce();

      expect(repository.fetchCalls, 1);
    });
  });

  group('⚠️ 앱을 끄지 않고 계정을 바꾸면', () {
    // 이 provider는 로그아웃해도 살아 있다. 다음 사람이 프로필 탭을 열면 첫
    // 화면에 앞 사람의 배경이 뜨고, 앞 사람이 띄운 요청이 늦게 오면 그 배경이
    // 다음 사람 커버에 남는다.
    const firstUrl = 'https://cdn.test/u-1.jpg';
    const nextUrl = 'https://cdn.test/u-2.jpg';
    late _HeldRepository held;
    late ProviderContainer container;
    late _Auth auth;

    setUp(() {
      held = _HeldRepository()..url = firstUrl;
      container = ProviderContainer.test(
        overrides: [
          backgroundImageRepositoryProvider.overrideWithValue(held),
          imageCropperProvider.overrideWithValue(_FakeCropper()),
          authControllerProvider.overrideWith(
            () => _Auth(const AuthSignedIn('u-1', isOnboarded: true)),
          ),
        ],
      );
      auth = container.read(authControllerProvider.notifier) as _Auth;
    });

    /// 로그아웃하고 u-2로 들어온다. 그 뒤 떠난 조회는 u-2의 배경을 받는다.
    void switchToNext() {
      auth.set(const AuthSignedOut(returning: true));
      auth.set(const AuthSignedIn('u-2', isOnboarded: true));
      held.url = nextUrl;
    }

    test('커버가 내려간 뒤 계정을 떠나도 받아 둔 배경을 비운다', () async {
      // 로그아웃하면 탭 화면이 통째로 내려가 이 provider를 지켜보는 곳이 없다.
      // 그래도 계정이 바뀐 것은 받아야 다음 사람의 첫 화면이 비어 있다.
      final cover = container.listen(
        backgroundImageControllerProvider,
        (_, _) {},
      );
      await controllerOf(container).load();
      cover.close();

      switchToNext();

      expect(stateOf(container), isA<ProfileImageLoading>());
    });

    for (final fails in [false, true]) {
      test(
        '⚠️ 바꾸기 전에 떠난 조회가 늦게 ${fails ? '실패해도' : '와도'} 다음 사람 커버에 넣지 않는다',
        () async {
          final hold = held.hold = Completer<void>();
          held.fails = fails;
          final stale = controllerOf(container).load();

          switchToNext();
          hold.complete();
          await stale;

          expect(stateOf(container), isA<ProfileImageLoading>());
        },
      );
    }

    test('⚠️ 다음 사람 배경을 먼저 받은 뒤 앞 사람 답이 와도 덮지 않는다', () async {
      final hold = held.hold = Completer<void>();
      final stale = controllerOf(container).load();
      switchToNext();
      held.hold = null;
      await controllerOf(container).load();

      hold.complete();
      await stale;

      expect(
        stateOf(container),
        isA<ProfileImageReady>().having((s) => s.url, 'url', nextUrl),
      );
    });

    for (final fails in [false, true]) {
      test(
        '⚠️ 바꾸기 전에 보낸 사진 바꾸기가 늦게 ${fails ? '실패해도' : '와도'} 다음 사람 커버에 넣지 않는다',
        () async {
          await controllerOf(container).load();
          final hold = held.hold = Completer<void>();
          held.fails = fails;
          final stale = controllerOf(container).apply(PhotoPicked(image()));
          // 자르기가 끝나 올리기가 실제로 떠난 뒤에 바꾼다.
          await pumpEventQueue();

          switchToNext();
          hold.complete();
          final failure = await stale;

          // 서버가 받아 줬으면 성공이다. 실패는 그대로 알린다.
          expect(failure, fails ? ProfileImageFailure.network : isNull);
          expect(stateOf(container), isA<ProfileImageLoading>());
        },
      );
    }

    test('같은 계정의 프로필만 바뀌면 배경을 비우지 않는다', () async {
      await controllerOf(container).load();
      final shown = stateOf(container);

      auth.set(const AuthSignedIn('u-1', isOnboarded: false));

      expect(stateOf(container), same(shown));
    });

    test('배경을 읽은 뒤에 로그인 상태가 들어와도 비우지 않는다', () async {
      // 스플래시를 건너뛴 화면 테스트가 이 순서다 — 탭이 먼저 읽고 `restore()`가
      // 뒤에 온다. 들어오는 것은 계정을 떠난 것이 아니다.
      auth.set(const AuthUnknown());
      await controllerOf(container).load();
      final shown = stateOf(container);

      auth.set(const AuthSignedIn('u-1', isOnboarded: true));

      expect(stateOf(container), same(shown));
      expect(
        shown,
        isA<ProfileImageReady>().having((s) => s.url, 'url', firstUrl),
      );
    });
  });
}

/// 테스트가 로그인 상태를 바꿔 끼우는 컨트롤러.
class _Auth extends AuthController {
  _Auth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  void set(AuthState next) => state = next;
}

/// 답을 붙잡아 둘 수 있는 저장소.
///
/// 붙잡기·실패·돌려줄 주소는 **요청이 떠날 때** 정해진다. 그래야 앞 사람
/// 요청을 붙잡아 둔 채 다음 사람 요청을 먼저 끝낼 수 있다.
class _HeldRepository implements ProfileImageRepository {
  /// 조회가 돌려줄 주소.
  String? url;

  /// 있으면 그때 떠난 요청이 이것을 기다린다.
  Completer<void>? hold;

  /// 참이면 그때 떠난 요청이 기다린 뒤 실패한다.
  var fails = false;

  Future<void> _wait() async {
    final waitFor = hold;
    final failing = fails;
    if (waitFor != null) await waitFor.future;
    if (failing) {
      throw const ProfileImageException(ProfileImageFailure.network);
    }
  }

  @override
  Future<String?> fetchUrl() async {
    final answer = url;
    await _wait();
    return answer;
  }

  @override
  Future<void> upload(PickedImage image) => _wait();

  @override
  Future<void> remove() => _wait();
}

/// 자르지 않고 **받은 값만 기록하는** 가짜.
///
/// 진짜는 JPEG로 바꾸는 데 플랫폼 플러그인을 써서 테스트 환경에 없다.
class _FakeCropper implements ImageCropper {
  static const croppedPath = '/tmp/cropped.jpg';

  double? alignY;
  double? aspectRatio;

  /// 있으면 자르지 못한 것처럼 던진다.
  ProfileImageFailure? failWith;

  @override
  Future<PickedImage> crop(
    PickedImage image, {
    required double aspectRatio,
    required double alignY,
  }) async {
    this.alignY = alignY;
    this.aspectRatio = aspectRatio;
    final failure = failWith;
    if (failure != null) throw ProfileImageException(failure);
    return PickedImage.validated(path: croppedPath, sizeBytes: 512);
  }

  /// 버린 파일 경로.
  String? discarded;

  @override
  Future<void> discard(PickedImage cropped) async => discarded = cropped.path;
}

/// 조회는 되고 **올리기만 실패하는** 저장소.
///
/// 공용 가짜는 실패를 하나로만 들고 있어 조회까지 함께 실패한다. 그러면
/// "올리기가 실패해도 원래 주소가 남는가"를 물을 수 없다 — 애초에 주소를
/// 세우지 못하기 때문이다.
class _UploadFailsRepository implements ProfileImageRepository {
  _UploadFailsRepository(this._url);

  final String _url;

  @override
  Future<String?> fetchUrl() async => _url;

  @override
  Future<void> upload(PickedImage image) async =>
      throw const ProfileImageException(ProfileImageFailure.upload);

  @override
  Future<void> remove() async =>
      throw const ProfileImageException(ProfileImageFailure.upload);
}
