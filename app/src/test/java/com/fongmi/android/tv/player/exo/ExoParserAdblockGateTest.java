package com.fongmi.android.tv.player.exo;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.nio.file.Files;
import java.nio.file.Path;

/** MediaItem enables the patched Exo ad parser only when both ad blocking and its fallback toggle are enabled. */
public class ExoParserAdblockGateTest {

    @Test
    public void parserAdblockRequiresMasterSwitchAndFallbackToggle() throws Exception {
        String source = Files.readString(Path.of("src/main/java/com/fongmi/android/tv/player/exo/ExoUtil.java"));

        // Batch 2.1 moved this read onto SettingSource; the gate must still require BOTH the
        // master adblock switch AND the legacy fallback toggle, and must keep adblock's
        // default of true (a silent flip to false would disable ad blocking by default).
        assertTrue(source.contains("builder.setAdblock(SettingSource.current().getBoolean(SettingKeys.ADBLOCK, true) && HlsRuleConfig.isLegacyFallbackEnabled())"));
        assertFalse(source.contains("!HlsRuleConfig.getRules().isEmpty()"));
        assertFalse(source.contains("builder.setAdblock(SettingSource.current().getBoolean(SettingKeys.ADBLOCK, true))"));
        assertFalse("adblock must not default to false", source.contains("getBoolean(SettingKeys.ADBLOCK, false)"));
    }
}
