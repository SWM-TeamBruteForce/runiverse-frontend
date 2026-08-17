import 'package:image_picker/image_picker.dart' as picker;
import 'package:runiverse/features/profile/domain/photo_picker.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';

/// 기기 앨범에서 고른다.
///
/// ⚠️ `image_picker`의 `ImageSource`와 이 앱의 이름이 겹칠 수 있어 **접두사를 붙여
/// import**한다. 겹친 채로 두면 어느 쪽 타입인지 읽는 사람이 헷갈린다.
///
/// ## 크기를 줄이지 않는다
///
/// `pickImage`에는 `maxWidth`·`imageQuality`가 있다. 쓰지 않는 이유는 그것이
/// **파일 크기를 바꾸기 때문**이다. 줄인 뒤의 크기를 다시 재서 서명을 받아야 하는데,
/// 재는 시점과 올리는 시점 사이에 값이 갈리면 403이 되고 원인이 보이지 않는다.
/// 10MB를 넘는 사진은 [PickedImage.validated]가 여기서 막는다.
class GalleryPhotoPicker implements PhotoPicker {
  const GalleryPhotoPicker();

  @override
  Future<PickedImage?> pick() async {
    final file = await picker.ImagePicker().pickImage(
      source: picker.ImageSource.gallery,
    );
    // 취소했다. 실패가 아니다.
    if (file == null) return null;

    // 조건에 맞지 않으면 여기서 던진다. 서버까지 보내고 400을 받는 것보다
    // 왕복 한 번을 아끼고, 무엇이 문제였는지 정확히 말해줄 수 있다.
    return PickedImage.validated(
      path: file.path,
      sizeBytes: await file.length(),
    );
  }
}
