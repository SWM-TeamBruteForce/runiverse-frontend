import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/data/card_photo_uploader.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/data/http_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 카드 작성 — 초안 발급(9-1) → S3 → 확정(9-2) (연동 가이드 3절).
void main() {
  const draftId = '019aa100-0000-7000-8000-000000000099';
  const cardId = '019aa100-0000-7000-8000-0000000000aa';

  late Directory dir;
  late PickedImage file;
  late PickedImage thumb;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('card_create_test');
    final one = File('${dir.path}/photo.jpg')
      ..writeAsBytesSync(List.filled(64, 7));
    final two = File('${dir.path}/thumb.jpg')
      ..writeAsBytesSync(List.filled(16, 7));
    file = PickedImage.validated(path: one.path, sizeBytes: 64);
    thumb = PickedImage.validated(path: two.path, sizeBytes: 16);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  NewRecordCard card({int photos = 0}) => NewRecordCard(
    record: RunRecord(
      id: 123,
      runningRoomId: 9,
      startedAt: DateTime(2026, 11, 24, 4, 28),
      distanceMeters: 5000,
      duration: const Duration(minutes: 30),
      averagePace: const Duration(minutes: 6),
      playerCount: 1,
    ),
    route: RouteArt.empty,
    activity: RecordCardActivity.daily,
    visibility: RecordCardVisibility.friends,
    reviewText: '좋았다',
    photos: [
      for (var i = 0; i < photos; i++)
        NewCardPhoto(
          file: file,
          thumbnail: thumb,
          caption: i == 0 ? '노을' : null,
        ),
    ],
  );

  ({HttpRecordCardRepository repository, _Dio dio, _Uploader uploader}) world({
    String uploadType = 'SINGLE',
  }) {
    final store = InMemoryTokenStore();
    store.saveSession(
      userId: 'me',
      accessToken: 'token',
      refreshToken: 'refresh',
      isOnboarded: true,
    );
    final dio = _Dio(draftId: draftId, cardId: cardId, uploadType: uploadType);
    final uploader = _Uploader();
    return (
      repository: HttpRecordCardRepository(
        dio,
        store,
        TokenRefresher(FakeAuthRepository(), store),
        // 작업 7 이 이 자리를 걷어낸다 — 아직 생성자가 요구한다.
        fallback: FakeRecordCardRepository(),
        uploader: uploader,
      ),
      dio: dio,
      uploader: uploader,
    );
  }

  test('⚠️ 사진이 없으면 S3 단계를 건너뛴다', () async {
    final w = world();

    final made = await w.repository.create(card());

    expect(w.uploader.calls, isEmpty);
    expect(made.id, cardId);
    expect(w.dio.paths, [
      '/api/v1/record-cards',
      '/api/v1/record-cards/drafts/$draftId/complete',
      '/api/v1/record-cards/$cardId',
    ]);
  });

  test('사진 한 장이면 크롭본과 썸네일을 둘 다 올린다', () async {
    final w = world();

    await w.repository.create(card(photos: 1));

    expect(w.uploader.calls, hasLength(2));
  });

  test('보내는 값이 가이드 3절 그대로다', () async {
    final w = world();

    await w.repository.create(card(photos: 1));

    final body = w.dio.lastPost!;
    expect(body['runningRecordId'], 123);
    expect(body['activityType'], 'DAILY');
    expect(body['visibility'], 'FRIENDS');
    expect(body['memo'], '좋았다');
    expect(body['thumbnailIndex'], 0);
    final image = (body['images'] as List).single as Map<String, dynamic>;
    expect(image['mimeType'], 'image/jpeg');
    expect(image['fileSizeBytes'], 64);
    expect(image['thumbnailFileSizeBytes'], 16);
    expect(image['caption'], '노을');
    expect(image['fileName'], isNot(contains('/')));
  });

  test('⚠️ 확정이 409 RECORD_CARD_DRAFT_IN_PROGRESS면 같은 초안으로 다시 부른다', () async {
    // 잠시 기다렸다 같은 초안으로 다시 부르면 같은 번호가 온다(가이드 7절).
    final w = world();
    w.dio.failCompleteOnce(409, 'RECORD_CARD_DRAFT_IN_PROGRESS');

    final made = await w.repository.create(card());

    expect(made.id, cardId);
    expect(w.dio.completeCalls, 2);
  });

  test('⚠️ 확정이 400 RECORD_CARD_IMAGE_NOT_UPLOADED면 다시 올리고 재확정한다', () async {
    final w = world();
    w.dio.failCompleteOnce(400, 'RECORD_CARD_IMAGE_NOT_UPLOADED');

    await w.repository.create(card(photos: 1));

    expect(w.uploader.calls, hasLength(4));
    expect(w.dio.completeCalls, 2);
  });

  test('⚠️ 두 번째도 실패하면 그대로 던진다', () async {
    // 끝없이 다시 걸면 망이 죽었을 때 저장 표시가 영원히 돈다.
    final w = world();
    w.dio.failCompleteAlways(409, 'RECORD_CARD_DRAFT_IN_PROGRESS');

    await expectLater(
      w.repository.create(card()),
      throwsA(isA<RecordCardException>()),
    );
    expect(w.dio.completeCalls, 2);
  });

  test('⚠️ MULTIPART는 분명히 실패한다', () async {
    // 조각내 올리는 길을 만들지 않았다. 조용히 멈추면 원인이 안 보인다.
    final w = world(uploadType: 'MULTIPART');

    await expectLater(
      w.repository.create(card(photos: 1)),
      throwsA(isA<RecordCardException>()),
    );
  });
}

/// 올린 것을 적어 두는 업로더.
class _Uploader extends CardPhotoUploader {
  final calls = <String>[];

  @override
  Future<void> put({
    required String url,
    required String path,
    required String mimeType,
    required int sizeBytes,
  }) async {
    calls.add(url);
  }
}

/// 9-1 · 9-2 · 8-1 세 길만 아는 [Dio].
class _Dio extends DioMixin implements Dio {
  _Dio({required this.draftId, required this.cardId, required this.uploadType});

  final String draftId;
  final String cardId;
  final String uploadType;

  final paths = <String>[];
  Map<String, dynamic>? lastPost;
  var completeCalls = 0;

  int? _completeStatus;
  String? _completeCode;
  var _completeFailsAlways = false;

  void failCompleteOnce(int status, String code) {
    _completeStatus = status;
    _completeCode = code;
  }

  void failCompleteAlways(int status, String code) {
    failCompleteOnce(status, code);
    _completeFailsAlways = true;
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    paths.add(path);
    if (path.endsWith('/complete')) {
      completeCalls++;
      final status = _completeStatus;
      if (status != null) {
        if (!_completeFailsAlways) _completeStatus = null;
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.badResponse,
          response: Response<Object?>(
            requestOptions: RequestOptions(path: path),
            statusCode: status,
            data: {'code': _completeCode},
          ),
        );
      }
      return _ok<T>(path, {'recordCardId': cardId});
    }

    lastPost = data! as Map<String, dynamic>;
    final images = (lastPost!['images'] as List?) ?? const [];
    return _ok<T>(path, {
      'recordCardDraftId': draftId,
      'expiresAt': '2026-11-24T05:00:00',
      'uploads': [
        for (var i = 0; i < images.length; i++)
          {
            'recordCardImageId': 'image-$i',
            'uploadType': uploadType,
            'uploadUrl': 'https://s3.invalid/photo-$i',
            'thumbnailUploadUrl': 'https://s3.invalid/thumb-$i',
          },
      ],
    });
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    paths.add(path);
    return _ok<T>(path, {
      'recordCardId': cardId,
      'isMine': true,
      'visibility': 'FRIENDS',
      'activityType': 'DAILY',
      'memo': '좋았다',
      'record': {
        'runningRecordId': 123,
        'startedAt': '2026-11-24T04:28:00',
        'totalDistanceMeters': 5000,
        'totalDurationSeconds': 1800,
        'averagePaceSecondsPerKm': 360,
        'routeArt': <Object?>[],
      },
      'images': <Object?>[],
      'companions': <Object?>[],
    });
  }

  Response<T> _ok<T>(String path, Map<String, dynamic> body) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: body as T,
  );
}
