import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/widgets/color/aura_orb.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';

/// 스플래시 (S01).
///
/// 로고 에셋이 없어 워드마크는 타입으로만 쓴다.
/// 배경 아우라는 장식 그라디언트가 아니라 **컬러 시스템의 예고**다 —
/// 여러 러닝 색이 섞여 하나가 되는 모습을 여기서 처음 보여준다.
///
/// ## 전환
///
/// 1.6초 뒤 자동으로 넘어가고, 그 전에 화면을 누르면 즉시 넘어간다.
/// **기다림을 강요하지 않는다.**
///
/// ## 자동 로그인
///
/// 화면이 떠 있는 1.6초 동안 저장된 토큰을 읽는다. 다 읽고 나서 갈림길을 정한다 —
/// **로그인 상태면 홈, 아니면 온보딩.**
///
/// 읽기가 1.6초보다 오래 걸리거나 사용자가 먼저 화면을 누르면 그 순간 기다린다.
/// 확인하지 않은 채로 온보딩에 보내면 로그인한 사람이 다시 로그인하게 된다.
///
/// ⚠️ 지금 저장소는 메모리라 앱을 끄면 비워진다. 그래서 실제로는 항상 온보딩으로 간다.
/// `flutter_secure_storage` 구현이 들어오면 이 코드가 그대로 살아난다.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  /// 와이어프레임이 정한 체류 시간.
  static const _dwell = Duration(milliseconds: 1600);

  /// 아우라에 섞을 색. 서로 다른 러닝 특성 4개를 골라 대비를 만든다.
  static const _auraHues = [
    RunHue.speed,
    RunHue.distance,
    RunHue.cadence,
    RunHue.endurance,
  ];

  Timer? _timer;

  /// 토큰 확인이 끝났는지. 타이머와 탭 어느 쪽이 먼저 와도 이것을 기다린다.
  late final Future<void> _restored;

  /// 두 번 이동하는 것을 막는다. 타이머와 탭이 거의 동시에 올 수 있다.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _restored = ref.read(authControllerProvider.notifier).restore();
    _timer = Timer(_dwell, _goNext);
  }

  @override
  void dispose() {
    // 타이머를 살려두면 화면이 사라진 뒤 go()가 불려 예외가 난다.
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();

    await _restored;
    if (!mounted) return;

    final signedIn = ref.read(authControllerProvider) is AuthSignedIn;
    context.go(signedIn ? AppRoutes.home : AppRoutes.onboardingIntro);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      body: GestureDetector(
        // 아무 데나 눌러도 넘어간다. 버튼을 따로 두지 않는다.
        behavior: HitTestBehavior.opaque,
        onTap: _goNext,
        child: Center(
          child: SizedBox.square(
            dimension: _auraSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AuraOrb(
                  colors: [
                    for (final hue in _auraHues) RunPalette.color(hue, 2),
                  ],
                  size: _auraSize,
                  // 와이어프레임이 정한 값. 살짝 눌러 워드마크에 시선을 남긴다.
                  vitality: 0.7,
                ),

                // 아우라 위 텍스트에는 스크림이 필수다(디자인 시스템 §1-4).
                // 러닝 색은 채도가 높아 그냥 얹으면 대비 기준을 통과하지 못한다.
                // 가운데만 덮고 가장자리 색은 살려둔다.
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        colors.bgScrim,
                        colors.bgScrim.withValues(alpha: 0),
                      ],
                      stops: const [0.25, 0.75],
                    ),
                  ),
                  child: const SizedBox.square(dimension: _auraSize),
                ),

                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.brandName,
                      style: AppTypography.display.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      AppStrings.brandTagline,
                      style: AppTypography.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 아우라 지름. 412 캔버스 기준 Figma 실측값이다.
const _auraSize = 360.0;
