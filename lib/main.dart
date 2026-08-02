import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/app/app.dart';

/// 앱 진입점. 여기서는 딱 두 가지만 한다 —
/// Riverpod 스코프를 열고, 앱 루트를 띄운다.
///
/// [ProviderScope]는 provider가 값을 보관하는 그릇이다. 아직 provider가 하나도
/// 없지만 미리 심어둔다. 나중에 추가할 때 진입점을 다시 건드리지 않아도 된다.
void main() {
  runApp(const ProviderScope(child: RuniverseApp()));
}
