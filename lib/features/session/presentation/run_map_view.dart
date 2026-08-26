import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 달린 경로를 그리는 지도.
///
/// ## 키가 없으면 지도를 만들지 않는다
///
/// `--dart-define=NAVER_MAP_CLIENT_ID=...`가 없으면 SDK가 초기화되지 않았고,
/// 그 상태에서 [NaverMap]을 세우면 **앱이 통째로 죽는다.** 안내를 대신 그린다 —
/// 시간·거리·페이스는 지도 없이도 그대로 돈다.
///
/// ## 구간마다 선을 따로 그린다
///
/// [track]이 좌표 하나의 목록이 아니라 **목록의 목록**인 이유다. 일시정지 사이의
/// 이동은 거리에 넣지 않기로 했으니 선으로도 잇지 않는다 — 하나로 이으면 멈춘
/// 사이에 차로 옮긴 것까지 뛴 것처럼 그려진다.
class RunMapView extends StatefulWidget {
  const RunMapView({required this.track, super.key});

  /// 구간별 경로. 각 구간은 좌표 2개 이상이다.
  final List<List<GeoPoint>> track;

  @override
  State<RunMapView> createState() => _RunMapViewState();
}

class _RunMapViewState extends State<RunMapView> {
  /// 스타일 에디터에서 만든 야간 스타일(`runiverse_night_default`).
  ///
  /// ⚠️ **이름이 아니라 My Style ID다.** 이름을 넣으면 서버가 400
  /// (`Invalid custom style ID`)으로 거절하고 SDK는 조용히 기본 스타일로
  /// 떨어진다. 실제로 그렇게 한 번 헤맸다.
  ///
  /// ⚠️ **시크릿이 아니다.** 클라이언트 ID와 달리 사용량이 걸려 있지 않고
  /// 환경마다 달라지지도 않아 `config/*.json`으로 빼지 않는다.
  ///
  /// ⚠️ **없는 ID면 조용히 기본 스타일로 떨어진다.** 앱이 죽지는 않지만
  /// 지도가 밝게 나오면 이 값부터 본다.
  static const _styleId = '66d8e4b2-5d6f-4099-8372-e979cc683c65';

  /// 초기 줌. **스케일바로 약 400m**에 해당한다.
  ///
  /// 축척은 위도에 따라 달라진다(Web Mercator) —
  /// `metersPerPixel = 156543.034 × cos(위도) / 2^zoom`.
  /// 서울(위도 37.5) 기준으로 16이 400m, 17이 200m, 18이 100m, 20이 30m다.
  ///
  /// ## 30m에서 세 번 낮췄다
  ///
  /// 처음엔 20(30m)으로 열었는데 **달리는 동안 경로가 화면에 남지 않았다.**
  /// 3m/s면 10초에 30m라 금방 밖으로 나간다. 18·17을 거쳐 16으로 왔다 —
  /// 몇 분치 경로가 한눈에 들어온다.
  static const _initialZoom = 16.0;

  /// 첫 좌표를 받기 전에 열어 둘 자리. 곧 내 위치로 따라간다.
  static const _fallbackTarget = NLatLng(37.5666, 126.9784);

  NaverMapController? _controller;

  @override
  void didUpdateWidget(RunMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track != oldWidget.track) _draw();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasNaverMapClientId) return const _MapUnavailable();

    return NaverMap(
      options: NaverMapViewOptions(
        // 달리는 사람이 보는 지도다. 어두운 바탕에서 경로선이 또렷하다.
        //
        // ⚠️ 커스텀 스타일을 쓰면 **야간·라이트 모드가 고정된다**(SDK 제약).
        // 앱이 라이트 테마여도 지도는 어둡게 나온다.
        customStyleId: _styleId,
        initialCameraPosition: NCameraPosition(
          target: _firstPoint() ?? _fallbackTarget,
          zoom: _initialZoom,
        ),
        // 내 위치를 따라간다. 달리면서 지도를 손으로 끌 여유는 없다.
        locationButtonEnable: true,
        // 러닝 중에는 기울이거나 돌릴 일이 없다. 손가락이 미끄러져 화면이
        // 돌아가면 다시 맞추는 것이 일이다.
        rotationGesturesEnable: false,
        tiltGesturesEnable: false,
        indoorEnable: false,
      ),
      // ⚠️ 스타일이 안 먹어도 SDK는 **조용히 기본 스타일로 떨어진다.**
      // 콜백이 없으면 "왜 밝지"에서 멈춘다 — 실패 이유를 듣는다.
      onCustomStyleLoadFailed: (error) =>
          debugPrint('[naver-map] 커스텀 스타일 실패 · id=$_styleId · $error'),
      onMapReady: (controller) {
        _controller = controller;
        // 추적 모드가 카메라를 현재 위치로 옮기지만 **줌은 덮지 않는다.**
        // (실기기에서 `getCameraPosition()`으로 확인했다 — 16을 넣으면 16이다.)
        controller.setLocationTrackingMode(NLocationTrackingMode.follow);
        _draw();
      },
    );
  }

  /// 이미 달린 구간이 있으면 그 시작점에서 연다. 없으면 `null`.
  ///
  /// 요약 화면이 이 값을 쓴다 — 러닝이 끝난 뒤에는 따라갈 현재 위치가 없다.
  NLatLng? _firstPoint() {
    for (final segment in widget.track) {
      if (segment.isNotEmpty) {
        return NLatLng(segment.first.latitude, segment.first.longitude);
      }
    }
    return null;
  }

  /// 경로를 다시 그린다.
  ///
  /// 오버레이를 지우고 다시 얹는다. 좌표가 1초에 한 번 들어오는 정도라
  /// 이 방식으로 충분하다 — 증분 갱신은 구간이 늘 때 오히려 더 복잡해진다.
  Future<void> _draw() async {
    final controller = _controller;
    if (controller == null) return;

    await controller.clearOverlays(type: NOverlayType.pathOverlay);

    for (var i = 0; i < widget.track.length; i++) {
      final segment = widget.track[i];
      if (segment.length < 2) continue;

      await controller.addOverlay(
        NPathOverlay(
          id: 'run-$i',
          coords: [
            for (final point in segment)
              NLatLng(point.latitude, point.longitude),
          ],
          width: 6,
          // ⚠️ 색을 토큰에서 가져오지 못한다. 오버레이는 위젯 트리 밖이라
          // `context.appColors`를 읽을 수 없다. 값은 `AppColors.primary`와
          // 같게 유지한다 — 한쪽만 바뀌면 지도 선만 다른 색이 된다.
          color: const Color(0xFF4C6FFF),
          outlineColor: const Color(0xFF4C6FFF),
        ),
      );
    }
  }
}

/// 지도를 띄울 수 없다. **고장이 아니라 설정이 빠진 것**이라고 말한다.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ColoredBox(
      color: colors.bgElevated,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.map,
              size: AppSpacing.space8,
              color: colors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              AppStrings.runMapUnavailable,
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
