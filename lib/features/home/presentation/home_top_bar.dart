import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/home/domain/weather.dart';
import 'package:runiverse/features/home/presentation/home_weather_provider.dart';

/// 홈 맨 위 줄 — 시안 `70:739`(외주 3차).
///
/// 왼쪽은 동네와 날씨(`서울 강남구 · 맑음 18°`), 오른쪽은 알림 종이다. 날씨는
/// 비어 있을 수 있다([HomeWeatherState]).
///
/// ## ⚠️ 알림함의 유일한 입구다
///
/// 하단 탭이 넷으로 고정이라 탭을 더할 자리가 없다. 예전에는 프로필 커버 위에
/// 있었고 그래서 프로필 탭에 점을 얹었는데, 입구를 홈으로 옮기면서 둘 다 뺐다.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    required this.badged,
    required this.onNotifications,
    required this.weather,
    required this.onAskLocation,
    required this.onWeatherSource,
    super.key,
  });

  /// 왼쪽 자리.
  final HomeWeatherState weather;

  /// `위치 켜고 날씨 보기`를 눌렀다.
  final VoidCallback onAskLocation;

  /// 날씨를 눌렀다. 출처 시트를 띄운다 — 라이선스 조건이다(`home_weather_sheet.dart`).
  /// 시트가 그 자리의 날씨 지도를 열도록 누른 날씨를 넘긴다.
  final ValueChanged<HomeWeatherShown> onWeatherSource;

  /// 읽지 않은 알림이 있는가.
  ///
  /// ⚠️ **숫자가 아니라 점이다.** 안 읽은 수가 서버와 어긋날 수 있어
  /// (연동 가이드 2-3) 숫자를 적으면 틀린 숫자를 적게 된다.
  final bool badged;

  final VoidCallback onNotifications;

  /// 날씨 앞 핀을 미리 읽어 둔다. 홈이 세워질 때 한 번 부른다.
  ///
  /// ⚠️ **안 읽어 두면 핀이 글자보다 늦게 붙는다.** 날씨는 홈이 그려지고 1~2초
  /// 뒤에 오는데, 핀 그림은 그때서야 읽기 시작해 약 0.1초 뒤에 따로 뜬다
  /// (에뮬레이터 녹화를 프레임으로 확인). 종은 첫 화면부터 그려져 상관없다.
  ///
  /// 화면에 그리는 것이 아니라 그림 파일을 [svg.cache]에 넣어 둘 뿐이다. 화면의
  /// `SvgPicture.asset`이 같은 키로 찾아 바로 쓴다.
  static Future<void> precacheIcons() =>
      SvgAssetLoader(AppIcons.pathOf(AppIcons.pin)).loadBytes(null);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: switch (weather) {
              HomeWeatherHidden() => const SizedBox.shrink(),
              // ⚠️ 권하는 문구라 날씨보다 한 단계 흐리게 둔다 — 시안에 없는
              // 상태다. 디자인 확인이 필요하다.
              HomeWeatherAsk() => _WeatherButton(
                text: AppStrings.homeWeatherAsk,
                color: colors.textSecondary,
                onTap: onAskLocation,
              ),
              final HomeWeatherShown shown => _WeatherButton(
                text: AppStrings.homeWeather(
                  shown.place,
                  _skyLabel(shown.weather.sky),
                  shown.weather.temperature,
                ),
                semantics: AppStrings.homeWeatherSemantics(
                  shown.place,
                  _skyLabel(shown.weather.sky),
                  shown.weather.temperature,
                ),
                color: colors.textPrimary,
                onTap: () => onWeatherSource(shown),
              ),
            },
          ),
        ),
        _NotificationButton(badged: badged, onTap: onNotifications),
      ],
    );
  }

  static String? _skyLabel(WeatherSky? sky) => switch (sky) {
    null => null,
    WeatherSky.clear => AppStrings.homeWeatherClear,
    WeatherSky.partlyCloudy => AppStrings.homeWeatherPartlyCloudy,
    WeatherSky.cloudy => AppStrings.homeWeatherCloudy,
    WeatherSky.fog => AppStrings.homeWeatherFog,
    WeatherSky.rain => AppStrings.homeWeatherRain,
    WeatherSky.snow => AppStrings.homeWeatherSnow,
    WeatherSky.thunder => AppStrings.homeWeatherThunder,
  };
}

/// 핀 + 글자. 시안 `70:740` — 핀 26, 6 띄우고 SUIT Medium 16.
class _WeatherButton extends StatelessWidget {
  const _WeatherButton({
    required this.text,
    required this.color,
    required this.onTap,
    this.semantics,
  });

  final String text;
  final Color color;
  final VoidCallback onTap;

  /// 없으면 [text]를 읽는다.
  final String? semantics;

  /// 시안의 글리프 크기. 종과 같다.
  static const _glyph = 26.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics ?? text,
      button: true,
      // ⚠️ **누름 동작을 여기에도 단다.** `excludeSemantics`가 아래 `InkWell`의
      // 동작까지 지워서, 없으면 스크린리더가 버튼이라고 읽고도 누르지 못한다.
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.md,
          child: ConstrainedBox(
            // 44 미만은 손가락이 빗나간다(`AppSizes` 주석).
            constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(AppIcons.pin, size: _glyph, color: color),
                // 시안 6. 간격 토큰에 6이 없어 2 + 4로 낸다.
                const SizedBox(width: AppSpacing.space0 + AppSpacing.space1),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypographyV2.body06.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.badged, required this.onTap});

  final bool badged;
  final VoidCallback onTap;

  /// 시안의 글리프 크기.
  static const _glyph = 26.0;

  /// 점의 지름. 탭 바·프로필 커버와 같다.
  static const _dot = 8.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return MergeSemantics(
      child: Semantics(
        // ⚠️ **점을 그림으로만 두면 읽히지 않는다.** 이 단추에는 글자가
        // 없어서 이 라벨이 스크린리더가 가진 전부다.
        label: badged
            ? '${AppStrings.notificationTitle}, '
                  '${AppStrings.notificationUnreadSemantics}'
            : AppStrings.notificationTitle,
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              // 44 미만은 손가락이 빗나간다(`AppSizes` 주석).
              width: AppSizes.touchDefault,
              height: AppSizes.touchDefault,
              // ⚠️ **글리프를 칸의 오른쪽 끝에 붙인다** — 시안은 종과 히어로의
              // 오른쪽 끝이 같다(둘 다 x=398). 가운데에 두면 종이 안쪽으로 9
              // 들어간다.
              //
              // 칸을 오른쪽 여백으로 밀어내서 맞추면 안 된다. 부모 `Row` 밖으로
              // 나간 9는 **그려지기만 하고 눌리지 않는다** — Flutter는 누른
              // 자리가 부모 영역 밖이면 아래로 내려보내지 않는다.
              child: Align(
                alignment: Alignment.centerRight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppIcon(
                      AppIcons.bell,
                      size: _glyph,
                      color: colors.textPrimary,
                    ),
                    if (badged)
                      Positioned(
                        key: const ValueKey('home-notification-badge'),
                        top: -1,
                        right: -1,
                        child: Container(
                          width: _dot,
                          height: _dot,
                          decoration: BoxDecoration(
                            color: colors.error,
                            shape: BoxShape.circle,
                            // 글리프 선 위에 떠 보이게 바탕색 테두리를 둔다.
                            border: Border.all(color: colors.bgBase, width: 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
