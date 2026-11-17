import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_motion.dart';
import 'package:runiverse/core/theme/v2/app_palette.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/runner_avatar.dart';
import 'package:runiverse/features/home/presentation/home_hero_shade.dart';
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
/// **세 자리를 자리표([_angles])로 두고, 그보다 많아지면 고르게 나눈다.**
///
/// ⚠️ **크기와 불투명도는 모두 같게 뒀다.** 시안은 깊이를 내려고 달리하는데,
/// 우리 목록은 서버가 준 순서라 **앞사람이 크게 그려지면 순위처럼 읽힌다.**
/// CLAUDE.md 가 파티원에 순위를 붙이지 말라고 못 박는다 — 동행이지 경쟁이
/// 아니다. 디자인 확인이 필요하다.
///
/// ## ⚠️ 움직이는 것은 둘레의 원뿐이다
///
/// 동심원 배경·글자·버튼은 시안 그대로 가만히 있는다. 움직임을 더한 것은
/// 셋뿐이다.
///
/// - **둘레 원이 저마다 맴돈다** — 각도(6.2초)와 반지름(4.1초)이 따로 도는
///   탓에 같은 길을 되밟는 것으로 보이지 않는다.
/// - **빈 자리도 돈다** — 아직 아무도 없을 때 둘레가 텅 비면 **찾고 있는
///   것인지 멈춘 것인지** 알 수 없다. 신청 직후가 가장 오래 보는 화면이다.
/// - **파티원이 늘면 한가운데 축하가 뜬다** — 1.92초. 그동안에도 궤도는
///   멈추지 않는다.
///
/// 가운데 내 원은 움직이지 않는다. 시안의 파란 번짐(`158:2969`)을 숨 쉬듯
/// 들고 나게 했었는데, 네온처럼 보여 번짐째 뺐다 — 내가 가운데라는 표시는
/// 동심원 구멍이 한다.
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

  /// 시안 `158:2952`은 452다. 340으로 줄였다 — 상태 카드 모두 같은 높이다.
  static const _height = 340.0;

  /// 둘레 사람들의 크기와 궤도 반지름.
  ///
  /// ⚠️ **폭 [_designWidth] 카드에서 어느 순간에도 닿지 않는 값이다.**
  /// 반지름 [_driftIn]~[_driftOut]과 각도 [_sways]를 다 돌려도 둘레 원은
  /// 버튼·카드 끝·내 사진·서로와 떨어져 있다. 시안 크기(80)·반지름(165)
  /// 그대로면 원이 버튼 뒤로 들어가고 카드 밖으로 잘린다. 다른 폭에서는
  /// 궤도 가로만 [_stretchOf]만큼 늘이고 줄인다.
  static const _otherSize = 60.0;
  static const _orbit = 136.0;

  /// 궤도 값을 정한 카드 폭 — 384dp 폰.
  static const _designWidth = 352.0;

  /// 궤도를 세로로 누르는 비율. 원이 안내 줄과 버튼 사이에서만 돌게 한다.
  static const _squash = 0.7;

  /// 가운데 원과 궤도 중심을 카드 한가운데에서 내리는 거리. 제목·안내 줄과
  /// 버튼 사이 한가운데에 둔다. 배경 동심원도 같이 내린다([HomeWaitingRing]).
  static const _centerDrop = 24.0;

  /// [_centerDrop]만큼 내린 동심원 중심을 카드 안 정렬로 적은 것. 합류
  /// 축하가 이 점을 중심으로 커지고, 축하 뒤를 누르는 막도 이 점에서 번진다.
  static const _ringCenter = Alignment(0, _centerDrop / (_height / 2));

  /// 동심원 구멍의 지름(배율 1). 시안이 가운데 내 사진(`158:2969`)을 이
  /// 크기로 구멍에 꼭 맞췄다.
  static const _ringHole = 135.0;

  /// 배율 1인 카드 폭. 동심원을 잰 원래 배경 그림(384×452)의 폭이다.
  static const _ringWidth = 384.0;

  /// 카드 폭 [width]에서 동심원과 가운데 내 사진을 키우거나 줄일 배율.
  ///
  /// ## ⚠️ 폭을 따라가되 1배에서 멈춘다
  ///
  /// 동심원은 카드 폭을 따라 줄고 는다 — 360dp 폰(폭 328)에서 0.85,
  /// 384dp(352)에서 0.92, 412dp(380)에서 0.99다. 사진도 같은 배율로 그려야
  /// 폰마다 구멍에 맞는다.
  ///
  /// 1배(폭 384, 416dp 폰)에서 멈춘다. 높이 340에 글자·버튼 자리가 고정이라
  /// 사진이 계속 커지면 버튼(위끝 268)에 붙는다 — 135면 6.5 떨어지고 148이면
  /// 닿는다. 그보다 넓은 화면에서는 같은 크기의 동심원이 가운데 놓이고
  /// 바깥은 바탕색이 이어진다.
  static double _ringScale(double width) => math.min(width / _ringWidth, 1);

  /// 카드 폭 [width]에서 궤도 가로를 늘이고 줄일 비율. [_designWidth]에서
  /// 1이고, 동심원과 같은 배율로 따라가 둘레 원이 링 위 같은 자리에 앉는다.
  /// 세로는 높이가 고정이라 그대로 둔다.
  static double _stretchOf(double width) =>
      _ringScale(width) / _ringScale(_designWidth);

  /// 아직 아무도 안 들어온 자리의 크기.
  ///
  /// 사람 원보다 작다 — **비어 있다는 말을 크기로 한다.** 같은 크기로 두면
  /// 테두리만 보고 사람인지 빈자리인지 가려야 한다. 작게 두면 글자·버튼과
  /// 부딪칠 일도 그만큼 준다.
  static const _emptySize = 56.0;

  /// 세 자리의 각도(도). 넷째부터는 고르게 나눈다.
  ///
  /// 시안 각도(-22.9° · 121.8° · 202.8°)는 340에서 121.8° 자리가 버튼 뒤로
  /// 들어간다. 오른쪽 하나는 가로 중앙선 위, 왼쪽 둘은 그 선을 기준으로
  /// 거울처럼 마주 보게 옮겼다.
  static const _angles = [0.0, 160.0, 200.0];

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
  /// ⚠️ **흰 원이 제목·안내 줄 위를 지나가면 안 된다.** 글자도 흰색이라
  /// 지나가는 동안 읽을 수 없다. 세 자리를 좌우 바깥([_angles])에 둔 것도
  /// 가운데 위 글자를 피하려는 배치다.
  ///
  /// 오른쪽 자리는 가로 중앙선을 사이에 두고 ±8°, 왼쪽 두 자리는 서로
  /// 40°밖에 안 떨어져 ±4°로 좁힌다. 왼쪽 둘은 같은 위상으로 함께
  /// 움직여(`_wanderOf`) 사이가 늘 같다.
  static const _sways = [(-8.0, 8.0), (-4.0, 4.0), (-4.0, 4.0)];

  /// 자리가 넷 이상일 때(고르게 나눌 때) 모든 자리에 쓸 폭.
  static const _swayFallback = (-8.0, 8.0);

  /// 반지름이 드나드는 폭(px).
  ///
  /// 340에서는 안팎 모두 좁다 — 안쪽으로 더 들이면 왼쪽 두 원끼리, 바깥으로
  /// 더 밀면 카드 끝과 닿는다.
  static const _driftIn = -3.0;
  static const _driftOut = 3.0;

  /// 자리마다 어긋나게 둘 위상(바퀴 수). 황금비라 몇 자리를 늘어놓아도
  /// 겹치지 않는다.
  static const _spinPhase = 0.618;
  static const _driftPhase = 0.382;

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
    super.dispose();
  }

  /// 자리 [index]가 지금 있는 곳 — 가운데에서 밀어낼 거리.
  ///
  /// 각도와 반지름이 주기가 다른 사인 둘이라, 원은 호를 따라 왕복하면서 동시에
  /// 들락거린다 — 눈에는 정해진 길 없이 떠도는 것으로 보인다.
  ///
  /// 가로는 [stretch]([HomeWaiting._stretchOf])만큼 늘이고 줄인다.
  Offset _wanderOf(int index, int total, double stretch) {
    final (lo, hi) = _swayOf(index, total);
    // 왼쪽 두 자리(1·2)는 같은 위상으로 함께 움직인다 — 사이가 늘 같아
    // 서로 부딪치지 않는다. 넷 이상으로 고르게 나눌 때는 자리마다 다르다.
    final phase = total <= HomeWaiting._angles.length && index == 2 ? 1 : index;
    final angle =
        _angleOf(index, total) +
        _sinBetween(_spin, phase * HomeWaiting._spinPhase, lo, hi) *
            math.pi /
            180;
    final radius =
        HomeWaiting._orbit +
        _sinBetween(
          _drift,
          phase * HomeWaiting._driftPhase,
          HomeWaiting._driftIn,
          HomeWaiting._driftOut,
        );
    return Offset(
      radius * math.cos(angle) * stretch,
      radius * math.sin(angle) * HomeWaiting._squash + HomeWaiting._centerDrop,
    );
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

  /// 제목 아래 줄. **초대 방은 "신청"이라고 하지 않는다** — 신청한 적이 없다.
  String get _waitingHint => widget.room.type == RoomType.invite
      ? AppStrings.homeInviteWaitingHint
      : AppStrings.homeMatchWaitingHint;

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
    // 둘레에 깔 자리 수. 사람이 덜 찼으면 **빈 자리로 채운다** — 셋이
    // 기본이고, 그보다 많이 오면 사람 수만큼만 둔다.
    //
    // 빈 원 셋은 가운데 나까지 **정원 4명을 보여 준다.** 응답에 정원 필드가
    // 없어 서버가 2~4명으로 편성하는 방의 최대를 그린다 — 둘짜리 방으로
    // 확정되면 확정 카드가 실제 인원을 보여 준다.
    final slots = math.max(others.length, HomeWaiting._angles.length);

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: SizedBox(
        height: HomeWaiting._height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(child: HomeWaitingRing()),

            // 둘레 사람들. **가운데보다 먼저 그린다** — 겹치면 내가 위다.
            //
            // ⚠️ **옮기는 것은 자리뿐이다.** `Transform.translate`는 사진을
            // 돌리지 않으므로, 각도에 회전을 더하면 얼굴은 선 채로 궤도만
            // 돈다 — 거꾸로 돌려 세울 레이어가 필요 없다.
            //
            // ⚠️ **카드 폭은 카드를 채운 칸(`Positioned.fill`)에서 읽는다.**
            // 움직임은 `LayoutBuilder` 안에서 다시 만들어져 그 `LayoutBuilder`를
            // 프레임마다 다시 배치한다. 크기가 정해진 칸이면 거기서 멈추고,
            // 그냥 두면 카드 `Stack` 배치까지 번진다. 폭은 프레임마다 읽지
            // 않고, 카드가 다시 만들어지거나 폭이 바뀔 때만 다시 읽는다.
            for (final (index, player) in others.indexed)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stretch = HomeWaiting._stretchOf(
                      constraints.maxWidth,
                    );
                    return Center(
                      child: AnimatedBuilder(
                        animation: _wander,
                        // ⚠️ **아바타는 `child`로 넘긴다.** builder 안에서
                        // 만들면 프레임마다 사진 위젯이 새로 서고, 네트워크
                        // 이미지가 매번 다시 붙는다.
                        child: RunnerAvatarV2(
                          nickname: player.nickname,
                          imageUrl: player.profileImageUrl,
                          size: HomeWaiting._otherSize,
                        ),
                        builder: (context, child) => _Orbiting(
                          offset: _wanderOf(index, slots, stretch),
                          child: child!,
                        ),
                      ),
                    );
                  },
                ),
              ),

            // 아직 안 찬 자리. **사람 뒤에 그린다** — 자리가 겹칠 일은 없지만
            // 순서를 사람 먼저로 둬야 들어오는 쪽이 위가 된다.
            //
            // ⚠️ **이 원은 `child`로 넘기지 못한다.** 테두리 짙기가 프레임마다
            // 바뀐다. 사진도 네트워크 이미지도 없는 테두리 하나라 매 프레임
            // 세워도 값이 싸다.
            for (var index = others.length; index < slots; index++)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stretch = HomeWaiting._stretchOf(
                      constraints.maxWidth,
                    );
                    return Center(
                      child: AnimatedBuilder(
                        animation: _wander,
                        builder: (context, _) => _Orbiting(
                          offset: _wanderOf(index, slots, stretch),
                          child: _SearchingSlot(
                            key: ValueKey('home-waiting-empty-$index'),
                            alpha: _breathOf(index),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // 가운데 — 나. 동심원과 같은 배율로 그려 구멍에 꼭 맞춘다.
            LayoutBuilder(
              builder: (context, constraints) => Transform.translate(
                offset: const Offset(0, HomeWaiting._centerDrop),
                child: RunnerAvatarV2(
                  nickname: mine?.nickname ?? widget.myNickname ?? '',
                  // ⚠️ **방 명단이 먼저다.** [HomeWaiting.myPhotoUrl]의 출처인
                  // `GET /users/me`(36번)에는 **`profileImageUrl`이 없다** —
                  // 응답은 `userId`·`email`·`loginType`·`nickname`·
                  // `isOnboarded`뿐이라 늘 `null`이고, 가운데 내 얼굴만 기본
                  // 이미지로 남았다. 둘레 사람들은 같은 명단에서 사진을 받아
                  // 제대로 떴다.
                  imageUrl: mine?.profileImageUrl ?? widget.myPhotoUrl,
                  size:
                      HomeWaiting._ringHole *
                      HomeWaiting._ringScale(constraints.maxWidth),
                ),
              ),
            ),

            Positioned(
              // 다른 상태 카드와 같이 제목을 위 24에 둔다.
              top: AppSpacing.space6,
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
                    // 기다려도 된다는 안내 한 줄만 둔다. 몇 명이 왔는지는
                    // 둘레 사진과 합류 축하가 보여 준다.
                    _waitingHint,
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
                // 누르면 로비로 간다. 지금 무엇을 기다리는지는 위 제목이
                // 말하므로 버튼이 같은 말을 되풀이하지 않는다.
                label: AppStrings.homeMatchToLobby,
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
                      // 축하는 내린 동심원 중심에 뜬다. 그 점을 기준으로 키워야
                      // 커지는 동안 중심이 동심원에서 비켜나지 않는다.
                      alignment: HomeWaiting._ringCenter,
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
  /// 세 자리는 자리마다 정해 두고([HomeWaiting._sways]), 그보다 많아지면
  /// 어느 자리가 글자를 지나는지 알 수 없어 모든 자리에
  /// [HomeWaiting._swayFallback]을 쓴다.
  static (double, double) _swayOf(int index, int total) =>
      total <= HomeWaiting._angles.length
      ? HomeWaiting._sways[index]
      : HomeWaiting._swayFallback;

  /// 둘레 자리의 각도(라디안).
  ///
  /// 세 자리까지는 자리표([HomeWaiting._angles])를 쓰고, 그보다 많아지면
  /// 고르게 나눈다.
  static double _angleOf(int index, int total) {
    final degrees = total <= HomeWaiting._angles.length
        ? HomeWaiting._angles[index]
        : HomeWaiting._angles.first + 360.0 * index / total;
    return degrees * math.pi / 180;
  }
}

/// 모집 중 배경과 그 위 덮개 — 동심원 구멍이 카드 한가운데에서
/// [HomeWaiting._centerDrop] 아래에 오게 깐다. 같은 배경을 쓰는 상태 대기
/// 카드도 이것을 깐다 — 두 카드가 번갈아 떠도 동심원이 제자리에 있다.
///
/// 덮개의 빛 중심도 같은 자리에서 구한다 — 숫자를 따로 적어 두면 한쪽만
/// 바뀐다.
class HomeWaitingRing extends StatelessWidget {
  const HomeWaitingRing({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final center = height / 2 + HomeWaiting._centerDrop;

        return Stack(
          children: [
            Positioned.fill(
              // ⚠️ **따로 묶는다.** 둘레 원이 프레임마다 움직여도 동심원은
              // 처음 한 번만 그리고 그 뒤로는 그려 둔 것을 다시 쓴다.
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RingPainter(
                    scale: HomeWaiting._ringScale(constraints.maxWidth),
                    centerY: center,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: HomeHeroShade(
                light: HomeHeroLight.center,
                ringCenter: Alignment(0, center / (height / 2) - 1),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 동심원 링 셋 — 시안 `158:2951`의 배경.
///
/// ## ⚠️ 그림이 아니라 그린다
///
/// 처음엔 시안을 384×452 그림(`home_waiting_bg.webp`, 지금은 지움)으로 구워
/// 깔았다. 그림은 카드를 덮어야 해서 좁은 카드에서는 0.86배 아래로 줄일 수
/// 없었고, 카드가 384보다 넓으면 1배를 넘겨 키워 구멍이 가운데 사진보다
/// 커졌다. 무늬가 동심원과 번짐뿐이라 그 그림에서 반지름별 색을 재 같은
/// 모양으로 그린다 — 어느 폭에서도 끝이 없고, 1배 그림을 키울 때 보이던
/// 계단도 없다.
///
/// 링마다 안쪽 끝이 가장 짙고([AppPaletteV2.ringGlow]) 바깥으로 [_falloff]
/// 곡선을 따라 바탕([AppPaletteV2.neutral900])으로 번진다. 둘 다 그림에서 잰
/// 테마와 무관한 값이다 — 그림도 테마를 따르지 않았다.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.scale, required this.centerY});

  /// [HomeWaiting._ringScale]. 아래 길이는 모두 배율 1 기준이다.
  final double scale;

  /// 동심원 중심의 높이. 가로는 늘 가운데다.
  final double centerY;

  /// 링 셋 — 안쪽 끝 반지름, 바깥으로 번지는 폭, 안쪽 끝의 짙기.
  ///
  /// 첫 링의 안쪽 끝이 구멍이다([HomeWaiting._ringHole]의 반). 셋째 링의
  /// 번짐은 그림 끝(반지름 약 290)에서 잘려 있어, 남은 구간의 짙기로 폭을
  /// 어림했다 — 어림한 바깥은 320dp처럼 좁은 폰의 카드 위 모서리와, 태블릿처럼
  /// 넓은 화면의 카드 가장자리에서만 보인다.
  static const _rings = [
    (edge: HomeWaiting._ringHole / 2, fade: 38.0, peak: .92),
    (edge: 158.5, fade: 66.0, peak: 1.0),
    (edge: 244.5, fade: 116.0, peak: 1.0),
  ];

  /// 번짐 곡선 — 안쪽 끝(0)에서 바깥 끝(1)까지 짙기가 줄어드는 모양.
  /// 첫째·둘째 링에서 잰 값의 평균이다.
  static const _falloff = [
    (at: 0.0, alpha: 1.0),
    (at: .15, alpha: .83),
    (at: .3, alpha: .61),
    (at: .45, alpha: .42),
    (at: .6, alpha: .23),
    (at: .75, alpha: .105),
    (at: .9, alpha: .03),
    (at: 1.0, alpha: 0.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = AppPaletteV2.neutral900);

    final outer = _rings.last.edge + _rings.last.fade;
    final colors = <Color>[];
    final stops = <double>[];
    void stop(double radius, double alpha) {
      stops.add(radius / outer);
      colors.add(AppPaletteV2.ringGlow.withValues(alpha: alpha));
    }

    stop(0, 0);
    for (final ring in _rings) {
      // 링 안쪽은 비어 있다. 1px 안에서 바탕에서 가장 짙은 색으로 선다.
      stop(ring.edge - 1, 0);
      for (final point in _falloff) {
        stop(ring.edge + ring.fade * point.at, ring.peak * point.alpha);
      }
    }

    canvas.drawRect(
      area,
      Paint()
        ..shader = RadialGradient(colors: colors, stops: stops).createShader(
          Rect.fromCircle(
            center: Offset(size.width / 2, centerY),
            radius: outer * scale,
          ),
        ),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.scale != scale || old.centerY != centerY;
}

/// 합류 축하 — 동심원 **한가운데**, 가운데 내 사진 위에 뜬다(1.92초).
///
/// 내 사진과 동심원을 카드 한가운데에서 [HomeWaiting._centerDrop]만큼
/// 내렸으니 축하와 그 뒤를 누르는 막도 같은 자리로 내린다.
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
          center: HomeWaiting._ringCenter,
          colors: [colors.bgScrim, colors.bgScrim.withValues(alpha: .35)],
        ),
      ),
      // ⚠️ `Align`으로 내리면 카드 자기 높이만큼 기준점이 어긋난다(높이 68
      // 카드면 중심이 194가 아니라 189). 위를 내림의 두 배 비우고 그 안
      // 가운데에 두면 카드 높이와 상관없이 중심이 동심원 중심에 온다.
      child: Padding(
        padding: const EdgeInsets.only(top: 2 * HomeWaiting._centerDrop),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primaryMuted,
                borderRadius: AppRadius.card,
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
                //
                // 누가 들어왔는지 알리는 것이 이 카드뿐이라(인원 줄은 없다)
                // 뜨는 순간 스크린리더가 읽게 한다(`liveRegion`). `container`가
                // 없으면 이 문장이 카드 전체 노드에 붙어, 들어올 때마다 카드를
                // 통째로 다시 읽는다.
                child: Semantics(
                  label: AppStrings.homePlayerJoined(player.nickname),
                  container: true,
                  liveRegion: true,
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ⚠️ **테두리가 없으면 원이 묻힌다.** 아바타의 바탕이
                      // `primaryMuted`인데(`runner_avatar.dart`) 이 카드도 같은
                      // 색이라, 사진이 없는 사람은 동그라미가 아예 안 보인다.
                      //
                      // 테두리 굵기만큼 사진을 안쪽으로 들인다(`Container`가
                      // 테두리 폭을 여백으로 둔다). 프로필 사진과 같은 방식이다.
                      // 바깥 지름은 그대로 44다. 원을 바탕에서 떼어 보이게만
                      // 하면 되니 빈 자리 원과 같은 밝기대의 흐린 흰 1이다 —
                      // 더 밝으면 문장보다 선이 먼저 보인다.
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.textStrong.withValues(alpha: .3),
                            width: 1,
                          ),
                        ),
                        child: RunnerAvatarV2(
                          nickname: player.nickname,
                          imageUrl: player.profileImageUrl,
                          size: _avatarSize - 2,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.space3),
                      // ⚠️ **닉네임만 줄인다.** 문장을 통째로 줄이면 정작
                      // 알려야 할 `합류했어요`가 먼저 잘린다. 닉네임은 16자까지
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
                        AppStrings.homePlayerJoinedSuffix,
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
      ),
    );
  }

  /// 시안의 둘레 원보다 작다. 카드 높이를 사진이 정한다.
  static const _avatarSize = 44.0;
}

/// 가운데에서 [offset]만큼 밀어낸다.
///
/// 궤도 가로를 카드 폭에 맞춰 늘이고 줄여(`_wanderOf`), 320~440dp 폰에서
/// 둘레 원은 카드 안에 머문다. 그래도 넘치면 바깥은 `ClipRRect`가 자른다.
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
