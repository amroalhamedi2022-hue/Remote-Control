package com.example.liquid_remote_control

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

    fun validFileName(name: String): Boolean {
        if (name.isEmpty() || name.length > 180 || name == "." || name == ".." ||
            name.endsWith(".") || name.endsWith(" ") ||
            name.startsWith(".liquidremote-", ignoreCase = true) ||
            name.startsWith(".netkit-", ignoreCase = true) ||
            Regex("^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(\\.|$)",
                RegexOption.IGNORE_CASE).containsMatchIn(name)) return false
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
