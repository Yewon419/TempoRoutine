// 템포루틴 Android — 루트 설정 (MASTER §5.13)
// tempocore = 순수 Kotlin/JVM (iOS TempoCore 1:1 이식, Android 의존 0) / app = Compose 앱.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "TempoRoutine"
include(":tempocore", ":app")
