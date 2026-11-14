/// 위치 말고 다른 권한(신체 활동·알림·iOS 추적 허용)의 결과.
///
/// [LocationAccess]에서 "기기 위치 기능이 꺼짐"만 뺀 모양이다. 패키지의
/// `PermissionStatus`를 그대로 쓰지 않는 이유도 같다 — 패키지 타입이 domain으로
/// 새지 않게 한다.
enum PermissionAccess {
  /// 쓸 수 있다.
  granted,

  /// 허용받지 못했지만 [deniedForever]는 아니다 — 이번에 거절했거나, 창이 안
  /// 떴거나(iOS 추적 허용), 기기가 막아 뒀다(보호자 통제). 안드로이드 12 이하의
  /// 알림은 설정에서 끈 것이라 다시 물을 수 없어도 여기다.
  denied,

  /// 다시 묻지 않기로 했다. **앱에서 물을 방법이 없다** — 설정으로 보내야 한다.
  deniedForever;

  bool get isGranted => this == PermissionAccess.granted;
}
