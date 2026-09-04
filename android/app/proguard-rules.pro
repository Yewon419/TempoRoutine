# kotlinx.serialization — 직렬화 클래스·serializer 보존(라이브러리 consumer 규칙 보완)
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keep,includedescriptorclasses class app.temporoutine.**$$serializer { *; }
-keepclassmembers class app.temporoutine.** {
    *** Companion;
}
-keepclasseswithmembers class app.temporoutine.** {
    kotlinx.serialization.KSerializer serializer(...);
}
