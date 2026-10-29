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
import 'package:runiverse/features/session/domain/user_status.dart';

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
/// ## ⚠️ 움직이는 것은 둘레의 원뿐이다
///
/// 동심원 배경·글자·버튼은 시안 그대로 가만히 있는다. 움직임을 더한 것은
/// 넷뿐이다.
///
/// - **둘레 원이 저마다 맴돈다** — 자리마다 위상·폭이 달라 한 몸처럼 기울지
///   않는다. 각도(6.2초)와 반지름(4.1초)이 따로 도는 탓에 같은 길을 되밟는
///   것으로 보이지 않는다.
/// - **빈 자리도 돈다** — 아직 아무도 없을 때 둘레가 텅 비면 **찾고 있는
///   것인지 멈춘 것인지** 알 수 없다. 신청 직후가 가장 오래 보는 화면이다.
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

  /// 아직 아무도 안 들어온 자리의 크기.
  ///
  /// 사람 원보다 작다 — **비어 있다는 말을 크기로 한다.** 같은 크기로 두면
  /// 테두리만 보고 사람인지 빈자리인지 가려야 한다. 작게 두면 글자·버튼과
  /// 부딪칠 일도 그만큼 준다.
  static const _emptySize = 56.0;

  /// 시안이 쓴 세 각도(도). 넷째부터는 고르게 나눈다.
  static const _angles = [-22.9, 121.8, 202.8];

  /// 각도가 한 번 왕복하는 데 걸리는 시간.
  ///
  /// ⚠️ **모션 토큰에 없는 값이다.** `AppMotion`의 가장 긴 것이 1.2초라
  /// 여기 쓸 눈금이 없다.
  ///
  /// ⚠️ **18초는 너무 느렸다.** 1초에 6px이라 보고 있어도 움직이는지
  /// 아리송했다(기기에서 확인). 기다리는 화면이라 서두를 자리는 아니지만,
  /// 멈춘 것처럼 보이면 움직임을 넣은 뜻이 없다.
  static const _orbitPeriod = Duration(milliseconds: 6200);

  /// 반지름이 드나드는 주기.
  ///
  /// ⚠️ **[_orbitPeriod]의 배수가 아니다.** 배수로 두면 둘이 맞물려 같은
  /// 길을 되밟고, 그러면 원이 정해진 궤도를 도는 것으로 보인다.
  static const _driftPeriod = Duration(milliseconds: 4100);

  /// 자리마다 흔들 폭(도). 사인을 이 범위로 편다.
  ///
  /// ## ⚠️ 폭이 자리마다 다르고, 가운데가 시안 자리가 아니다
  ///
  /// 돌려 보니 **흰 원이 제목·부제 위를 지나갔다.** 글자도 흰색이라 지나가는
  /// 동안 읽을 수 없다. 시안이 세 사람을 좌우 바깥([_angles])에 둔 것은
  /// 가운데 위 글자를 피하려는 배치다.
  ///
  /// 처음엔 시안 자리를 가운데 두고 ±6°로 좁혔는데, 좁히니 움직임이 안 보이고
  /// 넓히면 글자를 가렸다. **폭이 문제가 아니라 방향이 문제였다** — 위로 가는
  /// 쪽만 글자와 부딪친다.
  ///
  /// 그래서 **시안 자리를 흔들림의 한쪽 끝으로 삼고, 반대쪽으로만 편다.**
  /// 1번 자리(오른쪽 위)는 시계방향이 아래로 내려가는 쪽, 3번(왼쪽 위)은
  /// 반대다. 2번(왼쪽 아래)만 아래가 CTA라 위로 편다.
  static const _sways = [(0.0, 16.0), (0.0, 18.0), (-16.0, 0.0)];

  /// 자리가 넷 이상일 때(고르게 나눌 때) 쓸 폭. 어느 자리가 글자를 지나는지
  /// 알 수 없으니 좁게 둔다.
  static const _swayFallback = (-8.0, 8.0);

  /// 반지름이 드나드는 폭(px).
  ///
  /// ⚠️ **안쪽이 넓다.** 바깥으로 밀면 위쪽 두 자리가 카드 모서리와 글자 끝
  /// 쪽으로 간다. 안쪽은 가운데 내 원(지름 135)까지 아직 여유가 있다.
  static const _driftIn = -16.0;
  static const _driftOut = 5.0;

  /// 자리마다 어긋나게 둘 위상(바퀴 수). 황금비라 몇 자리를 늘어놓아도
  /// 겹치지 않는다.
  static const _spinPhase = 0.618;
  static const _driftPhase = 0.382;

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

  /// 반지름을 드나들게 하는 쪽. [_spin]과 따로 돌아야 궤도가 닫히지 않는다.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: HomeWaiting._driftPeriod,
  )..repeat();

  /// 둘레 원이 지켜볼 것 — 각도와 반지름 둘 다다.
  late final Listenable _wander = Listenable.merge([_spin, _drift]);

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
    _drift.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// 자리 [index]가 지금 있는 곳 — 가운데에서 밀어낼 거리.
  ///
  /// 각도와 반지름이 주기가 다른 사인 둘이라, 원은 호를 따라 왕복하면서 동시에
  /// 들락거린다 — 눈에는 정해진 길 없이 떠도는 것으로 보인다.
  Offset _wanderOf(int index, int total) {
    final (lo, hi) = _swayOf(index, total);
    final angle =
        _angleOf(index, total) +
        _sinBetween(_spin, index * HomeWaiting._spinPhase, lo, hi) *
            math.pi /
            180;
    final radius =
        HomeWaiting._orbit +
        _sinBetween(
          _drift,
          index * HomeWaiting._driftPhase,
          HomeWaiting._driftIn,
          HomeWaiting._driftOut,
        );
    return Offset(radius * math.cos(angle), radius * math.sin(angle));
  }

  /// 아직 안 찬 자리의 테두리가 지금 얼마나 짙은가.
  ///
  /// 들고 나는 것이 "찾는 중"이라는 말이다. 반지름과 다른 위상을 줘서 크기와
  /// 짙기가 같이 커졌다 작아지지 않는다.
  double _breathOf(int index) =>
      _sinBetween(_drift, index * HomeWaiting._driftPhase + .25, .16, .34);

  /// [c]의 사인을 [lo]~[hi] 범위로 편다. [phase]만큼 어긋나게 돈다.
  ///
  /// 사인이라 끝에서 느려졌다 돌아온다 — 등속으로 왕복하면 양 끝에서 멈칫하는
  /// 것이 눈에 띈다.
  static double _sinBetween(
    AnimationController c,
    double phase,
    double lo,
    double hi,
  ) {
    final s = math.sin((c.value + phase) * 2 * math.pi);
    return lo + (hi - lo) * (s + 1) / 2;
  }

  /// 나를 뺀 둘레 사람들.
  ///
  /// ⚠️ **나를 빼고 센다.** 서버가 나를 명단에 넣으므로, 안 빼면 신청한
  /// 순간 내가 합류한 것으로 읽혀 나에게 내 축하가 뜬다.
  List<RoomPlayer> _othersOf(RoomInfo room) => [
    for (final player in room.players)
      if (player.userId != widget.myUserId) player,
  ];

  /// 둘째 줄. **초대 방은 "찾고 있다"고 하지 않는다** — 상대를 이미 골랐고
  /// 답을 기다리는 중이다.
  String _waitingBody(int others) {
    if (widget.room.type == RoomType.invite) {
      return others == 0
          ? AppStrings.homeInviteWaitingAlone
          : AppStrings.homeInviteJoined(others + 1);
    }
    return others == 0
        ? AppStrings.homeMatchWaitingAlone
        : AppStrings.homeMatchWaitingOthers(others);
  }

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
    // 둘레에 깔 자리 수. 사람이 덜 찼으면 **빈 자리로 채운다** — 시안이 놓은
    // 셋이 기본이고, 그보다 많이 오면 사람 수만큼만 둔다.
    //
    // ⚠️ **방 정원을 모른다.** 서버가 2~4명으로 편성한다는 것만 알고 응답에
    // 정원 필드가 없다. 그래서 빈 원 셋은 "자리가 셋 남았다"는 약속이 아니라
    // 찾고 있다는 그림이다 — 둘짜리 방으로 확정돼도 틀린 말이 되지 않게.
    // 디자인 확인이 필요하다.
    final slots = math.max(others.length, HomeWaiting._angles.length);

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
                animation: _wander,
                // ⚠️ **아바타는 `child`로 넘긴다.** builder 안에서 만들면
                // 프레임마다 사진 위젯이 새로 서고, 네트워크 이미지가 매번
                // 다시 붙는다.
                child: RunnerAvatarV2(
                  nickname: player.nickname,
                  imageUrl: player.profileImageUrl,
                  size: HomeWaiting._otherSize,
                ),
                builder: (context, child) =>
                    _Orbiting(offset: _wanderOf(index, slots), child: child!),
              ),

            // 아직 안 찬 자리. **사람 뒤에 그린다** — 자리가 겹칠 일은 없지만
            // 순서를 사람 먼저로 둬야 들어오는 쪽이 위가 된다.
            //
            // ⚠️ **이 원은 `child`로 넘기지 못한다.** 테두리 짙기가 프레임마다
            // 바뀐다. 사진도 네트워크 이미지도 없는 테두리 하나라 매 프레임
            // 세워도 값이 싸다.
            for (var index = others.length; index < slots; index++)
              AnimatedBuilder(
                animation: _wander,
                builder: (context, _) => _Orbiting(
                  offset: _wanderOf(index, slots),
                  child: _SearchingSlot(
                    key: ValueKey('home-waiting-empty-$index'),
                    alpha: _breathOf(index),
                  ),
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
                    // ⚠️ **초대 방은 매칭하고 있지 않다.** 초대한 사람의 답을
                    // 기다리는 중이다 — 같은 레이아웃에 문구만 다르다.
                    widget.room.type == RoomType.invite
                        ? AppStrings.homeInviteWaitingTitle
                        : AppStrings.homeMatchWaitingTitle,
                    textAlign: TextAlign.center,
                    style: AppTypographyV2.heading03.copyWith(
                      color: colors.textStrong,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    // ⚠️ 신청 직후에는 아직 나뿐이다. 그때 `0명의 러너가`라고
                    // 적으면 말이 안 된다 — 시안에 없는 구간이다.
                    '${_waitingBody(others.length)}'
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
                // ⚠️ **초대 방은 매칭하고 있지 않다.** 상대의 답과 출발을
                // 기다린다.
                label: widget.room.type == RoomType.invite
                    ? AppStrings.homeInviteWaitingCta
                    : AppStrings.homeMatchWaitingCta,
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

  /// 자리 [index]가 흔들릴 폭(도).
  ///
  /// 시안이 쓴 셋은 자리마다 다르고([HomeWaiting._sways]), 그보다 많아지면
  /// 어느 자리가 글자를 지나는지 알 수 없어 좁게 둔다.
  static (double, double) _swayOf(int index, int total) =>
      total <= HomeWaiting._angles.length
      ? HomeWaiting._sways[index]
      : HomeWaiting._swayFallback;

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
                    // ⚠️ **테두리가 없으면 원이 묻힌다.** 아바타의 바탕이
                    // `primaryMuted`인데(`runner_avatar.dart`) 이 카드도 같은
                    // 색이라, 사진이 없는 사람은 동그라미가 아예 안 보인다.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.textStrong, width: 2),
                      ),
                      child: RunnerAvatarV2(
                        nickname: player.nickname,
                        imageUrl: player.profileImageUrl,
                        size: _avatarSize,
                      ),
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

/// 가운데에서 [offset]만큼 밀어낸다.
///
/// ⚠️ **카드 밖으로 걸쳐도 둔다.** 시안도 왼쪽 사람을 카드 밖까지 내보낸다 —
/// 둘레가 화면보다 넓다는 느낌이 거기서 나온다. 바깥은 `ClipRRect`가 자른다.
class _Orbiting extends StatelessWidget {
  const _Orbiting({required this.offset, required this.child});

  final Offset offset;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Transform.translate(offset: offset, child: child);
}

/// 아직 아무도 안 들어온 자리 — 테두리만 있는 원.
///
/// ## ⚠️ 속을 비워 둔다
///
/// 채워 그리면 사진이 안 뜬 사람으로 읽힌다. 테두리뿐인 원은 **자리는 있는데
/// 아직 비었다**는 말을 글자 없이 한다. [alpha]가 들고 나는 것이 "찾는
/// 중"이라는 말이다.
class _SearchingSlot extends StatelessWidget {
  const _SearchingSlot({required this.alpha, super.key});

  /// 테두리 짙기. 프레임마다 바뀐다.
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      width: HomeWaiting._emptySize,
      height: HomeWaiting._emptySize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.textStrong.withValues(alpha: alpha),
          width: 2,
        ),
      ),
    );
  }
}
