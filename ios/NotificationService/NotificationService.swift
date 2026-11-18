import Intents
import UserNotifications

/// 대기방 채팅 푸시(`ROOM_CHAT_SENT`)에 보낸 사람 이름·사진을 붙인다(커뮤니케이션 알림).
///
/// 서버가 채팅 푸시에 `mutable-content`를 켜서 OS가 띄우기 전에 여기를 거친다(FcmPushClient).
/// 안드로이드 `android_chat_notifications.dart`와 같은 모양을 iOS 방식으로 만든다.
///
/// ```
/// 19:30 - 5 km 러닝
/// (사진) 철수   곧 출발해요
/// (아이콘) 안내 영희님이 들어왔어요
/// ```
///
/// - 방 이름은 알림 제목(`19:30 - 5 km 러닝`)을 그대로 쓴다. 같은 방은 `thread-id`로 묶인다.
/// - 들어온 줄은 보낸 사람 자리에 "안내" + 안내 아이콘을 둔다(안드로이드 `chatPushNoticeSender`).
/// - 사진 주소는 1시간 뒤 만료된다. 못 받으면 사진 없이 띄운다 — OS가 이름 첫 글자로 그린다.
/// - 채팅 푸시가 아니거나 값이 빠졌으면 받은 그대로 띄운다.
final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var original: UNNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    original = request.content

    let content = request.content
    let data = content.userInfo
    guard data["type"] as? String == "ROOM_CHAT_SENT",
          let runningRoomId = data["runningRoomId"] as? String,
          let chatType = data["chatType"] as? String,
          let actorId = data["actorId"] as? String,
          let actorNickname = data["actorNickname"] as? String
    else {
      finish(content)
      return
    }

    let joined = chatType == "JOINED"
    let photoUrl = joined ? nil : (data["actorProfileImageUrl"] as? String).flatMap(URL.init(string:))
    Self.loadPhoto(photoUrl) { [weak self] photo in
      let sender = joined
        ? Self.person(id: Self.noticeId, name: Self.noticeName, image: Self.noticeImage)
        : Self.person(id: actorId, name: actorNickname, image: photo)
      self?.finish(Self.communication(content, sender: sender, roomId: runningRoomId))
    }
  }

  /// 시간이 다 됐다. 사진을 기다리지 않고 받은 그대로 띄운다.
  override func serviceExtensionTimeWillExpire() {
    if let original { finish(original) }
  }

  private let lock = NSLock()

  // 한 번만 넘긴다 — 사진 콜백과 시간 만료가 다른 스레드에서 같이 들어올 수 있다.
  private func finish(_ content: UNNotificationContent) {
    lock.lock()
    let handler = contentHandler
    contentHandler = nil
    lock.unlock()
    handler?(content)
  }

  // ⚠️ 방 이름이 제목으로 보이는지(받는 사람이 둘 이상이어야 묶음 대화로 그린다)는 실기기로 확인한다.
  private static func communication(
    _ content: UNNotificationContent,
    sender: INPerson,
    roomId: String
  ) -> UNNotificationContent {
    let me = INPerson(
      personHandle: INPersonHandle(value: "me", type: .unknown),
      nameComponents: nil,
      displayName: nil,
      image: nil,
      contactIdentifier: nil,
      customIdentifier: "me",
      isMe: true
    )
    let intent = INSendMessageIntent(
      recipients: [me, sender],
      outgoingMessageType: .outgoingMessageText,
      content: content.body,
      speakableGroupName: INSpeakableString(spokenPhrase: content.title),
      conversationIdentifier: roomId,
      serviceName: nil,
      sender: sender,
      attachments: nil
    )
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    interaction.donate(completion: nil)
    do {
      return try content.updating(from: intent)
    } catch {
      return content
    }
  }

  private static func person(id: String, name: String, image: INImage?) -> INPerson {
    INPerson(
      personHandle: INPersonHandle(value: id, type: .unknown),
      nameComponents: nil,
      displayName: name,
      image: image,
      contactIdentifier: nil,
      customIdentifier: id
    )
  }

  // 사진을 못 받으면(주소 없음·만료·망) 사진 없이 간다.
  private static func loadPhoto(_ url: URL?, completion: @escaping (INImage?) -> Void) {
    guard let url else {
      completion(nil)
      return
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    URLSession.shared.dataTask(with: request) { data, response, _ in
      let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
      completion(ok ? data.map(INImage.init(imageData:)) : nil)
    }.resume()
  }

  /// 안내 줄의 사람. 안드로이드 고정 Person key와 같은 역할이다.
  private static let noticeId = "notice"

  /// 앱 `AppStrings.chatPushNoticeSender`와 같은 말.
  private static let noticeName = "안내"

  private static let noticeImage: INImage? = Bundle.main
    .url(forResource: "chat_notice", withExtension: "png")
    .flatMap { try? Data(contentsOf: $0) }
    .map(INImage.init(imageData:))
}
