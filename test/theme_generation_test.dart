import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 한 소스가 **두 세대의 토큰을 함께** import 하는가.
///
/// 새 디자인으로 옮긴 화면은 `core/theme/v2/` 만 읽고, 아직 안 옮긴 화면은
/// 기존 `core/theme/tokens/`·`core/theme/extensions/` 만 읽는다. 섞이면
/// **"어디까지 옮겼나"를 코드로 답할 수 없고**, 되돌릴 때 무엇을 되돌려야
/// 하는지도 흐려진다.
bool mixesGenerations(String source) {
  final usesNew = source.contains('core/theme/v2/');
  if (!usesNew) return false;
  return source.contains('core/theme/tokens/') ||
      source.contains('core/theme/extensions/');
}

void main() {
  group('세대 판정', () {
    test('둘을 함께 쓰면 잡는다', () {
      const source = '''
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
''';

      expect(mixesGenerations(source), isTrue);
    });

    test('새 것만 쓰면 통과한다', () {
      const source = '''
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
''';

      expect(mixesGenerations(source), isFalse);
    });

    test('옛 것만 쓰면 통과한다', () {
      const source = '''
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
''';

      expect(mixesGenerations(source), isFalse);
    });

    test('확장도 구 세대로 센다', () {
      // `extensions/app_colors.dart` 만 함께 써도 섞인 것이다.
      const source = '''
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
''';

      expect(mixesGenerations(source), isTrue);
    });
  });

  test('⚠️ 섞어 쓰는 파일이 하나도 없다', () {
    // ⚠️ `lib/core/theme/` 자체는 뺀다. 새 토큰이 기존 팔레트를 재료로 쓸 수
    // 있고, 그것은 섞은 것이 아니라 얹은 것이다.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.contains('lib/core/theme/')) continue;
      if (mixesGenerations(entity.readAsStringSync())) offenders.add(path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '한 화면은 한 세대만 쓴다. 옮기는 중이면 그 화면의 토큰 import 를 '
          '전부 v2 로 바꾸고, 아직이면 전부 기존 것으로 되돌린다.',
    );
  });
}
