// 앱 모듈 — Compose + Room(KSP) + DataStore + Haze. 화면은 Phase 1부터(오늘·생리기록 시트).
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.room)
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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    buildTypes {
        release {
            // 로컬 성능 실측용 — debug 키로 서명해 에뮬레이터·사이드로드 설치 가능(Play 제출은 별도 키·P1).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

room {
    // 스키마 JSON을 리포에 남긴다 — iOS와 달리 마이그레이션이 필요해지는 시점을 diff로 본다.
    schemaDirectory("$projectDir/schemas")
}

// iOS 에셋 공유(2026-09-04 사용자 위임 결정): 서체(23MB)·모티프 PNG를 리포에 두 번 두지 않고 빌드 때 `App/`에서 복사한다.
// 산출 res 디렉터리는 build 밖 ASCII 경로여도 상관없지만, 빌드 디렉터리(한글 경로 우회로 ~/.temporoutine-android-build)에 둔다.
val iosRoot = rootDir.parentFile   // …/TempoRoutine
// Provider가 아닌 File로 넘긴다 — AGP 9는 SourceSet에 Provider 추가를 거부한다. 태스크 의존은 아래 preBuild.dependsOn이 맡는다.
val iosAssetsRes: File = layout.buildDirectory.dir("generated/iosAssets/res").get().asFile
val syncIosAssets by tasks.registering(Copy::class) {
    description = "iOS App/Fonts·Assets.xcassets에서 서체·모티프를 Android res로 복사"
    into(iosAssetsRes)
    from(File(iosRoot, "App/Fonts/NotoSerifKR-Variable.ttf")) { into("font"); rename { "notoserifkr_variable.ttf" } }
    // 캘린더 셀 숫자 = Gowun Batang 14(오늘 Bold) — 은필도 숫자만 이 서체(SeasonCalendarView.numberFont)
    from(File(iosRoot, "App/Fonts/GowunBatang-Regular.ttf")) { into("font"); rename { "gowunbatang_regular.ttf" } }
    from(File(iosRoot, "App/Fonts/GowunBatang-Bold.ttf")) { into("font"); rename { "gowunbatang_bold.ttf" } }
    for (season in listOf("Winter", "Spring", "Summer", "Autumn")) {
        from(File(iosRoot, "App/Assets.xcassets/Motif$season.imageset/Motif$season.png")) {
            into("drawable-nodpi"); rename { "motif_${season.lowercase()}.png" }
        }
    }
}
android.sourceSets["main"].res.srcDir(iosAssetsRes)
tasks.named("preBuild") { dependsOn(syncIosAssets) }

dependencies {
    implementation(project(":tempocore"))
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.haze)
    implementation(libs.haze.materials)

    testImplementation(libs.kotlin.test)
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.platform.launcher)

    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.room.testing)
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
}
