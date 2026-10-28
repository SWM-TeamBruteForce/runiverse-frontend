import 'package:runiverse/features/friend/domain/friend_entry.dart';

/// 한 번에 받은 목록과, 이어 읽을 자리.
class FriendPage {
  const FriendPage({required this.items, this.nextCursor});

  const FriendPage.empty() : items = const [], nextCursor = null;

  final List<FriendEntry> items;

  /// 다음 페이지 커서. 마지막 페이지면 `null`이다.
  ///
  /// ⚠️ **내용을 해석하지 않는다.** 서버가 준 값을 그대로 돌려보낸다. 직접
  /// 만들거나 다른 목록에서 받은 커서를 섞으면 `400`이다.
  final String? nextCursor;
}
