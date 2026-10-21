import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/config/store_links.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// 최소 버전에 못 미친다. **여기서 나갈 길은 스토어뿐이다.**
///
/// ## ⚠️ 닫을 수 없어야 한다
///
/// 이 상태에서는 서버가 `/app/version`을 뺀 **모든 요청을 403으로 거절한다.**
/// 빠져나가 봐야 아무 화면도 제대로 뜨지 않고, 사용자는 "앱이 고장났다"로
/// 읽는다. 뒤로가기도 막는다([PopScope]).
///
/// 라우터 밖에서 앱 전체를 덮으므로 [Navigator]가 없다 — 라우트로 두면
/// `LaunchGate`의 자동 이동이나 딥링크로 벗어날 수 있다.
class AppUpdatePage extends StatelessWidget {
  const AppUpdatePage({super.key});

  /// ## ⚠️ `PopScope`를 두지 않는다 — **여기서는 동작하지 않는다**
  ///
  /// 이 화면은 `MaterialApp.builder`에 있어 [Navigator]보다 **위**다. `PopScope`는
  /// 가장 가까운 [ModalRoute]에 자신을 등록하는데 그런 조상이 없어 **아무 일도
  /// 하지 않는다.** 실제로 뒤로가기를 누르면 그대로 앱이 내려간다(2026-10-21
  /// 에뮬레이터 확인). 막아 준다고 적힌 죽은 코드는 없는 것보다 나쁘다.
  ///
  /// **앱이 내려가는 것은 막을 일이 아니다.** 명세의 "닫을 수 없다"는 *이 화면을
  /// 치우고 앱을 쓰는 것*을 막으라는 뜻이고, 그쪽은 게이트가 라우터의 결과를
  /// 통째로 갈아 끼워 길 자체가 없다. 다시 켜면 게이트가 또 막는다.
  @override
  Widget build(BuildContext context) {
    return const _UpdateView(
      icon: LucideIcons.arrowBigUpDash,
      title: AppStrings.updateRequiredTitle,
      body: AppStrings.updateRequiredBody,
      dismissible: false,
    );
  }
}

/// 업데이트 안내와 강제 화면이 같은 뼈대를 쓴다.
class _UpdateView extends StatelessWidget {
  const _UpdateView({
    required this.icon,
    required this.title,
    required this.body,
    required this.dismissible,
  });

  final IconData icon;
  final String title;
  final String body;

  /// 닫을 수 있는가. 권장 안내만 `true`다.
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: AppSpacing.space10, color: colors.primary),
                const SizedBox(height: AppSpacing.space5),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypographyV2.heading05.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: AppTypographyV2.body15.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space7),
                AppButtonV2(
                  label: AppStrings.updateCta,
                  onPressed: () => openStore(context),
                ),
                if (dismissible) ...[
                  const SizedBox(height: AppSpacing.space3),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      AppStrings.updateLater,
                      style: AppTypographyV2.body15.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 스토어를 연다.
///
/// ## ⚠️ 실패를 삼키지 않는다
///
/// [launchUrl]은 열 수 없을 때 `false`를 돌려주거나 던진다. 그대로 두면
/// **아무 일도 일어나지 않는 버튼**이 되는데, 이 화면에는 그 버튼 하나뿐이라
/// 사용자가 갇힌 채로 아무것도 할 수 없다(`openLegalDocument`와 같은 판단).
Future<void> openStore(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);

  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(StoreLinks.current),
      // 스토어는 **앱 밖**에서 연다. 인앱 브라우저로 열면 스토어 앱으로
      // 넘어가지 못하고 웹 페이지만 뜬다.
      mode: LaunchMode.externalApplication,
    );
  } on Object catch (error) {
    debugPrint('[version] 스토어를 열지 못했다 · $error');
  }
  if (opened) return;

  messenger.showSnackBar(
    const SnackBar(content: Text(AppStrings.updateStoreFailed)),
  );
}
