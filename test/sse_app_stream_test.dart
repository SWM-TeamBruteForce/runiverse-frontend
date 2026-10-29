import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/notification/data/sse_app_stream.dart';
import 'package:runiverse/features/notification/domain/app_stream.dart';
import 'package:runiverse/features/notification/domain/app_notification.dart';

/// 앱 전역 알림 스트림(`GET /api/v1/app/stream`).
///
/// ## ⚠️ 매칭 스트림과 다른 두 가지
///
/// - **404가 없다.** 활성 신청과 무관하게 열린다. 매칭 스트림의 404(수락 전
///   연결)와 구분해야 한다
/// - **버전 헤더가 없으면 거절한다.** 다른 경로의 공통 규칙("없으면 통과")과
///   어긋나는 자리다
void main() {
  group('이벤트를 읽는다', () {
    const invited =
        '{"notificationId":913,"isRead":false,'
        '"createdAt":"2026-10-28T12:10:00",'
        '"actor":{"userId":"u1","nickname":"철수","isDeleted":false,'
        '"relationshipType":"FRIEND"},'
        '"invitation":{"runningRoomId":130,"status":"PENDING",'
        '"scheduledStartAt":"2026-10-28T19:30:00",'
        '"targetDistanceMeters":7000}}';

    test('RUNNING_INVITED를 알림으로 읽는다', () {
      final one = SseAppStream.eventOf('RUNNING_INVITED', invited);

      expect(one!.notificationId, 913);
      expect(one.type, NotificationType.runningInvited);
      expect(one.invitation!.runningRoomId, 130);
    });

    test('친구 이벤트 둘도 읽는다', () {
      const friend =
          '{"notificationId":912,"isRead":false,'
          '"createdAt":"2026-10-28T12:10:00",'
          '"actor":{"userId":"u1","nickname":"영희","isDeleted":false,'
          '"relationshipType":"FRIEND_REQUEST_RECEIVED"},'
          '"invitation":null}';

      expect(
        SseAppStream.eventOf('FRIEND_REQUESTED', friend)!.type,
        NotificationType.friendRequested,
      );
      expect(
        SseAppStream.eventOf('FRIEND_ACCEPTED', friend)!.type,
        NotificationType.friendAccepted,
      );
    });

    test('⚠️ 모르는 event는 버리고 스트림은 산다', () {
      // 지원하지 않는 이벤트를 받았다고 알림 처리 전체가 실패하면 안 된다.
      expect(SseAppStream.eventOf('SOMETHING_NEW', invited), isNull);
    });

    test('이름이 없거나 본문이 비면 null이다', () {
      // `:connected`와 `:ping`은 주석이라 이름 없이 여기 온다.
      expect(SseAppStream.eventOf(null, ''), isNull);
      expect(SseAppStream.eventOf('RUNNING_INVITED', ''), isNull);
    });

    test('JSON이 깨져도 던지지 않는다', () {
      expect(SseAppStream.eventOf('RUNNING_INVITED', '{nope'), isNull);
    });
  });

  group('실패를 가른다', () {
    test('⚠️ 버전을 읽은 상태의 403 APP_UPDATE_REQUIRED는 진짜 구버전이다', () {
      expect(
        SseAppStream.failureOf(403, {
          'code': 'APP_UPDATE_REQUIRED',
        }, versionKnown: true),
        AppStreamFailure.updateRequired,
      );
    });

    test('⚠️ 버전을 못 읽었으면 업데이트 화면으로 보내지 않는다', () {
      // 헤더가 빠져서 받은 403이다. 멀쩡한 최신 앱을 영영 업데이트 화면에
      // 가두는 것보다 알림만 포기하는 편이 낫다.
      expect(
        SseAppStream.failureOf(403, {
          'code': 'APP_UPDATE_REQUIRED',
        }, versionKnown: false),
        AppStreamFailure.unknown,
      );
    });

    test('APP_UPDATE_REQUIRED가 아닌 403은 업데이트가 아니다', () {
      // 이메일 미동의 같은 다른 403이 있다. 상태 코드만으로 판단하지 않는다.
      expect(
        SseAppStream.failureOf(403, {
          'code': 'EMAIL_NOT_AGREED',
        }, versionKnown: true),
        AppStreamFailure.unknown,
      );
    });

    test('401은 토큰 문제다', () {
      expect(
        SseAppStream.failureOf(401, null, versionKnown: true),
        AppStreamFailure.sessionExpired,
      );
    });

    test('⚠️ 404는 이 경로에 없다 — 매칭 스트림과 구분한다', () {
      expect(
        SseAppStream.failureOf(404, null, versionKnown: true),
        AppStreamFailure.unknown,
      );
    });

    test('5xx는 다시 붙어 보는 것뿐이다', () {
      expect(
        SseAppStream.failureOf(503, null, versionKnown: true),
        AppStreamFailure.network,
      );
    });
  });

  group('재연결 간격', () {
    test('반복마다 늘어난다', () {
      final backoff = AppStreamBackoff();
      final first = backoff.next();
      final second = backoff.next();
      final third = backoff.next();

      expect(second, greaterThan(first));
      expect(third, greaterThan(second));
    });

    test('⚠️ 상한이 있다', () {
      // 끝없이 늘리면 하루 뒤에 깨어나는 연결이 된다.
      final backoff = AppStreamBackoff();
      for (var i = 0; i < 20; i++) {
        backoff.next();
      }

      expect(backoff.next(), AppStreamBackoff.max);
    });

    test('붙으면 처음으로 돌아간다', () {
      final backoff = AppStreamBackoff();
      final first = backoff.next();
      backoff.next();
      backoff.reset();

      expect(backoff.next(), first);
    });

    test('⚠️ 첫 간격도 0이 아니다', () {
      // 같은 서버에 붙은 두 기기가 서로의 연결을 끊을 수 있다. 즉시 재연결을
      // 무한 반복하면 둘이 서로를 밀어내며 돈다.
      expect(AppStreamBackoff().next(), greaterThan(Duration.zero));
    });
  });
}
