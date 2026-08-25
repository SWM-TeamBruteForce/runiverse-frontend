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
      options: const NaverMapViewOptions(
        // 내 위치를 따라간다. 달리면서 지도를 손으로 끌 여유는 없다.
        locationButtonEnable: true,
        // 러닝 중에는 기울이거나 돌릴 일이 없다. 손가락이 미끄러져 화면이
        // 돌아가면 다시 맞추는 것이 일이다.
        rotationGesturesEnable: false,
        tiltGesturesEnable: false,
        indoorEnable: false,
      ),
      onMapReady: (controller) {
        _controller = controller;
        controller.setLocationTrackingMode(NLocationTrackingMode.follow);
        _draw();
      },
    );
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
