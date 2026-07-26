# Keep FFI entry points and native method declarations used by llama.cpp.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
