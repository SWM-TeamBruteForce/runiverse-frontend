import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record_card/domain/card_photo_draft.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_pan.dart';

/// 9:16 칸에서 사진을 미는 미리보기.
///
/// ## ⚠️ 넘침 셈은 순수 함수로 꺼내 본다
///
/// 위젯 테스트로는 몇 픽셀 넘쳤는지 볼 수 없다. 축을 잘못 고르면 **끌어도 아무
/// 일이 없는 화면**이 되는데, 그 증상은 기기에서만 보인다.
void main() {
  group('photoOverflow', () {
    test('가로로 긴 사진은 좌우로 넘친다', () {
      // 높이 480에 맞추면 폭이 853이 된다. 270을 넘는 583이 넘침이다.
      final over = photoOverflow(
        box: const Size(270, 480),
        image: const Size(1600, 900),
      );

      expect(over.x, closeTo(583.3, 0.5));
      expect(over.y, 0);
    });

    test('세로로 긴 사진은 위아래로 넘친다', () {
      // 900×1900은 9:16보다 홀쭉하다 — 스크린숏이 이 꼴이다.
      final over = photoOverflow(
        box: const Size(270, 480),
        image: const Size(900, 1900),
      );

      expect(over.x, 0);
      expect(over.y, greaterThan(0));
    });

    test('⚠️ 흔한 세로 사진(3:4)도 좌우로 넘친다', () {
      // 0.75 > 0.5625다. 9:16 틀에서는 세로 사진조차 좌우로 넘친다 —
      // 그래서 alignY만 두면 거의 아무도 밀 수 없다.
      final over = photoOverflow(
        box: const Size(270, 480),
        image: const Size(3000, 4000),
      );

      expect(over.x, greaterThan(0));
      expect(over.y, 0);
    });

    test('9:16 사진은 어느 쪽으로도 넘치지 않는다', () {
      final over = photoOverflow(
        box: const Size(270, 480),
        image: const Size(900, 1600),
      );

      expect(over.x, closeTo(0, 0.5));
      expect(over.y, closeTo(0, 0.5));
    });

    test('크기를 모르면 0이다', () {
      // 사진을 아직 못 읽었다. 0이면 끌기를 달지 않는다.
      expect(photoOverflow(box: const Size(270, 480), image: Size.zero).x, 0);
      expect(photoOverflow(box: Size.zero, image: const Size(16, 9)).x, 0);
    });
  });

  group('CardPhotoPan', () {
    testWidgets('⚠️ 못 읽은 사진은 끌기를 달지 않고 왜인지 말한다', (tester) async {
      // 고르던 사이에 OS가 임시 폴더를 비운 자리다. 크기를 모르면 어느 축이
      // 넘치는지도 모른다.
      final pan = _Pan();
      await _pump(tester, pan: pan);

      expect(find.byType(GestureDetector), findsNothing);
      expect(find.text(AppStrings.recordCardPhotoUnreadable), findsOne);
    });

    testWidgets('enabled가 false면 끌기를 달지 않는다', (tester) async {
      final pan = _Pan();
      await _pump(tester, pan: pan, image: const Size(160, 90), enabled: false);

      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('⚠️ 가로로 넘치는 사진은 좌우로 밀린다', (tester) async {
      // 9:16 틀에서 가장 흔한 경우다. 축을 잘못 고르면 끌어도 아무 일이 없다.
      final pan = _Pan();
      await _pump(tester, pan: pan, image: const Size(160, 90));

      await tester.drag(find.byType(CardPhotoPan), const Offset(-40, 0));

      expect(pan.alignX, isNotNull, reason: '가로 끌기가 안 달렸다');
      // `Alignment(1, _)`이 오른쪽 변을 맞추는 것이라 **오른쪽이 보인다.**
      // 사진을 왼쪽으로 밀었으니 그 반대쪽이 드러나는 것이 맞다.
      expect(pan.alignX, greaterThan(0), reason: '왼쪽으로 끌면 오른쪽이 보인다');
      expect(pan.alignY, isNull, reason: '세로는 넘치지 않아 밀 데가 없다');
    });

    testWidgets('⚠️ 세로로 넘치는 사진은 위아래로 밀린다', (tester) async {
      // 스크린숏처럼 9:16보다 홀쭉한 사진이다.
      final pan = _Pan();
      await _pump(tester, pan: pan, image: const Size(90, 190));

      await tester.drag(find.byType(CardPhotoPan), const Offset(0, -40));

      expect(pan.alignY, isNotNull, reason: '세로 끌기가 안 달렸다');
      expect(pan.alignY, greaterThan(0), reason: '위로 끌면 아랫부분이 보인다');
      expect(pan.alignX, isNull);
    });

    testWidgets('끝에서 멈춘다', (tester) async {
      // 넘어가면 사진 밖을 자르게 된다.
      final pan = _Pan();
      await _pump(tester, pan: pan, image: const Size(160, 90));

      // 칸 폭의 세 배를 끈다 — 상한을 한참 넘는 거리다.
      await tester.drag(find.byType(CardPhotoPan), const Offset(-900, 0));

      expect(pan.sentX, isNotEmpty);
      expect(pan.sentX, everyElement(lessThanOrEqualTo(1.0)));
      expect(pan.sentX.last, 1.0);
    });

    testWidgets('⚠️ 이미 끝이면 아무것도 보내지 않는다', (tester) async {
      // 같은 값을 거듭 보내면 초안이 매 프레임 갈려 화면 전체가 다시 그려진다.
      final pan = _Pan();
      await _pump(tester, pan: pan, image: const Size(160, 90), alignX: -1);

      // 왼쪽 끝에서 더 왼쪽(오른쪽으로 끌기)으로 간다.
      await tester.drag(find.byType(CardPhotoPan), const Offset(900, 0));

      expect(pan.sentX, isEmpty);
    });

    testWidgets('⚠️ 민 위치가 BoxFit.cover의 정렬로 들어간다', (tester) async {
      // 미리보기와 자르기가 같은 값을 봐야 한다. 다르면 보던 것과 다른 그림이
      // 저장된다 — `CoverCrop`의 주석이 적어 둔 함정이다.
      final pan = _Pan();
      await _pump(tester, pan: pan, alignX: -0.5, alignY: 0.25);

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.cover);
      expect(image.alignment, const Alignment(-0.5, 0.25));
    });
  });
}

/// 민 값을 받아 적는다. **첫 값과 전부**를 함께 본다 — 첫 값은 축을, 전부는
/// 상한을 말한다.
class _Pan {
  double? alignX;
  double? alignY;
  final sentX = <double>[];

  void call({double? alignX, double? alignY}) {
    this.alignX ??= alignX;
    this.alignY ??= alignY;
    if (alignX != null) sentX.add(alignX);
  }
}

/// ## ⚠️ 전부 `runAsync` 안에서 한다
///
/// `flutter_test`는 가짜 시간대에서 돌아 `toImage`도, 디코더도 진행되지 않는다.
/// 밖에서 부르면 **테스트가 멈춘다.** [CardPhotoPan]은 사진 크기를 읽은 뒤에야
/// 어느 축이 넘치는지 알고, 그 전까지 끌기를 달지 않으므로 **진짜 파일이
/// 있어야** 미는 길을 밟는다. `profile_edit_page_test.dart`에 같은 전례가 있다.
Future<void> _pump(
  WidgetTester tester, {
  required _Pan pan,
  Size? image,
  double alignX = 0,
  double alignY = 0,
  bool enabled = true,
  bool light = false,
}) async {
  await tester.runAsync(() async {
    final path = image == null
        ? '${Directory.systemTemp.path}/runiverse_pan_missing.jpg'
        : await _file(image.width.toInt(), image.height.toInt());

    await tester.pumpWidget(
      MaterialApp(
        // 테마 확장이 없으면 `context.appColorsV2`가 단언에서 죽는다.
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 270,
              height: 480,
              child: CardPhotoPan(
                photo: PickedPhoto(
                  image: PickedImage.validated(path: path, sizeBytes: 1024),
                  alignX: alignX,
                  alignY: alignY,
                ),
                onAlign: pan.call,
                enabled: enabled,
              ),
            ),
          ),
        ),
      ),
    );
    // 디코더가 돌 틈. 못 읽는 경로면 `onError`가 같은 틈에 온다.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  // 읽은 크기가 `setState`로 들어온 것을 그린다.
  await tester.pump();
}

/// [width]×[height] 단색 PNG를 임시 폴더에 쓰고 경로를 준다.
///
/// 확장자가 `.jpg`인데 내용은 PNG다. [PickedImage]는 이름만 보고
/// (`_mimeTypeOf`) 디코더는 내용을 보므로 둘 다 통과한다.
Future<String> _file(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366FF),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  final stamp = DateTime.now().microsecondsSinceEpoch;
  final file = File('${Directory.systemTemp.path}/runiverse_pan_$stamp.jpg');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });
  return file.path;
}
