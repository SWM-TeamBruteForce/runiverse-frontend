/// 워치에 보낼 파티원 사진을 만든다. 모양은 워치 레포 `docs/phone-communication.md`
/// 「상태」의 `WATCH_SYNCED`에만 있는 `photos` 가 정본이다.
abstract interface class WatchPhotoMaker {
  /// [url] 의 사진을 가운데 정사각으로 잘라 128×128 JPEG로 줄인 base64.
  ///
  /// 못 받거나 못 풀면 던진다. 부르는 쪽은 그 사람을 빼고 보낸다 — 워치는 사진이
  /// 없는 사람을 첫 글자로 그린다.
  Future<String> jpegBase64(String url);
}
