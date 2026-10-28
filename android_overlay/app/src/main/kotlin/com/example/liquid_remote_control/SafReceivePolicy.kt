package com.example.liquid_remote_control

import java.util.Locale

/**
 * Pure Kotlin safety policy shared by the native SAF receiver and JVM tests.
 * No filesystem writes, Android permissions, or network side effects.
 */
internal object SafReceivePolicy {
    const val maxFileBytes = 64L * 1024 * 1024
    const val minimumCacheReserve = 8L * 1024 * 1024

    fun canStage(activeSessions: Int, usableCacheBytes: Long, incomingBytes: Long): Boolean =
        activeSessions == 0 && incomingBytes in 0..maxFileBytes &&
            usableCacheBytes >= incomingBytes + minimumCacheReserve

    /** SAF publication writes a temporary document and then reads it back for SHA-256. */
    fun hasReadWriteTreeGrant(flags: Int, readFlag: Int, writeFlag: Int): Boolean =
        (flags and readFlag) != 0 && (flags and writeFlag) != 0

    private fun isWindowsReservedDeviceName(name: String): Boolean {
        // Windows trims ASCII spaces/dots from the device stem before the
        // extension: a name such as CON followed by a space and .txt is reserved.
        val stem = name.substringBefore('.').trimEnd(' ', '.').uppercase(Locale.ROOT)
        val reserved = setOf("CON", "PRN", "AUX", "NUL", "CONIN" + 36.toChar(), "CONOUT" + 36.toChar())
        val suffix = stem.lastOrNull()
        val numberedDevice = stem.length == 4 &&
            (stem.startsWith("COM") || stem.startsWith("LPT")) &&
            suffix != null && suffix in "123456789¹²³"
        return stem in reserved || numberedDevice
    }

    /** Reject isolated UTF-16 surrogates before names cross SAF/filesystem encoders. */
    private fun hasWellFormedUtf16(value: String): Boolean {
        var index = 0
        while (index < value.length) {
            val current = value[index]
            when {
                Character.isHighSurrogate(current) -> {
                    if (index + 1 >= value.length ||
                        !Character.isLowSurrogate(value[index + 1])) return false
                    index += 2
                }
                Character.isLowSurrogate(current) -> return false
                else -> index++
            }
        }
        return true
    }

    fun validFileName(name: String): Boolean {
        if (name.isEmpty() || name.length > 180 || !hasWellFormedUtf16(name) ||
            name == "." || name == ".." ||
            name.endsWith(".") || name.endsWith(" ") ||
            name.startsWith(".liquidremote-", ignoreCase = true) ||
            name.startsWith(".netkit-", ignoreCase = true) ||
            isWindowsReservedDeviceName(name)) return false
        if (name.any { it == '/' || it == '\\' || it == ':' ||
            it == '<' || it == '>' || it == '"' || it == '|' ||
            it == '?' || it == '*' }) return false
        var offset = 0
        while (offset < name.length) {
            val cp = Character.codePointAt(name, offset)
            if (cp < 32 || cp in 0x7f..0x9f || cp == 0xfffd ||
                cp == 0x00ad || cp == 0x034f || cp == 0x061c || cp == 0x180e ||
                cp in 0x200b..0x200f || cp in 0x2028..0x202e ||
                cp in 0x2060..0x206f || cp == 0xfeff ||
                cp in 0xfff9..0xfffb || cp in 0xe0000..0xe007f) return false
            offset += Character.charCount(cp)
        }
        return true
    }
}
