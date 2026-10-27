import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 매칭을 기다리는 중 — 시안 `158:2951`.
///
/// 동심원 한가운데에 내가 있고, 함께 달릴 사람들이 둘레에 떠 있다.
///
/// ## ⚠️ 둘레 자리는 시안을 그대로 베끼지 않았다
///
/// 시안은 세 사람을 **손으로 배치했다** — 반지름은 165~179로 비슷한데 각도가
/// 제각각이고(-23° · 122° · 203°), 크기도 67·78·103으로 다르다.
///
/// 우리 방은 **2~4명**이라 둘레에 설 사람이 1~3명으로 변한다. 그래서
/// **각도는 시안이 쓴 셋을 자리표로 두고, 그보다 많아지면 고르게 나눈다.**
///
/// ⚠️ **크기와 불투명도는 모두 같게 뒀다.** 시안은 깊이를 내려고 달리하는데,
/// 우리 목록은 서버가 준 순서라 **앞사람이 크게 그려지면 순위처럼 읽힌다.**
/// CLAUDE.md 가 파티원에 순위를 붙이지 말라고 못 박는다 — 동행이지 경쟁이
/// 아니다. 디자인 확인이 필요하다.
///
/// ## ⚠️ 움직이는 것은 프로필 사진 원뿐이다
///
/// 동심원 배경·글자·버튼은 시안 그대로 가만히 있는다. 움직임을 더한 것은
/// 셋뿐이다.
///
/// - **둘레 원이 맴돈다** — 18초에 한 바퀴. 보고 있으면 움직이는 게 보이고,
///   곁눈으로는 가만한 속도다. 대기를 초조하게 만들 자리가 아니다.
/// - **가운데 내 원이 숨 쉰다** — 테두리 빛이 들고 난다. 원 자체는 손대지
///   않는다. 사진이 커졌다 작아지면 출렁이는 것으로 보인다.
/// - **파티원이 늘면 한가운데 축하가 뜬다** — 1.92초. 그동안에도 궤도는
///   멈추지 않는다.
///
/// 확정(`HomeConfirmed`)에서는 이 모두가 없다. **멈춤 자체가 "끝났다"는
/// 신호다** — 거기서는 참여자가 줄을 서고 화면이 고요해진다.
class HomeWaiting extends StatefulWidget {
  const HomeWaiting({
    required this.room,
    required this.onLobby,
    this.myUserId,
    this.myNickname,
    this.myPhotoUrl,
    super.key,
  });

  final RoomInfo room;

  /// 로비로 들어간다. 시안의 CTA 는 잠겨 있지만, 들어갈 길은 남겨 둔다.
  final VoidCallback onLobby;

  /// 나를 둘레에서 빼고, **가운데에 그릴 내 줄을 찾는 데** 쓴다.
  ///
  /// ⚠️ **서버가 나를 명단에 넣는지 아닌지와 무관하게 맞는다.** 넣으면
  /// 빠지고, 안 넣으면 뺄 것이 없다 — 그때는 아래 두 값으로 물러선다.
  final String? myUserId;

  /// 명단에 내가 없을 때 쓸 이름. 출처는 `GET /users/me`(36번)다.
  final String? myNickname;

  /// ⚠️ **지금은 늘 `null`이다.** 36번 응답에 `profileImageUrl`이 없다 —
  /// `userId`·`email`·`loginType`·`nickname`·`isOnboarded`뿐이다. 서버가
  /// 필드를 더하는 날 살아나라고 자리만 남긴다.
  final String? myPhotoUrl;

  /// 시안 `158:2952`의 높이.
  static const _height = 452.0;

  /// 가운데 내 사진. 시안 `158:2969`.
  static const _mySize = 135.0;

  /// 둘레 사람들의 크기와 궤도 반지름.
  static const _otherSize = 80.0;
  static const _orbit = 165.0;

  /// 시안이 쓴 세 각도(도). 넷째부터는 고르게 나눈다.
  static const _angles = [-22.9, 121.8, 202.8];

  /// 둘레가 한 바퀴 도는 데 걸리는 시간.
  ///
  /// ⚠️ **모션 토큰에 없는 값이다.** `AppMotion`의 가장 긴 것이 1.2초라
  /// 여기 쓸 눈금이 없다. 보고 있으면 움직이는 게 보이고 곁눈으로는 가만해
  /// 보이는 속도로 골랐다 — 반지름 165에서 초당 약 58px이다.
  static const _orbitPeriod = Duration(seconds: 18);

  /// 가운데 원이 숨 쉬는 주기. 궤도와 배수 관계가 아니라 둘이 맞물려
  /// 반복하는 것처럼 보이지 않는다.
  static const _pulsePeriod = Duration(milliseconds: 2600);

  /// 축하가 머무는 시간. 등장 320(`drop`) · 유지 1400 · 퇴장 200(`base`).
  static const _celebrateHold = Duration(milliseconds: 1400);

  @override
  State<HomeWaiting> createState() => _HomeWaitingState();
}

class _HomeWaitingState extends State<HomeWaiting>
    with TickerProviderStateMixin {
  /// ⚠️ **컨트롤러를 위젯 위쪽에서 들고 있어야 한다.** 파티원이 늘 때마다
  /// 새로 만들면 회전이 0부터 다시 돌아 원이 눈에 띄게 튄다. 방이 바뀌어도
  /// 이것은 그대로 돈다.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: HomeWaiting._orbitPeriod,
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: HomeWaiting._pulsePeriod,
  )..repeat(reverse: true);

  /// 지금 축하하고 있는 사람. `null`이면 아무것도 안 뜬다.
  RoomPlayer? _celebrating;
  Timer? _celebrateTimer;

  /// 직전에 본 둘레 사람들. **늘었는지 보려고** 들고 있는다.
  ///
  /// ⚠️ **`late`로 두면 안 된다.** `late` 초기화는 선언할 때가 아니라 **처음
  /// 읽을 때** 돈다. 처음 읽는 곳이 [didUpdateWidget]이라, 그 시점의
  /// `widget.room`은 이미 **새 방**이다 — 늘어난 사람이 없는 것으로 읽혀
  /// 축하가 영영 안 뜬다.
  final _seen = <String>{};

  @override
  void initState() {
    super.initState();
    // 처음 그려질 때 있던 사람은 "이미 있던 사람"이다. 여기서 담아 두지
    // 않으면 화면에 들어오는 것만으로 전원이 합류한 것이 된다.
    _seen.addAll(_othersOf(widget.room).map((p) => p.userId));
  }

  @override
  void didUpdateWidget(HomeWaiting old) {
    super.didUpdateWidget(old);

    final others = _othersOf(widget.room);
    final ids = others.map((p) => p.userId).toSet();
    // ⚠️ **늘어난 것만 축하한다.** 머릿수를 보면 화면에 들어올 때마다 뜨고,
    // 누가 나가도 바뀌는 수라 나간 것을 축하하게 된다.
    final joined = ids.difference(_seen);
    _seen
      ..clear()
      ..addAll(ids);
    if (joined.isEmpty) return;

    // ⚠️ **마지막으로 들어온 사람으로 갈아탄다.** 앞 축하가 끝나기를
    // 기다리면 이미 지난 일을 뒤늦게 알리게 된다.
    final last = others.lastWhere((p) => joined.contains(p.userId));
    _celebrateTimer?.cancel();
    setState(() => _celebrating = last);
    _celebrateTimer = Timer(HomeWaiting._celebrateHold, () {
      if (!mounted) return;
      setState(() => _celebrating = null);
    });
  }

  @override
  void dispose() {
    _celebrateTimer?.cancel();
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// 나를 뺀 둘레 사람들.
  ///
  /// ⚠️ **나를 빼고 센다.** 서버가 나를 명단에 넣으므로, 안 빼면 신청한
  /// 순간 내가 합류한 것으로 읽혀 나에게 내 축하가 뜬다.
  List<RoomPlayer> _othersOf(RoomInfo room) => [
    for (final player in room.players)
      if (player.userId != widget.myUserId) player,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    // ⚠️ **한 번 집어 둔다.** 아래에서 `null` 검사와 사용이 나뉘는데, 필드를
    // 그대로 쓰면 승격이 안 돼 `!`를 붙이게 된다.
    final celebrating = _celebrating;
    final others = <RoomPlayer>[];
    RoomPlayer? mine;
    for (final player in widget.room.players) {
      if (player.userId == widget.myUserId) {
        mine = player;
      } else {
        others.add(player);
      }
    }

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: SizedBox(
        height: HomeWaiting._height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/home_waiting_bg.webp',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),

            // 둘레 사람들. **가운데보다 먼저 그린다** — 겹치면 내가 위다.
            //
            // ⚠️ **옮기는 것은 자리뿐이다.** `Transform.translate`는 사진을
            // 돌리지 않으므로, 각도에 회전을 더하면 얼굴은 선 채로 궤도만
            // 돈다 — 거꾸로 돌려 세울 레이어가 필요 없다.
            for (final (index, player) in others.indexed)
              AnimatedBuilder(
                animation: _spin,
                // ⚠️ **아바타는 `child`로 넘긴다.** builder 안에서 만들면
                // 프레임마다 사진 위젯이 새로 서고, 네트워크 이미지가 매번
                // 다시 붙는다.
                child: RunnerAvatarV2(
                  nickname: player.nickname,
                  imageUrl: player.profileImageUrl,
                  size: HomeWaiting._otherSize,
                ),
                builder: (context, child) => _Orbiting(
                  angle:
                      _angleOf(index, others.length) +
                      _spin.value * 2 * math.pi,
                  child: child!,
                ),
              ),

            // 가운데 — 나.
            AnimatedBuilder(
              animation: _pulse,
              child: RunnerAvatarV2(
                nickname: mine?.nickname ?? widget.myNickname ?? '',
                // ⚠️ **방 명단이 먼저다.** [HomeWaiting.myPhotoUrl]의 출처인
                // `GET /users/me`(36번)에는 **`profileImageUrl`이 없다** —
                // 응답은 `userId`·`email`·`loginType`·`nickname`·`isOnboarded`
                // 뿐이라 늘 `null`이고, 가운데 내 얼굴만 기본 이미지로 남았다.
                // 둘레 사람들은 같은 명단에서 사진을 받아 제대로 떴다.
                imageUrl: mine?.profileImageUrl ?? widget.myPhotoUrl,
                size: HomeWaiting._mySize,
              ),
              builder: (context, child) {
                // ⚠️ **크기를 건드리지 않는다.** 사진이 커졌다 작아지면
                // 출렁이는 것으로 보인다. 들고 나는 것은 테두리 빛뿐이다.
                final t = Curves.easeInOut.transform(_pulse.value);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // 시안 `158:2969`의 파란 번짐. 내가 가운데라는 표시다.
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary,
                        blurRadius: 24 + 14 * t,
                        spreadRadius: 2 * t,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
            ),

            Positioned(
              top: AppSpacing.space8,
              left: AppSpacing.space6,
              right: AppSpacing.space6,
              child: Column(
                children: [
                  Text(
                    AppStrings.homeMatchWaitingTitle,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading03.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    // ⚠️ 신청 직후에는 아직 나뿐이다. 그때 `0명의 러너가`라고
                    // 적으면 말이 안 된다 — 시안에 없는 구간이다.
                    '${others.isEmpty ? AppStrings.homeMatchWaitingAlone : AppStrings.homeMatchWaitingOthers(others.length)}'
                    '\n${AppStrings.homeMatchWaitingHint}',
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.body07.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: AppSpacing.space4,
              right: AppSpacing.space4,
              bottom: AppSpacing.space4,
              // ⚠️ **취소는 여기 두지 않는다.** 로비가 제재 여부를 문구로
              // 알려주고 거기서 결정하게 한다 — 두 곳에 두면 한쪽 문구만
              // 고쳐진다.
              child: AppButtonV2(
                label: AppStrings.homeMatchWaitingCta,
                variant: AppButtonV2Variant.tonal,
                onPressed: widget.onLobby,
              ),
            ),

            // ⚠️ **맨 위에 둔다.** 축하는 1.92초 동안 히어로의 주인공이다.
            // 궤도는 그 뒤에서 그대로 돈다 — 걷히면 새 원이 자리에 들어와
            // 맴돌고 있다.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: AppMotion.drop,
                  reverseDuration: AppMotion.base,
                  switchInCurve: AppMotion.easeBloom,
                  switchOutCurve: AppMotion.easeStandard,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: .86,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: celebrating == null
                      ? const SizedBox.shrink()
                      : _Celebration(
                          key: ValueKey(celebrating.userId),
                          player: celebrating,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 둘레 자리의 각도(라디안).
  ///
  /// 시안이 쓴 셋까지는 그대로 쓰고, 그보다 많아지면 고르게 나눈다.
  static double _angleOf(int index, int total) {
    final degrees = total <= HomeWaiting._angles.length
        ? HomeWaiting._angles[index]
        : HomeWaiting._angles.first + 360.0 * index / total;
    return degrees * math.pi / 180;
  }
}

/// 합류 축하 — 히어로 **한가운데**에 뜬다(1.92초).
///
/// ## ⚠️ 가로로 눕힌다
///
/// 사진을 위에 얹은 정사각형은 히어로를 너무 가린다. 사진 왼쪽·문구 오른쪽의
/// 가로 카드가 같은 말을 절반 높이로 한다.
class _Celebration extends StatelessWidget {
  const _Celebration({required this.player, super.key});

  final RoomPlayer player;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return DecoratedBox(
      // 동심원 위에 그냥 올리면 흰 글자가 묻힌다. 가운데만 눌러 둔다.
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [colors.bgScrim, colors.bgScrim.withValues(alpha: .35)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryMuted,
              borderRadius: AppRadius.card,
              border: Border.all(color: colors.primary),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space3,
                AppSpacing.space3,
                AppSpacing.space4,
                AppSpacing.space3,
              ),
              // ⚠️ **읽을 때는 한 문장이다.** 말줄임 때문에 닉네임과 뒷말을
              // 따로 세웠는데, 그대로 두면 스크린리더가 토막으로 읽는다.
              child: Semantics(
                label: AppStrings.homeMatchSuccess(player.nickname),
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RunnerAvatarV2(
                      nickname: player.nickname,
                      imageUrl: player.profileImageUrl,
                      size: _avatarSize,
                    ),
                    const SizedBox(width: AppSpacing.space3),
                    // ⚠️ **닉네임만 줄인다.** 문장을 통째로 줄이면 정작
                    // 알려야 할 `매칭성공!`이 먼저 잘린다. 닉네임은 16자까지
                    // 온다.
                    //
                    // ⚠️ `Expanded`가 아니라 `Flexible`이다. 짧은 이름일 때
                    // 남는 자리를 글자가 먹어 가운데 정렬이 깨진다.
                    Flexible(
                      child: Text(
                        player.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypographyV2.body05.copyWith(
                          color: colors.textStrong,
                        ),
                      ),
                    ),
                    Text(
                      AppStrings.homeMatchSuccessSuffix,
                      style: AppTypographyV2.body05.copyWith(
                        color: colors.textStrong,
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

  /// 시안의 둘레 원보다 작다. 카드 높이를 사진이 정한다.
  static const _avatarSize = 44.0;
}

/// 가운데에서 [angle] 방향으로 궤도 반지름만큼 밀어낸다.
///
/// ⚠️ **카드 밖으로 걸쳐도 둔다.** 시안도 왼쪽 사람을 카드 밖까지 내보낸다 —
/// 둘레가 화면보다 넓다는 느낌이 거기서 나온다. 바깥은 `ClipRRect`가 자른다.
class _Orbiting extends StatelessWidget {
  const _Orbiting({required this.angle, required this.child});

  final double angle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(
        HomeWaiting._orbit * math.cos(angle),
        HomeWaiting._orbit * math.sin(angle),
      ),
      child: child,
    );
  }
}
