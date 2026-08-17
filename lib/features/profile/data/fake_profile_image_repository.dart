import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_repository.dart';

/// 서버 없이 화면을 돌려보기 위한 가짜 저장소.
///
/// 테스트가 쓴다 — `HttpProfileImageRepository`는 실제 HTTP를 부르므로 위젯
/// 테스트에서 쓸 수 없다.
///
/// ⚠️ **`testWidgets` 안에서 `pumpWidget` 전에 기다리면 테스트가 멈춘다.**
/// 가짜 시간 위에서 도는데 [latency]의 타이머를 진행시킬 `pump`가 아직 없다.
/// 미리 사진이 있는 상태를 만들려면 [url]에 직접 넣는다.
class FakeProfileImageRepository implements ProfileImageRepository {
  FakeProfileImageRepository({
    this.latency = const Duration(milliseconds: 600),
    this.failWith,
    this.url,
  });

  /// 응답이 즉시 오면 로딩 표시가 뜨는지 확인할 수 없다.
  /// 테스트에서는 [Duration.zero]를 넣는다.
  final Duration latency;

  /// 실패를 흉내 낼 때 넣는다. `null`이면 성공한다.
  final ProfileImageFailure? failWith;

  /// 지금 사진 주소. `null`이면 올린 적이 없는 사람이다.
  String? url;

  /// 올라간 사진. 무엇이 넘어갔는지 테스트가 확인한다.
  PickedImage? uploaded;

  @override
  Future<String?> fetchUrl() async {
    await Future<void>.delayed(latency);
    _throwIfFailing();
    return url;
  }

  @override
  Future<void> upload(PickedImage image) async {
    await Future<void>.delayed(latency);
    _throwIfFailing();
    uploaded = image;
    // 진짜 저장소는 확정 응답에 주소를 주지 않지만, 여기서는 다음 [fetchUrl]이
    // 새 사진을 답하도록 만들어 둔다 — 화면의 갱신 경로를 그대로 밟게 하려는 것이다.
    url = 'https://example.invalid/${image.path}';
  }

  @override
  Future<void> remove() async {
    await Future<void>.delayed(latency);
    _throwIfFailing();
    url = null;
    uploaded = null;
  }

  void _throwIfFailing() {
    final failure = failWith;
    if (failure != null) throw ProfileImageException(failure);
  }
}
