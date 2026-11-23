import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/http_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';

/// 기록카드 REST의 실패 분류.
///
/// 계약은 「💾 [1.3.2] 기록 카드 프론트엔드 연동 가이드」다.
void main() {
  DioException badResponse(int status, {Object? body}) => DioException(
    requestOptions: RequestOptions(path: '/api/v1/record-cards'),
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: RequestOptions(path: '/api/v1/record-cards'),
      statusCode: status,
      data: body,
    ),
  );

  RecordCardFailure failureOf(DioException error) =>
      HttpRecordCardRepository.failureOf(error);

  group('실패를 가른다', () {
    test('⚠️ 응답이 없으면 망 문제다 — 다시 해 볼 수 있다', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        expect(
          failureOf(
            DioException(requestOptions: RequestOptions(path: '/x'), type: type),
          ),
          RecordCardFailure.network,
          reason: '$type',
        );
      }
    });

    test('400은 앱의 버그다 — 다시 보내도 같은 답이다', () {
      expect(
        failureOf(badResponse(400, body: {'code': 'INVALID_REQUEST'})),
        RecordCardFailure.invalidRequest,
      );
    });

    test('401은 로그인이 풀린 것이다', () {
      expect(failureOf(badResponse(401)), RecordCardFailure.sessionExpired);
    });

    test('⚠️ 403과 404는 기다려도 달라지지 않는다', () {
      // `server`로 뭉치면 화면이 "잠시 뒤 다시"를 권하는데 거짓말이 된다.
      expect(failureOf(badResponse(403)), RecordCardFailure.forbidden);
      expect(failureOf(badResponse(404)), RecordCardFailure.notFound);
    });

    test('⚠️ 상세의 404는 한 가지 실패다 — 삭제·권한·탈퇴를 가르지 않는다', () {
      // 가이드 2절이 "같은 응답으로 처리한다"고 적었다. 갈라 보이면
      // 없는 카드의 작성자가 탈퇴했는지를 남에게 알려 주는 셈이다.
      expect(
        failureOf(badResponse(404, body: {'code': 'NOT_FOUND'})),
        RecordCardFailure.notFound,
      );
    });

    test('5xx는 서버 문제다', () {
      expect(failureOf(badResponse(500)), RecordCardFailure.server);
      expect(failureOf(badResponse(503)), RecordCardFailure.server);
    });

    test('⚠️ 모르는 상태 코드를 성공으로 보지 않는다', () {
      // 쓰기 코드(409 등)는 묶음 8이 가른다. 그때까지도 **실패로는 선다.**
      expect(failureOf(badResponse(409)), RecordCardFailure.server);
      expect(failureOf(badResponse(418)), RecordCardFailure.server);
    });

    test('⚠️ 403 APP_UPDATE_REQUIRED를 여기서 가르지 않는다', () {
      // `dio_client.dart`의 인터셉터가 저장소보다 **앞에서** 잡아 업데이트
      // 관문으로 보낸다. 여기서 또 가르면 같은 일을 두 곳에서 하고, 한쪽만
      // 고쳐지는 날이 온다. 그래서 그냥 `forbidden`이다.
      expect(
        failureOf(badResponse(403, body: {'code': 'APP_UPDATE_REQUIRED'})),
        RecordCardFailure.forbidden,
      );
    });
  });

  group('날짜', () {
    test('⚠️ 시각을 붙이지 않는다 — KST 달력 날짜다', () {
      expect(
        HttpRecordCardRepository.day(DateTime(2026, 11, 2, 23, 50)),
        '2026-11-02',
      );
      expect(HttpRecordCardRepository.day(DateTime(2026, 1, 9)), '2026-01-09');
    });
  });
}
