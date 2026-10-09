import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // google-services.json 을 읽어 Firebase 설정을 빌드에 심는다.
    // 운영은 app/, 개발(debug·profile)은 src/<타입>/ 아래 것을 가져간다.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 업로드 키 자격증명. flavor마다 키가 다르다 — prod는 `android/key.properties`,
// dev는 `android/key-dev.properties`. 둘 다 gitignore 대상이라 키를 가진
// 사람의 로컬(과 CI)에만 있다.
//
// 파일이 없으면 debug 키로 되돌린다. 키가 없는 사람도 release 빌드가 돌아가야
// 하기 때문이다. 그렇게 나온 산출물은 Play가 받지 않는다.
fun loadKeystore(fileName: String): Properties? =
    rootProject.file(fileName).takeIf { it.isFile }?.let { file ->
        Properties().apply { FileInputStream(file).use { load(it) } }
    }

val prodKeystore = loadKeystore("key.properties")
val devKeystore = loadKeystore("key-dev.properties")

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
    }

    signingConfigs {
        fun uploadKey(name: String, keystore: Properties) = create(name) {
            keyAlias = keystore["keyAlias"] as String
            keyPassword = keystore["keyPassword"] as String
            storeFile = file(keystore["storeFile"] as String)
            storePassword = keystore["storePassword"] as String
        }
        prodKeystore?.let { uploadKey("prod", it) }
        devKeystore?.let { uploadKey("dev", it) }
    }

    // dev와 prod는 applicationId가 달라 한 기기에 나란히 깔린다.
    //
    // 같은 applicationId면 덮어쓰기가 실패한다 — Play 설치본은 구글이 만든 앱
    // 서명 키로, 로컬 빌드는 업로드 키나 debug 키로 서명되기 때문이다
    // (INSTALL_FAILED_UPDATE_INCOMPATIBLE). 개발은 `--flavor dev`로 한다.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appLabel"] = "Runiverse-dev"
            signingConfig = signingConfigs.findByName("dev") ?: signingConfigs.getByName("debug")
        }
        create("prod") {
            dimension = "env"
            manifestPlaceholders["appLabel"] = "Runiverse"
            signingConfig = signingConfigs.findByName("prod") ?: signingConfigs.getByName("debug")
        }
    }
    // debug·profile 빌드는 buildType의 debug 키가 이기고, release만 flavor의 키를 탄다.
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
