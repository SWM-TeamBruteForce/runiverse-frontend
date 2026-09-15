import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_motion.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
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
/// ⚠️ **`core`에 있는 이유는 화면 둘이 함께 쓰기 때문이다.**
///
/// 러닝 중 화면(session)과 러닝 결과(record)가 같은 지도를 그린다. 한쪽
/// feature의 `presentation/`을 다른 쪽에서 import할 수 없어 여기로 올렸다
/// (CLAUDE.md "공유가 필요하면 `core/widgets/`로 올린다").
///
/// `GeoPoint`(session/domain)에만 기대고 그 밖의 feature 코드는 모른다 —
/// `core/storage/sign_in_memory_store.dart`가 `auth/domain`을 쓰는 것과 같다.
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

  /// 지도에 얹어 둔 구간별 선. **다시 만들지 않고 좌표만 갈아 끼운다.**
  final _overlays = <NPathOverlay>[];

  /// 각 구간을 마지막으로 그렸을 때의 좌표 수. 안 바뀐 구간은 건드리지 않는다.
  final _drawnLengths = <int>[];

  /// [_draw]가 도는 중인가. 끝나기 전에 또 불리면 [_pending]으로 미룬다.
  bool _drawing = false;
  bool _pending = false;

  @override
  void didUpdateWidget(RunMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ⚠️ **`!=`로 비교하면 안 된다.** `List`의 `!=`는 내용이 아니라 신원을
    // 본다. `track` 게터가 부를 때마다 새 리스트를 만들므로 그 조건은 **항상
    // 참**이고, 좌표가 하나도 안 늘어도 다시 그린다. 이 화면은 초당 두 번
    // (티커 1 + GPS 1) 리빌드되므로 그만큼 헛일을 한다.
    if (!_sameShape(widget.track, oldWidget.track)) _draw();
  }

  /// 그릴 것이 그대로인가.
  ///
  /// 길이만 본다. **좌표는 뒤에 붙기만 하고 이미 들어간 것은 바뀌지 않으므로**
  /// 길이가 같으면 내용도 같다. 전부 비교하면 초당 두 번 수천 점을 훑는다.
  static bool _sameShape(List<List<GeoPoint>> a, List<List<GeoPoint>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
    }
    return true;
  }

  /// 지도 둘레에 두는 빈 띠.
  ///
  /// ⚠️ **이것이 부모가 잡을 수 있는 유일한 통로다.** [NaverMap]은
  /// `forceGesture`로 제스처를 먼저 가져가므로, 지도가 상자를 꽉 채우면
  /// 부모의 스와이프·스크롤이 **어디에서도** 먹지 않는다. 러닝 중 화면은
  /// `PageView`, 결과 화면은 `ListView` 안이다.
  ///
  /// 16은 엄지로 잡기 빠듯하고, 32는 지도를 너무 먹는다.
  static const _gutter = AppSpacing.space6;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasNaverMapClientId) return const _MapUnavailable();

    return Padding(
      padding: const EdgeInsets.all(_gutter),
      child: Stack(
        children: [
          // 플랫폼 뷰가 붙기 전 한 프레임을 덮는다.
          //
          // ⚠️ **타일 로딩 중의 흰 격자는 이걸로 덮이지 않는다.** 그건 지도가
          // 직접 그리는 것이라 이 바탕 위에 얹힌다 — `android/app/src/main/res`의
          // `navermap_default_background_light` 오버라이드가 그쪽을 맡는다
          // (`docs/implementation-notes.md`).
          //
          // ⚠️ `context.appColors`가 아니라 **[AppColors.dark]를 직접 쓴다.**
          // 지도는 커스텀 야간 스타일이라 앱이 라이트 테마여도 어둡다 —
          // 테마를 따라가면 라이트에서 밝은 바탕이 깔려 더 눈에 띈다.
          Positioned.fill(child: ColoredBox(color: AppColors.dark.bgBase)),
          Positioned.fill(child: _map()),
          // 지도 위에 얹는다. **플러터 위젯이라 탭이 제스처 아레나와
          // 무관하다** — 부모가 드래그를 가져가도 이 버튼은 항상 눌린다.
          Positioned(
            right: AppSpacing.space3,
            bottom: AppSpacing.space3,
            child: _ZoomControls(controller: _controller),
          ),
        ],
      ),
    );
  }

  Widget _map() {
    return NaverMap(
      // ⚠️ **스크롤 가능한 부모 안에서 지도가 제스처를 먼저 받게 한다.**
      //
      // 이것이 `false`(기본값)면 플러그인이 `EagerGestureRecognizer`를 달지
      // 않아, 제스처 아레나를 부모가 이긴다. 러닝 중 화면은 `PageView`,
      // 결과 화면은 `ListView` 안이라 **드래그와 핀치가 지도에 닿지 않았다** —
      // 탭만 통과해서 더블탭 확대만 되던 이유다.
      //
      // ⚠️ 대가가 있다. 지도 위에서는 **부모의 스와이프·스크롤이 막힌다.**
      // 지도 밖을 잡으면 되지만 결과 화면은 지도 카드가 폭을 다 쓴다.
      forceGesture: true,
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
        // SDK 기본 버튼이다. 탭할 때마다 추적 모드가 순환한다
        // (`follow` → `face` → …). 직접 만든 버튼으로 `follow`나 `face`에
        // 묶어 봤지만, 어느 쪽으로 고정해도 잃는 것이 있어 되돌렸다.
        locationButtonEnable: true,
        // 손으로 돌려 볼 수 있게 둔다. 지도를 자유롭게 보려는 쪽을 택했다 —
        // 틀어졌으면 현위치 버튼으로 되돌린다.
        rotationGesturesEnable: true,
        tiltGesturesEnable: false,
        indoorEnable: false,
      ),
      // ⚠️ 스타일이 안 먹어도 SDK는 **조용히 기본 스타일로 떨어진다.**
      // 콜백이 없으면 "왜 밝지"에서 멈춘다 — 실패 이유를 듣는다.
      onCustomStyleLoadFailed: (error) =>
          debugPrint('[naver-map] 커스텀 스타일 실패 · id=$_styleId · $error'),
      onMapReady: (controller) {
        // ⚠️ `setState`가 필요하다. 줌 버튼이 이 컨트롤러를 받아야 눌린다 —
        // 그냥 대입하면 버튼은 `null`을 든 채로 남는다.
        if (mounted) setState(() => _controller = controller);
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
  /// ## 지우지 않는다
  ///
  /// 예전에는 전부 지우고 다시 얹었다. 그러면 지운 뒤 다시 얹기 전까지
  /// **경로가 없는 프레임**이 생기고, 초당 두 번 반복되니 선이 깜빡인다.
  /// 지금은 이미 얹어 둔 선의 좌표만 갈아 끼운다([NPathOverlay.setCoords]).
  ///
  /// **바뀐 구간만 손댄다.** 좌표는 마지막 구간에만 붙으므로, 일시정지로
  /// 끝난 구간들은 다시 그리지 않는다 — 30분 전에 끝난 구간을 초당 두 번씩
  /// 다시 얹던 것이 사라진다.
  Future<void> _draw() async {
    // ⚠️ **겹쳐 돌면 안 된다.** 초당 두 번 불리는데 안에 `await`이 있어,
    // 가드가 없으면 두 번이 뒤엉켜 선이 어긋난다.
    if (_drawing) {
      _pending = true;
      return;
    }

    _drawing = true;
    try {
      do {
        _pending = false;
        await _apply();
      } while (_pending);
    } finally {
      _drawing = false;
    }
  }

  Future<void> _apply() async {
    final controller = _controller;
    if (controller == null) return;

    final segments = [
      for (final segment in widget.track)
        if (segment.length > 1) segment,
    ];

    // 구간이 줄었다 = 새 러닝이 시작됐다. **이때만** 지운다.
    if (segments.length < _overlays.length) {
      await controller.clearOverlays(type: NOverlayType.pathOverlay);
      _overlays.clear();
      _drawnLengths.clear();
    }

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];

      // 길이가 그대로면 좌표도 그대로다. 지도를 건드릴 이유가 없다.
      if (i < _overlays.length && _drawnLengths[i] == segment.length) continue;

      final coords = [
        for (final point in segment) NLatLng(point.latitude, point.longitude),
      ];

      if (i < _overlays.length) {
        _overlays[i].setCoords(coords);
        _drawnLengths[i] = segment.length;
        continue;
      }

      final overlay = NPathOverlay(
        id: 'run-$i',
        coords: coords,
        width: 6,
        // ⚠️ 색을 토큰에서 가져오지 못한다. 오버레이는 위젯 트리 밖이라
        // `context.appColors`를 읽을 수 없다. 값은 `AppColors.primary`와
        // 같게 유지한다 — 한쪽만 바뀌면 지도 선만 다른 색이 된다.
        color: const Color(0xFF4C6FFF),
        outlineColor: const Color(0xFF4C6FFF),
      );
      _overlays.add(overlay);
      _drawnLengths.add(segment.length);
      await controller.addOverlay(overlay);
    }
  }
}

/// 지도 위에 얹는 줌 버튼.
///
/// ## 왜 SDK 위젯을 쓰지 않았나
///
/// 패키지의 `NaverMapZoomControlWidget`은 안에서 Material 아이콘
/// (`Icons.add`·`Icons.remove`)과 `Colors.grey.shade900` 같은 값을 직접 쓴다.
/// 프로젝트는 **Lucide 전용**이고 색은 토큰에서만 온다.
///
/// 줌 계산은 그 위젯이 하던 방식을 그대로 따른다 — 현재 줌을 **반올림한 뒤**
/// ±1이다. 애니메이션 도중에 눌러도 정수 레벨로 떨어진다.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.controller});

  /// 지도가 준비되기 전에는 `null`이다. 그동안 버튼은 눌리지 않는다.
  final NaverMapController? controller;

  static const _size = 40.0;

  /// 한 번에 움직이는 줌 폭.
  ///
  /// **1단계는 배율이 2배로 뛴다.** 지도가 확 튀어 어디를 보고 있었는지
  /// 놓친다. 0.5면 약 1.4배라 눈이 따라간다.
  ///
  /// ⚠️ 눈금에 맞춰 반올림한 뒤 더한다. 핀치로 16.3 같은 값이 된 상태에서
  /// 그냥 더하면 16.8·17.3처럼 어긋난 값이 쌓인다.
  static const _step = 0.5;

  Future<void> _zoomBy(int delta) async {
    final map = controller;
    if (map == null) return;

    final now = await map.getCameraPosition().then((c) => c.zoom);
    final snapped = (now / _step).round() * _step;

    await map.updateCamera(
      NCameraUpdate.withParams(zoom: snapped + delta * _step)
        ..setReason(NCameraUpdateReason.control)
        ..setAnimation(duration: AppMotion.slow),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgElevated,
        border: Border.all(color: colors.borderStrong),
        borderRadius: AppRadius.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            icon: LucideIcons.plus,
            label: AppStrings.mapZoomIn,
            onTap: controller == null ? null : () => _zoomBy(1),
            size: _size,
          ),
          SizedBox(
            width: _size,
            height: 1,
            child: ColoredBox(color: colors.borderStrong),
          ),
          _ZoomButton(
            icon: LucideIcons.minus,
            label: AppStrings.mapZoomOut,
            onTap: controller == null ? null : () => _zoomBy(-1),
            size: _size,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.size,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: AppSpacing.space5,
            color: onTap == null ? colors.textDisabled : colors.textPrimary,
          ),
        ),
      ),
    );
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
