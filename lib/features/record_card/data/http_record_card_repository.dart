import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/data/record_card_detail_dto.dart';
import 'package:runiverse/features/record_card/data/record_card_list_dto.dart';
import 'package:runiverse/features/record_card/data/recorded_run_dto.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';

/// 진짜 서버를 부르는 [RecordCardRepository].
///
/// 계약은 **「💾 [1.3.2] 기록 카드 프론트엔드 연동 가이드」**가 정본이다.
/// `docs/specs/2026-11-16-record-card-design.md` 3절·10절의 추측은 낡았다.
///
/// ## ⚠️ 쓰기는 아직 가짜가 받는다
///
/// 읽기(달력·상세·프로필)를 먼저 붙이는 묶음이다(사용자 결정 2026-11-24).
/// [create]·[update]·[delete]는 [fallback]에 그대로 넘긴다 — **저장은 서버에
/// 가지 않는다.** 묶음 8이 이 세 줄을 9-1 → S3 → 9-2 로 바꾼다.
///
/// ## 401은 한 번만 갱신한다
///
/// `HttpRunRecordRepository`와 같은 규칙이고, 갱신은 반드시 [TokenRefresher]를
/// 거친다. 저장소마다 재시도를 적으면 한쪽만 고쳐지는 일이 생긴다.
class HttpRecordCardRepository implements RecordCardRepository {
  HttpRecordCardRepository(
    this._dio,
    this._store,
    this._refresher, {
    required this.fallback,
  });

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  /// 묶음 8까지 쓰기를 맡는다.
  ///
  /// ⚠️ **일부러 공개다.** Dart는 `_`로 시작하는 named 매개변수를 허용하지
  /// 않고, 네 번째 위치 인자로 두면 무엇을 넘기는지 호출부에서 읽히지 않는다.
  /// 묶음 8이 쓰기를 구현하면 이 필드가 사라진다.
  final FakeRecordCardRepository fallback;

  // ── 읽기 ─────────────────────────────────────────────────────

  /// 러닝 기록 목록 + 카드 유무 (7-1).
  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    // ⚠️ **서버에 묻기 전에 걸러 낸다.** 400을 받고 나서야 아는 것보다 낫고,
    // 무엇보다 이건 사용자 입력이 아니라 **앱의 버그**다.
    if (from.isAfter(to)) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }
    // 가이드 1절: 시작일과 종료일을 **포함해** 최대 31일이다.
    if (to.difference(from).inDays >= RecordCardRepository.maxRangeDays) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }

    final body = await authorized(
      (token) => _dio.get<Map<String, dynamic>>(
        '/api/v1/users/me/running-records',
        queryParameters: {'from': day(from), 'to': day(to)},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    return RecordedRunDto.listFrom(body);
  }

  /// 그 사람의 카드 한 페이지 (10-3).
  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) async {
    // ⚠️ **번호를 경로에 그대로 붙이지 않는다.** 닉네임이 번호로 쓰이는 날
    // `/`가 든 값 하나가 경로를 갈라 **다른 엔드포인트를 부른다.**
    final path =
        '/api/v1/users/${Uri.encodeComponent(userId)}/record-cards';
    final body = await authorized(
      (token) => _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {
          // ⚠️ **`null`을 싣지 않는다.** `?limit=null`은 400이다.
          'limit': ?limit,
          'cursor': ?cursor,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    return RecordCardListDto.from(body);
  }

  /// 카드 한 장 전부 (8-1).
  @override
  Future<RecordCard> detailOf(String cardId) async {
    // ⚠️ **번호를 경로에 그대로 붙이지 않는다.** UUID라 지금은 안전하지만,
    // 서버가 형식을 바꾸면 `/`가 들어온 번호 하나가 경로를 갈라 **다른
    // 엔드포인트를 부른다.**
    final path = '/api/v1/record-cards/${Uri.encodeComponent(cardId)}';
    final body = await authorized(
      (token) => _dio.get<Map<String, dynamic>>(
        path,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    return RecordCardDetailDto.from(body);
  }

  /// 못 만든 곡을 다시 만들어 달라고 한다 (9-6). 본문이 없고 `204`가 온다.
  @override
  Future<void> retryMusic(String cardId) => authorizedVoid(
    (token) => _dio.post<void>(
      '/api/v1/record-cards/${Uri.encodeComponent(cardId)}/retry',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    ),
  );

  // ── 쓰기 — 묶음 8까지 가짜가 받는다 ──────────────────────────

  @override
  Future<RecordCard> create(NewRecordCard card) => fallback.create(card);

  @override
  Future<RecordCard> update(EditRecordCard card) => fallback.update(card);

  @override
  Future<void> delete(String cardId) => fallback.delete(cardId);

  // ── 공통 ─────────────────────────────────────────────────────

  /// 토큰을 실어 보내고, **401이면 한 번만** 갱신해서 다시 부른다.
  ///
  /// 읽기 셋이 같은 규칙을 쓰도록 여기 모았다.
  Future<Map<String, dynamic>> authorized(
    Future<Response<Map<String, dynamic>>> Function(String token) send,
  ) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const RecordCardException(RecordCardFailure.sessionExpired);
    }

    try {
      return _body(await send(accessToken));
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw exceptionOf(error);
      }
      try {
        return _body(await send(await _refreshed()));
      } on DioException catch (retried) {
        throw exceptionOf(retried);
      }
    }
  }

  /// 본문이 없는 요청(`204`)을 보낸다. 401 규칙은 [authorized]와 같다.
  ///
  /// ⚠️ **[authorized]를 쓰지 않는다.** 그쪽은 본문을 요구해서, 본문 없는
  /// `204`를 **서버 오류로** 읽는다.
  Future<void> authorizedVoid(
    Future<Response<void>> Function(String token) send,
  ) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const RecordCardException(RecordCardFailure.sessionExpired);
    }

    try {
      await send(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw exceptionOf(error);
      }
      try {
        await send(await _refreshed());
      } on DioException catch (retried) {
        throw exceptionOf(retried);
      }
    }
  }

  /// 읽기 구현이 쓸 [Dio]. 묶음 7의 다음 작업들이 쓴다.
  Dio get dio => _dio;

  static Map<String, dynamic> _body(Response<Map<String, dynamic>> response) {
    final data = response.data;
    if (data == null) {
      throw const RecordCardException(RecordCardFailure.server);
    }
    return data;
  }

  Future<String> _refreshed() async {
    final accessToken = await _refresher.refresh();
    if (accessToken == null) {
      throw const RecordCardException(RecordCardFailure.sessionExpired);
    }
    return accessToken;
  }

  /// 서버가 받는 `YYYY-MM-DD`. **KST 달력 날짜**라 시각을 붙이지 않는다.
  static String day(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// `DioException`을 카드 실패로 옮긴다.
  ///
  /// ## ⚠️ 읽기에는 `code`로 갈릴 자리가 없다
  ///
  /// 가이드는 "앱의 분기는 `code`를 기준으로" 하라고 적었는데, 그 `code`가
  /// 갈라 주는 것은 **전부 쓰기 쪽**이다(7절 표의 `RECORD_CARD_ALREADY_EXISTS`
  /// ·`RECORD_CARD_CHANGED`·`RECORD_CARD_DRAFT_IN_PROGRESS`
  /// ·`RECORD_CARD_IMAGE_NOT_UPLOADED`·`INVALID_RECORD_CARD_IMAGE`). 복구
  /// 위치가 코드마다 달라 한 값으로 뭉개면 안 되지만, **읽기에서는 그 코드가
  /// 오지 않는다.** 그래서 지금은 상태 코드만 본다 — 묶음 8이 `code` 분기를
  /// 여기에 넣는다. 쓰지 않는 값을 미리 읽어 두면 "읽는데 안 쓰는 코드"가
  /// 남는다.
  ///
  /// ## ⚠️ `403 APP_UPDATE_REQUIRED`는 여기 오지 않는다
  ///
  /// `dio_client.dart`의 `updateRequiredInterceptor`가 저장소보다 **앞에서**
  /// 잡아 업데이트 관문으로 보낸다. 여기서 또 가르면 같은 일을 두 곳에서 하고,
  /// 한쪽만 고쳐지는 날이 온다.
  static RecordCardException exceptionOf(DioException error) =>
      RecordCardException(failureOf(error));

  static RecordCardFailure failureOf(DioException error) {
    // ⚠️ **응답이 없으면 망 문제다.** 시간 초과·연결 실패·취소가 여기다.
    if (error.type != DioExceptionType.badResponse) {
      return RecordCardFailure.network;
    }

    final status = error.response?.statusCode ?? 0;

    return switch (status) {
      400 => RecordCardFailure.invalidRequest,
      401 => RecordCardFailure.sessionExpired,
      // ⚠️ **이 둘은 재시도 대상이 아니다.** `server`로 뭉치면 화면이
      // 기다렸다 다시 해 보라고 권하는데, 기다린다고 달라지지 않는다.
      //
      // 상세의 `404`는 삭제·권한·작성자 탈퇴를 한 응답으로 묶는다 —
      // 화면은 "찾을 수 없거나 볼 수 없습니다"로 안내한다(가이드 2절).
      403 => RecordCardFailure.forbidden,
      404 => RecordCardFailure.notFound,
      _ => RecordCardFailure.server,
    };
  }
}
