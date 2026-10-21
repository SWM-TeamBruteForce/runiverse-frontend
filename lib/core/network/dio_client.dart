import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/core/version/app_version_headers.dart';

/// 서버를 부를 때 쓰는 [Dio] 하나를 만든다.
///
/// ## 왜 함수인가
///
/// 여기서 [Dio]를 전역 변수로 들고 있으면 테스트가 서로 오염된다.
/// 누가 언제 하나만 쓸지는 [Provider]가 정하게 두고, 이 파일은 만드는 법만 안다.
///
/// ## dio의 `LogInterceptor`는 쓰지 않는다
///
/// `LogInterceptor`는 요청·응답 본문을 통째로 찍는다. 로그인 요청에는
/// **비밀번호**가, 응답에는 **`refreshToken`**이 들어 있다 — 탈취되면 계정을
/// 계속 쓸 수 있는 값이라 `AuthSession`이 "로그로 찍지 않는다"고 규정해 뒀다.
/// 편의를 위해 켰다가 그대로 두면 그 규칙이 조용히 깨진다.
///
/// 대신 아래에 method·경로·상태 코드만 찍는 인터셉터를 직접 단다.
/// 그것만으로 "요청이 나갔는가"는 알 수 있고, 자격증명은 남지 않는다.
Dio createDio({void Function()? onUpdateRequired}) {
  // 주소가 없으면 여기서 멈춘다. 이대로 두면 상대 경로로 요청이 나가서
  // "서버가 죽었다"와 구분되지 않는 실패를 보게 된다 — 원인이 설정인데
  // 서버를 뒤지게 되는 상황이 제일 오래 걸린다.
  if (!AppConfig.hasApiBaseUrl) {
    throw StateError('서버 주소가 없다. --dart-define=API_BASE_URL=... 을 붙여 실행한다.');
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      // 응답이 없을 때 영원히 기다리면 화면의 로딩 표시가 멈추지 않는다.
      // 사용자는 앱이 죽은 것으로 본다.
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: Headers.jsonContentType,
      // 앱 버전 헤더. **없으면 서버가 그냥 통과시킨다**(공통 규칙) — 못 읽은
      // 값을 지어내면 통과했을 요청이 403으로 막힌다.
      headers: AppVersionHeaders.current,
      // 4xx·5xx에서 던지게 둔다. 저장소가 `DioException`을 잡아
      // 자기 실패 타입으로 바꾼다.
      responseType: ResponseType.json,
    ),
  );

  // 업데이트가 필요하다는 거절을 가장 먼저 잡는다.
  //
  // ## ⚠️ 저장소가 오류를 바꾸기 전에 잡아야 한다
  //
  // 저장소마다 `DioException`을 자기 실패 타입으로 옮긴다. 거기까지 가면
  // 403은 화면마다 다른 문구가 되고, **업데이트가 필요하다는 사실이 사라진다.**
  // 인터셉터는 그 변환보다 앞이다.
  //
  // ## ⚠️ `code`를 본다. 403이라고 다 이것이 아니다
  //
  // 권한 없는 리소스도 403이다. 그것까지 업데이트 화면으로 보내면 멀쩡한 앱이
  // 선다. 작업 가이드가 "`APP_UPDATE_REQUIRED`일 때만"이라고 못 박았다.
  //
  // ## 오류를 삼키지 않는다
  //
  // 알리기만 하고 `handler.next(error)`로 흘려보낸다. 막는 것은 게이트의
  // 몫이고, 여기서 삼키면 부르던 쪽이 영영 답을 못 받는다.
  if (onUpdateRequired != null) {
    dio.interceptors.add(updateRequiredInterceptor(onUpdateRequired));
  }

  // 요청이 실제로 나갔는지 눈으로 확인하기 위한 최소한의 흔적.
  //
  // **본문을 찍지 않는다.** 로그인 응답에는 `refreshToken`이 들어 있고,
  // 요청에는 비밀번호가 들어 있다. method·경로·상태 코드만 남기면
  // "요청이 나갔는가, 서버가 뭐라 답했는가"는 알 수 있으면서
  // 자격증명은 로그에 남지 않는다.
  //
  // 경로만 찍으므로 서버 주소도 드러나지 않는다.
  if (kDebugMode) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('[api] → ${options.method} ${options.path}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            '[api] ← ${response.statusCode} ${response.requestOptions.path}',
          );
          handler.next(response);
        },
        onError: (error, handler) {
          debugPrint(
            '[api] x ${error.type.name} '
            '${error.response?.statusCode ?? '-'} '
            '${error.requestOptions.path}',
          );
          handler.next(error);
        },
      ),
    );
  }

  return dio;
}

/// 서버가 **앱 업데이트가 필요하다**고 거절했는가.
///
/// REST와 SSE가 같은 판정을 쓴다. 한쪽만 고치면 경로에 따라 다르게 동작한다.
///
/// ⚠️ **403만으로는 모자라다.** 권한 없는 리소스도 403이라, 그것까지 업데이트
/// 화면으로 보내면 멀쩡한 앱이 선다.
bool isUpdateRequired(int? statusCode, Object? body) {
  if (statusCode != 403) return false;
  return body is Map && body['code'] == 'APP_UPDATE_REQUIRED';
}

/// 403 `APP_UPDATE_REQUIRED`를 [onUpdateRequired]에 알리는 인터셉터.
///
/// **떼어 둔 이유는 테스트다.** `createDio()`는 서버 주소가 없으면 `StateError`로
/// 멈추므로 테스트에서 부를 수 없다.
Interceptor updateRequiredInterceptor(void Function() onUpdateRequired) {
  return InterceptorsWrapper(
    onError: (error, handler) {
      if (isUpdateRequired(error.response?.statusCode, error.response?.data)) {
        debugPrint('[version] 서버가 업데이트를 요구한다 · ${error.requestOptions.path}');
        onUpdateRequired();
      }
      handler.next(error);
    },
  );
}
