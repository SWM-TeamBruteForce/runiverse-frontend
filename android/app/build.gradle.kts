plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.swmaestro.runiverse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.swmaestro.runiverse"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 카카오 리다이렉트 스킴(`kakao<앱키>://oauth`)의 앱 키를 채운다.
        //
        // ⚠️ 매니페스트는 `--dart-define`을 읽지 못한다. 그것은 Dart 코드에만
        // 닿는다. 그래서 같은 값을 Gradle 프로퍼티로 한 번 더 넘긴다.
        //   flutter build apk -PKAKAO_NATIVE_APP_KEY=... --dart-define=KAKAO_NATIVE_APP_KEY=...
        //
        // 없으면 빈 문자열이라 스킴이 `kakao://oauth`가 된다. 빌드는 되지만
        // 카카오가 돌아올 곳을 찾지 못한다 — 앱은 키가 없으면 SDK를 아예
        // 초기화하지 않으므로(main.dart) 버튼이 그 상태로 눌리지는 않는다.
        manifestPlaceholders["KAKAO_NATIVE_APP_KEY"] =
            (project.findProperty("KAKAO_NATIVE_APP_KEY") as String?) ?: ""
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
