import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 새 세대로 옮긴 화면이 **자기 배경을 깔았는가.**
///
/// ## 왜 필요한가
///
/// 앱 테마(`AppTheme.dark()`)가 아직 옛 세대라 `Scaffold`의 기본 배경이
/// 푸른 회색(`#0B0E14`)이다. 시안의 바탕은 `#0A0A0A`다. 옮긴 화면이
/// `backgroundColor`를 빠뜨리면 **토큰은 전부 새것인데 바탕만 옛것**이 된다.
///
/// ⚠️ **눈으로도 잘 안 보인다.** 두 색의 차이가 채널당 10 안쪽이라, 화면 하나만
/// 보면 알아채기 어렵다. 스플래시와 온보딩 소개가 그렇게 두 PR을 통과했고
/// 에뮬레이터에서 화소를 재고서야 드러났다.
///
/// `test/theme_generation_test.dart`가 **import**를 보는 것과 짝이다.
/// 그쪽은 "어느 세대의 토큰을 읽는가", 이쪽은 "그 세대의 바탕을 깔았는가"를 본다.
///
/// ## 판정 방법
///
/// 소스를 읽어 `Scaffold(` 마다 뒤따르는 `backgroundColor:`를 찾는다. 위젯을
/// 띄워 재는 쪽이 정확하지만, 화면마다 provider 를 세우는 값이 이 한 줄을
/// 지키는 값보다 크다. **빠뜨림을 잡는 것이 목적**이고 빠뜨림은 소스에 드러난다.
bool usesNewGeneration(String source) =>
    source.contains('core/theme/v2/app_colors.dart');

/// `Scaffold(` 중 `backgroundColor:`를 받지 않은 것의 개수.
///
/// 여는 괄호부터 짝이 맞는 닫는 괄호까지를 그 `Scaffold`의 범위로 본다.
/// 중첩된 `Scaffold`는 각각 따로 센다.
int scaffoldsWithoutBackground(String source) {
  var missing = 0;
  var from = 0;

  while (true) {
    final start = source.indexOf('Scaffold(', from);
    if (start < 0) return missing;

    final open = start + 'Scaffold('.length;
    var depth = 1;
    var i = open;
    while (i < source.length && depth > 0) {
      final ch = source[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      }
      i++;
    }

    final body = source.substring(open, i);
    // 중첩된 Scaffold 의 인자는 그쪽 차례에 다시 본다. 여기서는 이 Scaffold 가
    // 직접 받은 것만 봐야 하는데, 안쪽 것이 깔아 둔 값을 바깥 것의 것으로
    // 세지 않도록 안쪽 범위를 지운다.
    final inner = body.indexOf('Scaffold(');
    final own = inner < 0 ? body : body.substring(0, inner);
    if (!own.contains('backgroundColor:')) missing++;

    from = open;
  }
}

void main() {
  group('판정', () {
    test('배경을 깔면 통과한다', () {
      const source = '''
return Scaffold(
  backgroundColor: colors.bgBase,
  body: SafeArea(child: Text('hi')),
);
''';
      expect(scaffoldsWithoutBackground(source), 0);
    });

    test('⚠️ 빠뜨리면 잡는다', () {
      const source = '''
return Scaffold(
  body: SafeArea(child: Text('hi')),
);
''';
      expect(scaffoldsWithoutBackground(source), 1);
    });

    test('한 파일에 둘이면 둘 다 본다', () {
      const source = '''
Widget a() => Scaffold(backgroundColor: c.bgBase, body: Text('a'));
Widget b() => Scaffold(body: Text('b'));
''';
      expect(scaffoldsWithoutBackground(source), 1);
    });
  });

  test('⚠️ 옮긴 화면은 모두 자기 배경을 깐다', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!usesNewGeneration(source)) continue;

      final missing = scaffoldsWithoutBackground(source);
      if (missing > 0) {
        offenders.add('${entity.path.replaceAll(r'\', '/')} ($missing개)');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '앱 테마가 아직 옛 세대라 Scaffold 기본 배경이 푸른 회색이다. '
          '옮긴 화면은 `backgroundColor: colors.bgBase` 를 직접 깐다. '
          '전역 테마를 바꾸는 것은 마지막 화면이 넘어온 뒤의 일이다.',
    );
  });
}
