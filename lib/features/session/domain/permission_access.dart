/// 위치 말고 러닝이 묻는 권한(신체 활동·알림)의 결과.
///
/// [LocationAccess]에서 "기기 위치 기능이 꺼짐"만 뺀 모양이다. 패키지의
/// `PermissionStatus`를 그대로 쓰지 않는 이유도 같다 — 패키지 타입이 domain으로
/// 새지 않게 한다.
enum PermissionAccess {
  /// 쓸 수 있다.
  granted,

  /// 이번에 거절했다. 다시 물을 수 있다.
  denied,

  /// 다시 묻지 않기로 했다. **앱에서 물을 방법이 없다** — 설정으로 보내야 한다.
  deniedForever;

  bool get isGranted => this == PermissionAccess.granted;
}
