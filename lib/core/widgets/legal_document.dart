import 'package:flutter/material.dart';
import 'package:runiverse/core/config/legal_links.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:url_launcher/url_launcher.dart';

/// 고지 문서를 브라우저로 연다.
///
/// 설정(S22.2)과 약관 동의(S03) 두 화면이 쓴다. 두 곳에 같은 코드를 두면
/// 한쪽만 고쳐지는 날이 온다.
///
/// ## ⚠️ 실패를 삼키지 않는다
///
/// [launchUrl]은 열 수 없을 때 `false`를 돌려주거나 던진다. 그대로 두면
/// **아무 일도 일어나지 않는 버튼**이 되고, 사용자는 앱이 멈춘 줄 안다.
///
/// 안드로이드에서 열리려면 매니페스트 `<queries>`에 VIEW+https 인텐트가
/// 있어야 한다. 없으면 예외도 로그도 없이 실패한다.
///
/// 주소가 아직 없는 문서([LegalLinks.terms])는 "준비 중"으로 알린다 —
/// 눌러도 조용하면 고장으로 읽힌다.
Future<void> openLegalDocument(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);

  if (!LegalLinks.isReady(url)) {
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.legalDocumentPending)),
    );
    return;
  }

  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      // 기본값이면 안드로이드는 Custom Tab으로 연다. 앱 밖으로 튕기지
      // 않으면서 뒤로가기로 돌아온다.
      mode: LaunchMode.platformDefault,
    );
  } on Object catch (error) {
    debugPrint('[legal] 문서를 열지 못했다 · $error');
  }
  if (opened) return;

  messenger.showSnackBar(
    const SnackBar(content: Text(AppStrings.legalDocumentFailed)),
  );
}
