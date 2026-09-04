// 앱 모듈 — Phase 0은 툴체인 검증용 껍데기(Compose 진입점 1개). 화면은 Phase 1부터.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.temporoutine.android"
    // Compose BOM 2026.08.00(ui 1.12.0)이 compileSdk ≥37 요구(2026-09-04 실측). 플랫폼 패키지는 minor 분기(37.0/37.2).
    compileSdk = 37

    defaultConfig {
        applicationId = "app.temporoutine"
        // minSdk 31(Android 12): Haze 실블러 지원선(12/12L 우회, 11 이하 스크림) — 계획서 가정 6.
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":tempocore"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
}
