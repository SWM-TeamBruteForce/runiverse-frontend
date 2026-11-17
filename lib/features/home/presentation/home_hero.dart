import 'package:flutter/material.dart';
import 'package:runiverse/features/home/presentation/home_confirmed.dart';
import 'package:runiverse/features/home/presentation/home_waiting.dart';
import 'package:runiverse/features/home/presentation/home_idle.dart';
import 'package:runiverse/features/home/presentation/home_solo_room.dart';
import 'package:runiverse/features/home/presentation/home_started.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';

/// 홈 히어로 (S05).
///
/// ## 히어로가 매칭 상태를 전담한다
///
/// 정본이 정한 구조다. 등록하면 홈으로 돌아오고, 모집 중의 상태는 여기서
/// 보여 준다. 방으로 가는 문도 여기 있다 — 모집 중에는 `로비로 가기`, 확정
/// 뒤에는 `로비 이동`.
///
/// 상태는 [room]이 정한다 — `null`이면 기본, 모집 중이면 대기, 확정이면 확정.
///
/// ## ⚠️ 상태마다 배경이 다르다
///
/// 시안이 상태별로 다른 배경을 준다 — 기본은 아래에서 올라오는 파란 빛
/// (`158:2848`), 모집 중은 동심원, 확정은 위에서 내려오는 빛, 혼자 남은 방은
/// 회색 빛이다. 그 위에 빛 방향에 맞춘 덮개(`HomeHeroShade`)를 함께 깐다.
/// **배경은 상태 카드가 들고 온다** — 높이(340)와 제목 자리(위 24)만 모든
/// 카드가 같다.
///
/// 기본 상태의 빛은 **이미지다**(`assets/images/home_hero_light.webp`).
/// 시안이 blur 레이어 일곱 겹을 `plus-lighter`로 겹쳐 만든 것이라 손으로
/// 그리면 맞출 수 없다. 부드러운 그러데이션이라 WebP 로 5KB 에 들어간다.
///
/// 글자는 빛의 **위쪽**에 둔다. `docs/implementation-notes.md` §3-4가
/// **글로우를 텍스트 뒤에 깔지 말라**고 못 박았는데, 시안의 빛은 아래가 밝고
/// 위가 어두워서 제목이 앉는 자리는 여전히 어둡다.
///
/// ## 정본에서 뺀 것
///
/// - **날씨 오버레이** — 받을 API가 없다
/// - **`FAILED` 상태** — 명세에 그 상태가 없다. "마감은 인원과 무관하게 항상
///   확정으로 끝난다"고 정해져 있어 정본의 이 갈래는 낡았다
class HomeHero extends StatelessWidget {
  const HomeHero({
    required this.onMatch,
    required this.onCancel,
    required this.onLobby,
    required this.now,
    this.name,
    this.photoUrl,
    this.myUserId,
    this.room,
    this.pending = false,
    this.cooldownUntil,
    super.key,
  });

  /// 내 닉네임. **없을 수 있다** — `/me`가 오기 전이거나 온보딩 전이다.
  ///
  /// 대기 중 카드가 방 명단에 내가 없을 때 가운데 원에 쓴다. 기본 카드는
  /// 이름을 부르지 않는다.
  final String? name;

  /// 내 프로필 사진. 대기 중 카드가 가운데에 쓴다.
  final String? photoUrl;

  /// 내 아이디. 대기 중 카드가 **둘레에서 나를 빼는 데** 쓴다.
  final String? myUserId;

  /// 매칭 등록 화면으로. 기본 상태에서만 쓴다.
  final VoidCallback onMatch;

  /// 방 정보를 못 받았을 때만 쓴다. 평소의 취소는 로비가 맡는다.
  final VoidCallback onCancel;

  /// 방으로 들어간다. 모집 중이면 로비, 확정 뒤면 대기실 — 같은 화면이다.
  final VoidCallback onLobby;

  /// 지금. **부르는 쪽이 1초마다 갈아끼운다** — 카운트다운이 이 값에서 나온다.
  final DateTime now;

  /// 속한 방. `null`이면 매칭 중이 아니거나 아직 방 정보를 못 받았다.
  final RoomInfo? room;

  /// 매칭 신청이 풀리는 시각. 없거나 지났으면 제한이 없다.
  ///
  /// 이탈·조기 종료 제재다. **매칭 신청만 막고 솔로는 열어 둔다.**
  final DateTime? cooldownUntil;

  /// ⚠️ 서버는 매칭 중이라는데 [room]이 아직 없는 구간인가.
  ///
  /// 인원·마감 시각은 스트림이 나르므로 상태 조회만으로는 그릴 것이 없다.
  /// 그 사이에 기본 히어로를 보여주면 신청한 적 없는 줄 알고 다시 누른다.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final current = room;

    // 상태마다 자기 카드를 통째로 그린다.
    if (current == null && !pending) {
      return HomeIdle(onMatch: onMatch, now: now, cooldownUntil: cooldownUntil);
    }
    if (current != null && current.status == RoomStatus.matched) {
      // ⚠️ **혼자 달리게 된 방을 먼저 가른다.** 상대를 못 만나면 서버가 그
      // 방을 1인 러닝으로 돌리는데, 확정 카드를 그리면 참여자 줄에 나 혼자
      // 서 있고 왜 그런지는 아무 데도 안 적힌다.
      return HomeSoloRoom.shows(current, myUserId: myUserId)
          ? HomeSoloRoom(room: current, now: now, onLobby: onLobby)
          : HomeConfirmed(room: current, now: now, onLobby: onLobby);
    }
    if (current != null && current.status == RoomStatus.matching) {
      return HomeWaiting(
        room: current,
        onLobby: onLobby,
        myUserId: myUserId,
        myNickname: name,
        myPhotoUrl: photoUrl,
      );
    }

    return switch (current?.status) {
      // ⚠️ **여기를 비워두면 달리는 중에 홈이 "지금 매칭하기"가 된다.**
      // 예약한 시각이 지나 서버가 러닝을 시작했는데 사용자가 홈 탭에
      // 있으면 아무도 데려가지 않았다 — 그사이가 통째로 거리에서 빠진다.
      RoomStatus.started => HomeStarted(onEnter: onLobby),
      // 기본 상태는 위에서 이미 돌아갔다. 여기 오는 `_` 는 모집 중인데
      // 방 정보가 아직 없는 구간이거나 **모르는 상태값**이고, 그때도
      // 비워 두지 않는다.
      _ => HomePending(onCancel: onCancel),
    };
  }
}
