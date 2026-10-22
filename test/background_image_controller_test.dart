import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/profile/data/fake_profile_image_repository.dart';
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

  ProviderContainer makeContainer() {
    repository = FakeProfileImageRepository(latency: Duration.zero);
    return ProviderContainer.test(
      overrides: [
        backgroundImageRepositoryProvider.overrideWithValue(repository),
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
    final container = ProviderContainer.test(
      overrides: [
        backgroundImageRepositoryProvider.overrideWithValue(
          _UploadFailsRepository('https://cdn.test/cover.jpg'),
        ),
      ],
    );
    await controllerOf(container).load();

    final failure = await controllerOf(container).apply(PhotoPicked(image()));

    expect(failure, ProfileImageFailure.upload);
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

    test('아직 조회한 적이 없으면 그냥 받는다', () async {
      // 화면이 열리기 전에 이미지가 깨질 일은 없지만, 받은 적이 없는데
      // 막아 버리면 그 세션에서 배경이 영영 안 뜬다.
      final container = makeContainer();

      await controllerOf(container).retryOnce();

      expect(repository.fetchCalls, 1);
    });
  });
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
