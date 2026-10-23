/// 앱 버전 이름. `MAJOR.MINOR.PATCH` 세 부분이다.
///
/// ## ⚠️ 문자열로 비교하지 않는다
///
/// 명세가 따로 못 박은 지점이다 — 문자열로 견주면 **`1.10.0`이 `1.9.0`보다
/// 낮게** 나온다(`'1'` < `'9'`). 서버가 이 값으로 구버전을 막으므로, 비교가
/// 틀리면 **멀쩡한 최신 앱이 업데이트 화면에 갇힌다.**
///
/// 부분마다 정수로 견준다.
///
/// ## 빌드 번호가 아니다
///
/// 스토어에 보이는 **버전 이름**이다(`pubspec.yaml`의 `1.0.0`). 빌드 번호
/// (`+7`)는 서버가 보지 않는다 — 같은 이름으로 여러 번 올릴 수 있어서 구별에
/// 쓸 수 없다.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// 부분마다 **9자리까지**다. 명세가 정한 한도다.
  static const _maxDigits = 9;

  /// 읽는다. **형식이 아니면 `null`이다.**
  ///
  /// ⚠️ **못 읽은 것을 `0.0.0`으로 눌러선 안 된다.** 그러면 어떤 최소 버전에도
  /// 못 미치는 값이 되어, 값을 못 읽었을 뿐인 사용자가 영영 업데이트 화면에
  /// 갇힌다. 못 읽었다는 사실 그대로 올려 보내고 판정을 하지 않는다.
  ///
  /// 빌드 번호가 붙은 `1.0.0+7`도 받는다. `package_info_plus`는 이름만 주지만,
  /// `pubspec`에서 직접 읽는 경로가 생기면 그 꼴로 들어온다.
  static AppVersion? parse(String? text) {
    if (text == null) return null;

    final name = text.trim().split('+').first;
    final parts = name.split('.');
    if (parts.length != 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > _maxDigits) return null;
      // ⚠️ **`int.tryParse`만으로는 모자라다.** `+5`·`-5`·` 5`를 받아주므로
      // `1.+2.3` 같은 것이 통과한다. 숫자만 있는지 따로 본다.
      if (!_digitsOnly(part)) return null;
      numbers.add(int.parse(part));
    }

    return AppVersion(numbers[0], numbers[1], numbers[2]);
  }

  static bool _digitsOnly(String text) =>
      text.codeUnits.every((unit) => unit >= 0x30 && unit <= 0x39);

  @override
  int compareTo(AppVersion other) {
    final byMajor = major.compareTo(other.major);
    if (byMajor != 0) return byMajor;
    final byMinor = minor.compareTo(other.minor);
    if (byMinor != 0) return byMinor;
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  /// 서버에 싣는 꼴. `X-App-Version` 헤더가 이것을 쓴다.
  @override
  String toString() => '$major.$minor.$patch';
}
