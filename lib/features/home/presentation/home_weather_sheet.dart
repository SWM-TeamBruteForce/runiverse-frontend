import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/legal_document.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/home/domain/weather.dart';

/// 홈 날씨의 출처. 날씨를 누르면 뜬다.
///
/// ## ⚠️ 지우지 않는다 — 라이선스 조건이다
///
/// Open-Meteo API 데이터는 CC BY 4.0이고, **데이터를 보여 주는 자리 옆에
/// 링크를 두라**고 한다(open-meteo.com/en/licence). 위 줄에 글자를 더하지 않고
/// 날씨 자체를 누르면 출처가 뜨게 했다.
///
/// 링크는 홈페이지가 아니라 **Open-Meteo 날씨 지도의 이 자리**다. 날씨를
/// 누른 사람은 더 자세한 날씨를 보려는 것이라, 소개 페이지보다 맞다.
Future<void> showHomeWeatherSheet(
  BuildContext context, {
  required double latitude,
  required double longitude,
}) => showModalBottomSheet<void>(
  context: context,
  // ⚠️ **탭 바 위로 띄운다.** 홈 탭의 내비게이터에 띄우면 떠 있는 탭 바가
  // 시트 아래를 덮어 버튼이 가린다(에뮬레이터 확인).
  useRootNavigator: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _HomeWeatherSheet(
    source: openMeteoMapUrl(latitude: latitude, longitude: longitude),
  ),
);

class _HomeWeatherSheet extends StatelessWidget {
  const _HomeWeatherSheet({required this.source});

  /// 출처 링크 — 이 자리를 가운데로 연 Open-Meteo 날씨 지도.
  final String source;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.bgElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // 초대 시간 시트(`invite_time_sheet.dart`)와 같은 틀이다.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space5,
          AppSpacing.space3,
          AppSpacing.space5,
          AppSpacing.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: AppRadius.full,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              AppStrings.homeWeatherSource,
              style: AppTypographyV2.body05.copyWith(color: colors.textStrong),
            ),
            const SizedBox(height: AppSpacing.space4),
            AppButtonV2(
              label: AppStrings.homeWeatherSourceOpen,
              variant: AppButtonV2Variant.secondary,
              // 브라우저가 열리는 동안 시트는 남겨 둔다. 돌아오면 닫으면 된다.
              onPressed: () => openLegalDocument(context, source),
            ),
          ],
        ),
      ),
    );
  }
}
