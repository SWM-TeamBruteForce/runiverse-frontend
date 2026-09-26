import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';

/// 디자인 아이콘 33개의 이름.
///
/// **문자열을 직접 쓰지 않는다.** 없는 이름을 넘기면 화면에 빈 자리가 생길
/// 뿐 아무 오류도 나지 않아서, 오타를 눈으로 찾게 된다.
abstract final class AppIcons {
  static const addFriend = 'add_friend';
  static const badge = 'badge';
  static const bell = 'bell';
  static const book = 'book';
  static const calendar = 'calendar';
  static const camera = 'camera';
  static const check = 'check';
  static const check2 = 'check_2';
  static const close = 'close';
  static const color = 'color';
  static const down = 'down';
  static const exit = 'exit';
  static const friend = 'friend';
  static const guide = 'guide';
  static const home = 'home';
  static const home2 = 'home_2';
  static const left = 'left';
  static const map = 'map';
  static const map2 = 'map_2';
  static const microphone = 'microphone';
  static const people = 'people';
  static const photo = 'photo';
  static const profile = 'profile';
  static const right = 'right';
  static const running = 'running';
  static const search = 'search';
  static const settings = 'settings';
  static const shoes = 'shoes';
  static const stop = 'stop';
  static const verified = 'verified';
  static const verified2 = 'verified_2';
  static const view = 'view';
  static const view2 = 'view_2';

  /// 전부. 테스트가 파일과 대조하는 데 쓴다.
  static const all = <String>[
    addFriend,
    badge,
    bell,
    book,
    calendar,
    camera,
    check,
    check2,
    close,
    color,
    down,
    exit,
    friend,
    guide,
    home,
    home2,
    left,
    map,
    map2,
    microphone,
    people,
    photo,
    profile,
    right,
    running,
    search,
    settings,
    shoes,
    stop,
    verified,
    verified2,
    view,
    view2,
  ];

  /// [name]이 놓인 자리.
  static String pathOf(String name) => 'assets/icons/$name.svg';
}

/// 새 디자인의 아이콘 하나.
///
/// ## ⚠️ 색은 언제나 덮어쓴다
///
/// 내보낸 SVG 33개가 전부 `fill="#227DFF"`(켜진 상태의 파랑)로 굳어 있다.
/// 그대로 그리면 꺼진 탭도 파랗다. 그래서 [color]를 주지 않으면
/// `textPrimary`로 칠한다 — **원본 색이 그대로 나오는 경로는 없다.**
///
/// ## Lucide와 섞어 쓰지 않는다
///
/// 옮긴 화면은 이것만, 안 옮긴 화면은 Lucide만 쓴다. 한 화면에 둘이 섞이면
/// 선 굵기와 모서리가 달라 눈에 띈다.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 24, this.color});

  /// [AppIcons]의 상수를 넘긴다.
  final String name;

  /// 시안의 아이콘이 전부 24×24다.
  final double size;

  /// 없으면 `AppColorsV2.textPrimary`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      AppIcons.pathOf(name),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? context.appColorsV2.textPrimary,
        BlendMode.srcIn,
      ),
    );
  }
}
