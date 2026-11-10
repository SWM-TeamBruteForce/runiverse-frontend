import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/app_update/presentation/app_update_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/session/domain/run_resume.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 스플래시 (S01).
///
/// 러너 심볼과 앱 이름만 둔다. 심볼은 앱 아이콘·워치 앱과 같은 그림이다.
///
/// ## 배치
///
/// 심볼·이름 묶음은 **연결 실패 안내가 떠도 움직이지 않는다.** 안내는 묶음
/// 아래 남은 자리에서만 자란다 — 한 `Column`에 넣고 가운데 정렬하면 안내가
/// 생기는 순간 묶음 전체의 가운데가 바뀌어 로고가 위로 튄다.
///
/// 배경은 OS 시작 화면(안드로이드 `launch_background.xml`·`values-v31`,
/// iOS `LaunchScreen.storyboard`)과 같은 색이다. 바꾸면 그쪽도 함께 바꾼다.
///
/// ## 전환
///
/// 1.6초 뒤 자동으로 넘어가고, 그 전에 화면을 누르면 즉시 넘어간다.
/// **기다림을 강요하지 않는다.**
///
/// ## 자동 로그인
///
/// 화면이 떠 있는 1.6초 동안 저장된 토큰으로 세션을 되살린다.
/// 다 읽고 나서 갈림길을 정한다.
///
/// ```
/// 토큰이 살아 있다  → 홈 (프로필을 안 채웠으면 홈의 유도 카드가 알린다)
/// 토큰이 만료됐다   → 로그인 (소개는 건너뛴다. 처음 온 사람이 아니다)
/// 저장된 것이 없다  → 온보딩 소개
/// 판정하지 못했다   → 이 화면에 머물며 재시도
/// ```
///
/// 읽기가 1.6초보다 오래 걸리거나 사용자가 먼저 화면을 누르면 그 순간 기다린다.
/// 확인하지 않은 채로 온보딩에 보내면 로그인한 사람이 다시 로그인하게 된다.
///
/// ## 오프라인은 허용하지 않는다
///
/// 서버에 닿지 못하면 앱에 들어가지 못한다. **판정에 실패한 것과 판정에 성공한 것은
/// 다른 상태다** — 저장된 값을 믿고 들여보내면 둘을 같이 취급하게 된다.
/// 상태가 [AuthUnknown]에 머무는 것이 곧 "아직 못 정했다"이므로 상태를 더 만들지 않는다.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  /// 와이어프레임이 정한 체류 시간.
  static const _dwell = Duration(milliseconds: 1600);

  Timer? _timer;

  /// 버전 확인과 토큰 복원이 끝났는지. 타이머와 탭 어느 쪽이 먼저 와도
  /// 이것을 기다린다. 재시도하면 새 Future로 갈아 끼운다.
  late Future<void> _ready;

  /// 두 번 이동하는 것을 막는다. 타이머와 탭이 거의 동시에 올 수 있다.
  bool _leaving = false;

  /// 판정에 실패했다. 확인이 끝났는데도 상태가 정해지지 않은 경우다.
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _ready = _prepare();
    _timer = Timer(_dwell, _goNext);
  }

  /// 들어갈 준비. **버전 확인이 토큰 복원보다 먼저다.**
  ///
  /// ## ⚠️ 순서가 규칙이다
  ///
  /// 최소 버전에 못 미치는 앱은 서버가 `/app/version`을 뺀 **모든 요청을
  /// 403으로 거절한다.** 토큰부터 복원하면 그 갱신 요청이 403으로 떨어지고,
  /// 앱은 "세션이 죽었다"로 읽어 **업데이트가 필요한 사람을 로그인 화면으로**
  /// 보낸다. 거기서 로그인해도 또 403이다.
  ///
  /// 버전을 먼저 보면 막힌 앱은 게이트가 덮으므로 그 길로 가지 않는다.
  Future<void> _prepare() async {
    await ref.read(appUpdateProvider.notifier).check();
    await ref.read(authControllerProvider.notifier).restore();
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

    await _ready;
    if (!mounted) return;

    // ⚠️ **판정 없이 들여보내지 않는다**(명세). 서버에 닿지 못했으면 이 화면에
    // 머물며 다시 시도할 길을 준다 — 구버전 앱을 그냥 통과시키면 안에서
    // 403만 받으면서 이유를 모른다.
    if (ref.read(appUpdateProvider) is! AppUpdateChecked) {
      setState(() {
        _offline = true;
        _leaving = false;
      });
      return;
    }

    switch (ref.read(authControllerProvider)) {
      case AuthSignedIn():
        // **자동 로그인은 폼으로 밀지 않는다.** 앱을 열자마자 입력 폼이 뜨는 것이
        // 당황스럽고, 돌아온 사람은 자기 계획이 있는데 폼이 그것을 가로막는다.
        //
        // 프로필을 안 채운 사람은 홈의 유도 카드가 맡는다. 카드를 켜는 값은
        // `restore()`가 부른 `/users/me`에서 온다 — 저장된 값이 아니다.
        //
        // 폼으로 보내는 것은 **인증 직후**(가입 · 이메일 로그인 · 카카오)뿐이다.
        //
        // ⚠️ **신체 정보를 미리 읽어 둔다.** 앱을 다시 켜고 곧바로 러닝에
        // 들어가면(아래 `running` 복구가 그렇다) 러닝 중에 처음 읽게 되어
        // 칼로리가 잠깐 `--`로 보인다. 기다리지 않는다 — 실패해도 갈 곳은
        // 그대로고, `bodyProfileProvider`가 알아서 다시 읽는다.
        unawaited(ref.read(bodyProfileProvider.notifier).refresh());
        await _goByStatus();
      case AuthSignedOut(:final returning):
        // 로그인했던 적이 있으면 소개를 건너뛴다.
        context.go(returning ? AppRoutes.signIn : AppRoutes.onboardingIntro);
      case AuthUnknown():
        // 서버에 닿지 못했다. 이 화면에 머물며 다시 시도할 길을 준다.
        setState(() {
          _offline = true;
          _leaving = false;
        });
    }
  }

  /// 서버가 아는 상태를 보고 갈 곳을 정한다.
  ///
  /// ## ⚠️ 못 읽어도 홈으로 보낸다
  ///
  /// 여기서 막으면 **상태 조회 하나가 앱 전체를 잠근다.** 진행 중인 러닝이 있어도
  /// 홈에서 다시 물을 기회가 있고(포그라운드 복귀), 로그인은 이미 끝났다.
  /// 스플래시에 사람을 묶어두는 쪽이 더 나쁘다.
  Future<void> _goByStatus() async {
    final status = await ref.read(userStatusProvider.notifier).refresh();
    if (!mounted) return;

    // 못 읽었으면 홈이다.
    if (status == null) {
      context.go(AppRoutes.home);
      return;
    }

    switch (RunResume.of(status)) {
      case RunResume.home:
        context.go(AppRoutes.home);
      // ⚠️ **`go`가 아니라 홈을 깔고 그 위에 얹는다.** 곧바로 러닝 화면을
      // 띄우면 뒤로가기로 갈 곳이 없어 앱이 닫힌다.
      case RunResume.soloPrepare:
        context.go(AppRoutes.home);
        unawaited(context.push(AppRoutes.runPrepare));
      case RunResume.running:
        // ⚠️ 러닝 화면은 스스로 붙지 않는다. 여기서 다시 붙고 서버가 정한
        // 출발 시각부터 이어 잰다. 이름·거리는 `RUNNING_STARTED` 스냅샷이
        // 실어 온다.
        //
        // ⚠️ **솔로도 다시 붙인다.** 예전에는 솔로를 방 새로 만드는 경로
        // (409 → 정리)에 맡겼는데, 그 경로는 홈에서 시작해야 닿는다. 복구는
        // 러닝 화면으로 바로 들어오므로 닿을 길이 없어 "서버에 연결하는
        // 중이에요"에서 영영 멈췄다.
        if (status case UserStatusRunning()) {
          unawaited(
            ref
                .read(runningConnectionProvider.notifier)
                .reopen(
                  status.runningRoomId,
                  targetDistanceMeters: status.targetDistanceMeters,
                  matched: !status.isSolo,
                  type: status.type,
                ),
          );
          unawaited(
            ref
                .read(runSessionControllerProvider.notifier)
                .startWhenReady(since: status.scheduledStartAt),
          );
        }
        context.go(AppRoutes.home);
        unawaited(context.push(AppRoutes.runSession));
    }
  }

  /// 재시도. 화면을 떠나지 않고 갱신을 다시 부른다.
  Future<void> _retry() async {
    setState(() {
      _offline = false;
      _ready = _prepare();
    });
    await _goNext();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Scaffold(
      // 앱 테마는 아직 옛 세대라 scaffold 배경이 푸른 회색(#0B0E14)이다.
      // 옮긴 화면은 자기 배경을 직접 깐다 — 전역 테마를 바꾸는 것은
      // 마지막 화면이 넘어온 뒤의 일이다.
      backgroundColor: colors.bgBase,
      body: GestureDetector(
        // 아무 데나 눌러도 넘어간다. 버튼을 따로 두지 않는다.
        // 판정에 실패했을 때만 막는다 — 갈 곳이 없는데 탭을 받으면 아무 일도
        // 일어나지 않아 고장난 것으로 읽힌다. 그때는 재시도 버튼이 유일한 길이다.
        behavior: HitTestBehavior.opaque,
        onTap: _offline ? null : _goNext,
        child: SizedBox.expand(
          // 묶음 위아래에 남는 자리를 46:54로 나눈다. 시안은 묶음 가운데를
          // 화면 높이 46%에 두는데, 이렇게 나누면 묶음 높이의 4%(약 5)만큼
          // 아래다. 묶음 높이를 상수로 박지 않으려고 이쪽을 택했다.
          //
          // ⚠️ iOS `LaunchScreen.storyboard`가 같은 식으로 묶음을 놓는다.
          // 비율을 바꾸면 그쪽 제약도 함께 바꾼다.
          child: Column(
            children: [
              const Spacer(flex: 46),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _markWidth,
                    child: AspectRatio(
                      aspectRatio: _markAspectRatio,
                      // 흰 쪽만 글자색으로 칠하고 파란 쪽은 제 색을 지킨다.
                      // 그래서 한 장이 아니라 두 장이다.
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SvgPicture.asset(
                            'assets/brand/runiverse_mark_neutral.svg',
                            colorFilter: ColorFilter.mode(
                              colors.textPrimary,
                              BlendMode.srcIn,
                            ),
                          ),
                          SvgPicture.asset(
                            'assets/brand/runiverse_mark_blue.svg',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  Text(
                    AppStrings.brandName,
                    style: AppTypographyV2.heading02.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),

              // 안내는 이 안에서만 자란다. 위의 묶음을 밀지 않는다.
              Expanded(
                flex: 54,
                child: Align(
                  alignment: Alignment.topCenter,
                  // ⚠️ 작은 화면에서 글자를 키우면 안내가 이 칸보다 길어진다.
                  // 스크롤이 없으면 재시도 버튼이 화면 밖으로 밀려 갇힌다.
                  child: _offline
                      ? SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.space6,
                              AppSpacing.space9,
                              AppSpacing.space6,
                              0,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  AppStrings.splashOffline,
                                  style: AppTypographyV2.body05.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.space1),
                                Text(
                                  AppStrings.splashOfflineHint,
                                  textAlign: TextAlign.center,
                                  style: AppTypographyV2.body12.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.space4),
                                // 문구 바로 아래 붙는 버튼이라 compact 다.
                                // regular(56)는 화면 하단 CTA 용이다.
                                AppButtonV2(
                                  label: AppStrings.splashRetry,
                                  variant: AppButtonV2Variant.secondary,
                                  size: AppButtonV2Size.compact,
                                  expand: false,
                                  onPressed: _retry,
                                ),
                              ],
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 심볼 폭. 412 캔버스 기준 시안 값이다.
const _markWidth = 80.0;

/// 심볼 가로세로 비. SVG `viewBox`(83.28 × 72.27)와 같다.
const _markAspectRatio = 83.28 / 72.27;
