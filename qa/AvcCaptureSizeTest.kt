package com.example.liquid_remote_control

fun main() {
    check(AvcCaptureSize.fit(2560, 1600, 1280, 2, 2) == (1280 to 800))
    check(AvcCaptureSize.fit(1080, 2400, 1280, 2, 2) == (576 to 1280))
    check(AvcCaptureSize.fit(2400, 1080, 960, 16, 16) == (960 to 432))
    check(AvcCaptureSize.fit(320, 240, 1280, 2, 2) == (320 to 240))
    check(AvcCaptureSize.fit(1, 1, 1280, 2, 2) == null)
    check(runCatching { AvcCaptureSize.fit(0, 1, 640, 2, 2) }.isFailure)
    check(runCatching { AvcCaptureSize.fit(10, 10, 640, 0, 2) }.isFailure)
    println("AVC capture sizing: 7 cases passed")
}
