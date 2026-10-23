plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sysmentalhealth.solace_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications, which uses java.time APIs
        // that are not available on older Android versions without desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // ONNX Runtime has ONE native runtime in this app: the speech library's (sherpa_onnx) libonnxruntime.so. The face reading's
    // Java layer is NOT taken from Maven (its own libonnxruntime.so is version-tagged VERS_1.28.0 and cannot coexist with the
    // speech library's VERS_1.28.2); see tool/prepare_onnxruntime.py. Its Java classes are in libs/, and its patched native
    // bridge (libonnxruntime4j_jni.so, which now links against the speech library's runtime) is in src/main/jniLibs/.

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sysmentalhealth.solace_mobile"
        // 23 rather than Flutter's default 21: home_widget pulls in
        // androidx.work, which requires API 23. This drops Android 5.x, which
        // is below 0.1% of devices and cannot run the widget anyway.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Keeps MediaPipe and ONNX Runtime working after the shrinker (see proguard-rules.pro).
            proguardFiles("proguard-rules.pro")
        }
    }
}

dependencies {
    // Backports java.time for flutter_local_notifications on older Android.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Front-camera frames for the optional emotion module (see CameraFrameCapture.kt).
    implementation("androidx.camera:camera-core:1.3.4")
    implementation("androidx.camera:camera-camera2:1.3.4")
    implementation("androidx.camera:camera-lifecycle:1.3.4")

    // Reading the face on the phone (see FaceModels.kt): the two face networks run in ONNX Runtime (Java classes of 1.28.0 on
    // the speech library's 1.28.2 runtime; see tool/prepare_onnxruntime.py), the expression numbers come from MediaPipe
    // (1.1.0: the same version as the server's Python package).
    implementation(files("libs/onnxruntime-android-1.28.0-classes.jar"))
    implementation("com.google.mediapipe:tasks-vision:1.1.0")
}

flutter {
    source = "../.."
}
