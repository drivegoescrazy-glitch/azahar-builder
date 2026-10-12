import kotlin.system.measureNanoTime
import org.citra.citra_emu.features.settings.model.*

private var sink = 0
fun main() {
    // Representative INI keys: hits across boolean entries and missing keys from other sections.
    val keys = BooleanSetting.values().map { it.key!! } + listOf("resolution_factor", "volume", "plugin_unknown")
    fun oldLookup() {
        var checksum = 0
        repeat(3000) { for (key in keys) checksum += BooleanSetting.values().firstOrNull { it.key == key }?.ordinal ?: -1 }
        sink = checksum
    }
    fun newLookup() {
        var checksum = 0
        repeat(3000) { for (key in keys) checksum += BooleanSetting.from(key)?.ordinal ?: -1 }
        sink = checksum
    }
    repeat(5) { oldLookup(); newLookup() }
    oldLookup(); val expected = sink
    newLookup(); check(sink == expected) { "Lookup results differ" }
    val old = LongArray(7) { measureNanoTime { oldLookup() } }.sorted()[3]
    val new = LongArray(7) { measureNanoTime { newLookup() } }.sorted()[3]
    println("INI lookup microbenchmark: ${keys.size * 3000} lookups/sample, median of 7 after warm-up")
    println("Previous enum scan: ${old/1e6} ms; indexed lookup: ${new/1e6} ms; identical checksum=$sink")
    println("Host JVM microbenchmark only; no Android/gameplay FPS claim.")
}
