import java.io.File
import org.ini4j.Wini
import org.citra.citra_emu.features.settings.model.*
import org.citra.citra_emu.features.settings.utils.*
import org.citra.citra_emu.features.settings.ui.SettingsActivityView
import org.citra.citra_emu.utils.DirectoryInitialization

fun main(args: Array<String>) {
    val root = File(args[0]).apply { mkdirs() }
    DirectoryInitialization.userDirectory = root.absolutePath
    val config = File(root, "config").apply { mkdirs() }
    val global = File(config, "config.ini")
    global.writeText("[Renderer]\nresolution_factor=1\nuse_60fps_patch=0\nfilter_mode=true\n[WebService]\nweb_api_url=https://example.test/?a=b\n")
    val custom = File(config, "custom").apply { mkdirs() }
    val a = File(custom, PerGameSettings.fileName(1))
    val b = File(custom, PerGameSettings.fileName(2))
    a.writeText("[Renderer]\nresolution_factor=7\nuse_60fps_patch=true\nasync_shader_compilation=0\nuse_hw_shader=0\n[Plugin]\nsecret=keep\n")
    b.writeText("[Renderer]\nresolution_factor=3\n")
    val inherited = PerGameSettings.load(99)
    check(inherited.linearFilter == true && inherited.resolutionFactor == 1) {
        "quick menu must display inherited global values"
    }
    val globalBefore = global.readBytes()
    val bBefore = b.readBytes()
    val before = a.readBytes()
    var options = PerGameSettings.load(1)
    check(options.patch60fps == true) { "text booleans must load" }
    check(!options.boost) { "unowned renderer settings must not imply preset ownership" }
    check(PerGameSettings.save(1, options, emptySet()))
    check(a.readBytes().contentEquals(before)) { "no-op Save must not rewrite / clamp settings" }
    check(!PerGameSettings.has60fpsCodePatch(1))
    val fps = File(root, "load/60fps/0000000000000001/exefs").apply { mkdirs() }
    val patch = File(fps, "code.ips")
    patch.writeText("not a patch")
    check(!PerGameSettings.has60fpsCodePatch(1))
    patch.writeText("PATCHEOF")
    check(PerGameSettings.has60fpsCodePatch(1))
    options.patch60fps = true
    options.speedLimitPercent = 200
    check(PerGameSettings.save(1, options, setOf("patch60fps", "speedLimitPercent")))
    check(Wini(a).get("Renderer", "frame_limit") == "100") { "60 FPS must never turn into 200% emulation speed" }
    options.resolutionFactor = 1
    options.patch60fps = false
    check(PerGameSettings.save(1, options, setOf("resolutionFactor", "patch60fps")))
    fun ini() = Wini(a)
    check(ini().get("Renderer", "resolution_factor") == "1") { "can return to a default" }
    check(ini().get("Renderer", "use_60fps_patch") == "0") { "can turn 60 FPS off" }
    check(ini().get("Renderer", "async_shader_compilation") == "0") { "unrelated override survived" }
    options.integerScaling = true
    options.customTextures = true
    options.preloadTextures = false
    options.asyncTextures = true
    check(PerGameSettings.save(1, options, setOf("integerScaling", "customTextures", "preloadTextures", "asyncTextures")))
    val visuals = PerGameSettings.load(1)
    check(visuals.integerScaling == true && visuals.customTextures == true &&
        visuals.preloadTextures == false && visuals.asyncTextures == true)
    options.boost = true
    check(PerGameSettings.save(1, options, setOf("boost")))
    check(ini().get("Renderer", "use_hw_shader") == "1")
    check(ini().get("Renderer", "resolution_factor") == "1") { "boost must preserve chosen resolution" }
    check(ini().get("Utility", "dump_textures") == "0")
    check(ini().get("Utility", "async_custom_loading") == "1")
    // An advanced edit while the boost preset is active must not be lost.
    val edited = ini().apply { put("Renderer", "use_hw_shader", 0) }
    edited.store(a)
    options.boost = false
    check(PerGameSettings.save(1, options, setOf("boost")))
    check(ini().get("Renderer", "async_shader_compilation") == "0") { "restore original override" }
    check(ini().get("Renderer", "use_hw_shader") == "0") { "preserve post-preset edit" }
    check(ini().get("Renderer", "use_vsync") == null) { "restore global inheritance" }
    check(ini().get("Plugin", "secret") == "keep")
    // Exercise real SettingsFile and enum model: this used to re-read globals into the same
    // singleton instances while saving and silently replace the chosen game's values.
    val view = object : SettingsActivityView {
        override val settings = Settings()
        override fun showSettingsFragment(menuTag: String, addToStack: Boolean, gameId: String) {}
        override fun onSettingsFileLoaded() {}
        override fun onSettingsFileNotFound() { error("Unexpected read failure") }
        override fun showToastMessage(message: String, isLong: Boolean) {}
        override fun finish() {}
        override fun onSettingChanged() {}
    }
    val sections = SettingsFile.readCustomGameSettings("0000000000000001", view)
    check(BooleanSetting.PATCH_60FPS.boolean == false)
    IntSetting.RESOLUTION_FACTOR.int = 4
    sections["Renderer"]!!.putSetting(IntSetting.RESOLUTION_FACTOR)
    BooleanSetting.PATCH_60FPS.boolean = true
    sections["Renderer"]!!.putSetting(BooleanSetting.PATCH_60FPS)
    SettingsFile.saveCustomGameSettings("0000000000000001", sections, view)
    check(IntSetting.RESOLUTION_FACTOR.int == 4) { "saving must not mutate active enum values" }
    check(ini().get("Renderer", "resolution_factor") == "4")
    check(ini().get("Renderer", "use_60fps_patch") == "true")
    check(ini().get("Plugin", "secret") == "keep") { "advanced save preserves unknown keys" }
    SettingsFile.readCustomGameSettings("0000000000000001", view)
    check(BooleanSetting.PATCH_60FPS.boolean) { "boolean round-trip" }
    val second = PerGameSettings.load(2).apply { resolutionFactor = 1 }
    check(PerGameSettings.save(2, second, setOf("resolutionFactor")))
    check(PerGameSettings.load(1).resolutionFactor == 4)
    check(PerGameSettings.load(2).resolutionFactor == 1) { "title resolutions must be independent" }
    b.writeBytes(bBefore)
    check(global.readBytes().contentEquals(globalBefore)) { "global file must never change" }
    check(b.readBytes().contentEquals(bBefore)) { "other titles must never change" }
    BooleanSetting.ASYNC_SHADERS.boolean = false
    view.settings.loadSettings("0000000000000002", view)
    check(BooleanSetting.ASYNC_SHADERS.boolean == BooleanSetting.ASYNC_SHADERS.defaultValue) {
        "missing global keys must not retain the previous title's value"
    }
    check(PerGameSettings.reset(1))
    check(!a.exists())
    check(b.exists() && global.exists())
    println("PASS: no-op saves, default/60-FPS toggles, preset ownership/restoration, unknown keys, enum mutation, title isolation, reset")
}
