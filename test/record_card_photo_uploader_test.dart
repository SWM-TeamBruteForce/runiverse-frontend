import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/record_card/data/card_photo_uploader.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';

/// S3에 직접 올리는 자리 (연동 가이드 3절).
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('card_upload_test');
    file = File('${dir.path}/photo.jpg')..writeAsBytesSync(List.filled(64, 7));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('⚠️ 올리는 Dio에는 주소도 인증도 붙지 않는다', () {
    // `dio_client`의 Dio로 보내면 baseUrl이 붙고 Authorization 헤더가
    // 실린다 — S3가 그 헤더까지 서명 검증에 넣어 403을 준다.
    final uploader = CardPhotoUploader();

    expect(uploader.uploadDio.options.baseUrl, isEmpty);
    expect(
      uploader.uploadDio.options.headers.keys,
      isNot(contains('Authorization')),
    );
  });

  test('⚠️ 보내는 시간 제한이 따로 길다', () {
    // 사진 본문이 올라가는 구간이라 나머지와 같은 값으로 묶으면 느린 망에서
    // 멀쩡한 업로드가 잘린다. 기본값은 무제한 대기다.
    final uploader = CardPhotoUploader();

    expect(uploader.uploadDio.options.sendTimeout, const Duration(seconds: 60));
    expect(
      uploader.uploadDio.options.connectTimeout,
      const Duration(seconds: 10),
    );
  });

  test('⚠️ 잰 크기와 실제 바이트가 다르면 올리지 않는다', () async {
    // 서명은 요청에 넣은 크기로 받았다. 그대로 올리면 403인데, 원인이
    // S3 응답에 전혀 드러나지 않는다 — 여기서 멈춰야 가까운 곳에 남는다.
    final uploader = CardPhotoUploader();

    await expectLater(
      uploader.put(
        url: 'https://s3.invalid/x',
        path: file.path,
        mimeType: 'image/jpeg',
        sizeBytes: 65,
      ),
      throwsA(isA<RecordCardException>()),
    );
  });

  test('⚠️ 파일이 사라졌으면 올리지 않는다', () async {
    final uploader = CardPhotoUploader();

    await expectLater(
      uploader.put(
        url: 'https://s3.invalid/x',
        path: '${dir.path}/없는파일.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 64,
      ),
      throwsA(isA<RecordCardException>()),
    );
  });

  test('보낸 본문과 헤더가 발급 때 값과 같다', () async {
    final sent = <({String url, int length, String? type})>[];
    final uploader = CardPhotoUploader(uploadDio: _Recording(sent));

    await uploader.put(
      url: 'https://s3.invalid/put-here',
      path: file.path,
      mimeType: 'image/jpeg',
      sizeBytes: 64,
    );

    expect(sent.single.url, 'https://s3.invalid/put-here');
    expect(sent.single.length, 64);
    expect(sent.single.type, 'image/jpeg');
  });

  test('⚠️ S3가 거절하면 망 실패로 올라간다', () async {
    final uploader = CardPhotoUploader(uploadDio: _Failing());

    await expectLater(
      uploader.put(
        url: 'https://s3.invalid/x',
        path: file.path,
        mimeType: 'image/jpeg',
        sizeBytes: 64,
      ),
      throwsA(
        isA<RecordCardException>().having(
          (e) => e.failure,
          'failure',
          RecordCardFailure.network,
        ),
      ),
    );
  });
}

/// 보낸 것을 적어 두는 [Dio].
class _Recording extends DioMixin implements Dio {
  _Recording(this.sent);

  final List<({String url, int length, String? type})> sent;

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    sent.add((
      url: path,
      length: (data! as List<int>).length,
      type: options?.contentType,
    ));
    return Response<T>(requestOptions: RequestOptions(path: path));
  }
}

/// 언제나 거절하는 [Dio].
class _Failing extends DioMixin implements Dio {
  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async => throw DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: RequestOptions(path: path),
      statusCode: 403,
    ),
  );
}
