/// 좌표의 동네 이름을 주는 곳.
abstract interface class PlaceRepository {
  /// [latitude]·[longitude]의 동네 이름(`서울 중구`). 모르면 `null`, 실패하면 던진다.
  Future<String?> nameOf({required double latitude, required double longitude});
}
