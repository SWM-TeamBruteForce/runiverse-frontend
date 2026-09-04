import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리스 서명 자격증명. `android/key.properties`는 gitignore 대상이라
// 저장소에 없다 — 업로드 키스토어를 가진 사람의 로컬에만 있다.
//
// 파일이 없으면 아래 buildTypes에서 debug 키로 되돌린다. 키스토어가 없는
// 사람도 `flutter build --release`가 그대로 돌아가야 하기 때문이다. 그렇게
// 나온 산출물은 Play에 올릴 수 없지만, 올릴 일도 없다.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

android {
    namespace = "com.runiverse.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.runiverse.app"
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

        // 런처에 뜨는 이름. 개발 빌드는 아래 buildTypes에서 덮어쓴다.
        manifestPlaceholders["appLabel"] = "runiverse"
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        // 개발 빌드는 applicationId가 달라 Play에서 받은 앱과 나란히 깔린다.
        //
        // 같은 applicationId면 덮어쓰기가 실패한다 — Play 설치본은 구글이
        // 만든 앱 서명 키로, 로컬 빌드는 업로드 키나 debug 키로 서명되기
        // 때문이다(INSTALL_FAILED_UPDATE_INCOMPATIBLE). 지우고 깔면 되지만
        // 그러면 로그인과 러닝 기록이 함께 날아간다.
        debug {
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appLabel"] = "runiverse dev"
        }

        // `profile`은 Flutter가 만드는 타입이다. DEBUG 리본 없이 돌려보는
        // 용도라 이것도 개발 빌드로 친다. 이미 있으면 그대로 가져온다.
        maybeCreate("profile").apply {
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appLabel"] = "runiverse dev"
        }

        release {
            // key.properties가 있으면 업로드 키로, 없으면 종전대로 debug 키로
            // 서명한다. Play는 debug 서명을 거부하므로 업로드용 산출물은
            // 반드시 키스토어를 가진 쪽에서 빌드해야 한다.
            signingConfig = signingConfigs.getByName(
                if (keystorePropertiesFile.exists()) "release" else "debug"
            )
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
