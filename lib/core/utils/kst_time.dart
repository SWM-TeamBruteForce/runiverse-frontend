/// 서버가 쓰는 시각 표기를 다룬다 — **오프셋 없는 한국 시각.**
///
/// ## ⚠️ `DateTime.parse`를 그대로 쓰면 안 된다
///
/// 서버는 `2026-09-16T19:00:00`처럼 오프셋 없이 준다. `DateTime.parse`는
/// 오프셋이 없으면 **기기 로컬 시각으로 읽는다.** 기기가 한국이면 맞지만
/// 아니면 시차만큼 통째로 어긋난다 — 런던에 있으면 마감까지 9시간이 더 남은
/// 것처럼 보이고, 카운트다운이 그만큼 늦게 끝난다.
///
/// 서비스가 한국 시간대로만 돌아가므로(매칭 슬롯이 18:00~22:00 KST) **읽는
/// 쪽이 KST로 못 박는 것**이 맞다. 서버가 오프셋을 실어 주면 이 파일이 없어진다.
abstract final class KstTime {
  /// 한국 표준시. 서머타임이 없어 상수로 둘 수 있다.
  static const offset = Duration(hours: 9);

  /// 서버 문자열을 읽어 **그 순간의 로컬 시각**으로 준다.
  ///
  /// 돌려주는 값은 기기 시간대의 `DateTime`이다 — 화면에 그대로 그리고,
  /// `difference`로 남은 시간을 재도 맞는다.
  static DateTime? parse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final read = DateTime.tryParse(raw);
    if (read == null) return null;

    // 오프셋이 붙어 있으면 서버가 정확히 말한 것이다. 건드리지 않는다.
    if (read.isUtc) return read.toLocal();

    // 오프셋이 없다 — 읽힌 값은 **한국 벽시계**다. 그 벽시계를 UTC로 옮겨
    // 진짜 순간을 만든 뒤 기기 시간대로 되돌린다.
    return DateTime.utc(
      read.year,
      read.month,
      read.day,
      read.hour,
      read.minute,
      read.second,
      read.millisecond,
    ).subtract(offset).toLocal();
  }

  /// 지금의 **한국 벽시계.**
  ///
  /// 매칭 슬롯이 KST 기준이라, 오늘이 며칠이고 18:00이 언제인지는 이 값으로
  /// 정해야 한다. 기기가 어디에 있든 같은 답이 나온다.
  static DateTime nowWall() => DateTime.now().toUtc().add(offset);

  /// 한국 벽시계 값을 **그 순간의 로컬 시각**으로 옮긴다.
  static DateTime toLocal(DateTime wall) => DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
    wall.millisecond,
  ).subtract(offset).toLocal();

  /// 순간을 **한국 벽시계로** 옮긴다. 화면에 시각을 적을 때 쓴다.
  ///
  /// ## ⚠️ 표시는 기기 시간대를 따라가지 않는다
  ///
  /// 매칭 슬롯은 **18:00~22:00으로 고정**이다. 기기 시각으로 그리면 런던에
  /// 있는 사람에게 `10:00 슬롯`이라고 말하게 되는데, 그런 슬롯은 존재하지
  /// 않는다. 고른 것도 서버가 아는 것도 19:00이고, 화면도 그렇게 적어야 한다.
  ///
  /// 남은 시간(`difference`)은 이것으로 재지 않는다 — 그쪽은 순간끼리 빼야
  /// 맞는다. **표시는 벽시계, 계산은 순간**이다.
  static DateTime wallOf(DateTime at) => at.toUtc().add(offset);

  /// 한국 벽시계 값을 서버 표기로 적는다. 초 단위까지, 오프셋 없이.
  ///
  /// `toIso8601String()`을 쓰지 않는다 — 밀리초가 붙어 서버 형식과 어긋난다.
  static String format(DateTime wall) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${wall.year}-${two(wall.month)}-${two(wall.day)}'
        'T${two(wall.hour)}:${two(wall.minute)}:${two(wall.second)}';
  }
}
