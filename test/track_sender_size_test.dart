import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/track_sender.dart';

/// 한 배치가 서버의 WebSocket 메시지 한도를 넘지 않는가.
///
/// ## 왜 이 테스트가 있나
///
/// `TrackSender.batchLimit`이 200이던 때 실제로 close code **1009**(메시지
/// 초과)로 소켓이 끊겼다. 끊기면 재연결 → 커서 되감기 → **같은 배치를 다시
/// 보내 또 1009** 로 스스로 증폭한다. 한 번 밀리면 빠져나오지 못한다.
///
/// 배치 크기는 개수로 정하는데 한도는 바이트다. **그 사이를 이 테스트가
/// 잇는다** — `TrackPoint`에 필드가 늘어 점당 크기가 커지면 여기서 먼저 깨진다.
void main() {
  /// 가장 큰 좌표. **필드를 하나도 비우지 않는다.**
  ///
  /// 실제 좌표는 케이던스나 고도가 `null`이라 이보다 작다. 한도를 보는
  /// 테스트이므로 최악을 재야 한다. 소수점도 길게 둔다 — `double`이 그대로
  /// 문자열이 되므로 자릿수가 곧 바이트다.
  TrackPoint biggest(int sequence) => TrackPoint(
    sequence: sequence,
    latitude: 37.500898300000004,
    longitude: 127.00001234567891,
    altitudeMeters: 41.832031250000004,
    accuracyMeters: 12.345678901234567,
    speedMetersPerSecond: 3.1415927410125732,
    headingDegrees: 359.87654321098765,
    cadenceSpm: 174,
    currentPaceSecondsPerKm: 318,
    recordedAt: DateTime(2026, 9, 3, 1, 45, 30),
  );

  int encodedBytes(int count) {
    final message = WsMessage(WsEvents.runningLocationUpdate, {
      'locations': [for (var i = 1; i <= count; i++) biggest(i).toJson()],
    });
    return utf8.encode(message.encode()).length;
  }

  test('⚠️ 최대 배치가 서버 한도를 넘지 않는다', () {
    final bytes = encodedBytes(TrackSender.batchLimit);

    expect(
      bytes,
      lessThan(TrackSender.serverMessageLimitBytes),
      reason:
          '${TrackSender.batchLimit}점이 ${bytes}B다. 한도는 '
          '${TrackSender.serverMessageLimitBytes}B — 1009로 끊긴다. '
          'TrackPoint에 필드를 더했다면 batchLimit을 함께 낮춰야 한다.',
    );
  });

  test('⚠️ 여유가 20% 이상 남는다', () {
    // 딱 맞게 두면 필드 하나만 늘어도 곧바로 한도를 넘는다. 200점이던 때
    // 여유가 13%였고 그래서 터졌다.
    final bytes = encodedBytes(TrackSender.batchLimit);
    final headroom =
        (TrackSender.serverMessageLimitBytes - bytes) /
        TrackSender.serverMessageLimitBytes;

    expect(
      headroom,
      greaterThan(0.20),
      reason: '여유가 ${(headroom * 100).toStringAsFixed(1)}%뿐이다',
    );
  });

  test('점 하나가 300바이트를 넘지 않는다', () {
    // 배치 상한을 개수로 정할 수 있는 근거다. 점당 크기가 흔들리면
    // 개수 기준이 무너지고 바이트 기준으로 잘라야 한다.
    final perPoint = encodedBytes(100) / 100;

    expect(perPoint, lessThan(300));
  });
}
