plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

// 한글 경로(템포루틴) 우회 — 2026-09-04 실측: Gradle이 테스트 워커 @argfile을 UTF-8로 쓰는데 java.exe는
// 시스템 코드페이지(CP949)로 읽어 non-ASCII 클래스패스 항목이 깨진다 → 전 테스트 클래스 ClassNotFoundException.
// 빌드 산출물(클래스패스 항목)을 ASCII 경로로 두면 argfile에 한글이 안 실린다. ASCII 경로(CI·이사 후)에선 미적용.
val projectPathIsAscii = rootDir.path.all { it.code < 128 }
subprojects {
    if (!projectPathIsAscii) {
        layout.buildDirectory.set(File(System.getProperty("user.home"), ".temporoutine-android-build/${project.name}"))
    }
}
