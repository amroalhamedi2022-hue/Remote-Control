package com.example.liquid_remote_control

/** Run with kotlinc SafReceivePolicy.kt SafReceivePolicyTest.kt -include-runtime -d policy.jar */
fun main() {
    val policy = SafReceivePolicy
    check(policy.validFileName("تقرير طبي 2026.txt"))
    check(policy.validFileName("family-photo 📷.png"))
    check(policy.validFileName("a".repeat(180)))
    check(policy.validFileName("CON-notes.txt"))
    check(policy.validFileName("COM10.txt"))
    val forbidden = listOf(
        "", ".", "..", "report.", "report ", "../escape", "folder\\\\file",
        "CON", "con.txt", "LPT1.doc", "COM¹.txt", "NUL",
        "CON .txt", "NUL .bin", "COM1 .log", "AUX .cfg",
        "CONIN\$.txt", "CONOUT\$.txt", "CON...txt",
        "LPT3 .txt", "CONIN\$ .txt", "CONOUT\$ .txt",
        ".liquidremote-hidden",
        ".NETKIT-hidden", "safe\u202Egpj.exe", "safe\u200Bname.txt",
        "bad\u007F.txt", "bad\u0085.txt", "bad\uFFFD.txt",
        "tag\uDB40\uDC20.txt", "a".repeat(181), "a:b.txt"
    )
    for (name in forbidden) {
        check(!policy.validFileName(name)) { "Accepted forbidden filename: ${name.toList()}" }
    }
    val readGrant = 1 shl 0
    val writeGrant = 1 shl 1
    check(policy.hasReadWriteTreeGrant(readGrant or writeGrant, readGrant, writeGrant))
    check(policy.hasReadWriteTreeGrant(readGrant or writeGrant or (1 shl 4), readGrant, writeGrant))
    check(!policy.hasReadWriteTreeGrant(readGrant, readGrant, writeGrant))
    check(!policy.hasReadWriteTreeGrant(writeGrant, readGrant, writeGrant))
    check(!policy.hasReadWriteTreeGrant(0, readGrant, writeGrant))

    check(policy.canStage(0, 8L * 1024 * 1024, 0))
    check(policy.canStage(0, 72L * 1024 * 1024, 64L * 1024 * 1024))
    check(!policy.canStage(1, 72L * 1024 * 1024, 1))
    check(!policy.canStage(0, 8L * 1024 * 1024 - 1, 0))
    check(!policy.canStage(0, 72L * 1024 * 1024 - 1, 64L * 1024 * 1024))
    check(!policy.canStage(0, Long.MAX_VALUE, 64L * 1024 * 1024 + 1))
    check(!policy.canStage(0, Long.MAX_VALUE, -1))
    println("PASS: SAF filename parity, Unicode spoofing, single-stage and cache quotas")
}
