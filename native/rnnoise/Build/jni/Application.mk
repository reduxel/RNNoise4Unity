APP_ABI := armeabi-v7a arm64-v8a
APP_OPTIM := release
APP_PLATFORM := android-24
APP_STL := c++_static
APP_CPPFLAGS += -std=c++11
APP_SHORT_COMMANDS := true
# 16KB page size support (NDK r27: opt-in, r28+: default)
APP_SUPPORT_FLEXIBLE_PAGE_SIZES := true
