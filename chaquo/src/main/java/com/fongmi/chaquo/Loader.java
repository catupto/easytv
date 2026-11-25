package com.fongmi.chaquo;

// PLUGIN-05: Python runtime removed. Compatibility shell kept so callers compile;
// Python spiders/subtitle scripts are unavailable and degrade to the existing
// SpiderNull / error paths. See docs/PLUGIN-05-minimal-apk.md.
public class Loader {

    public Spider spider(String api) {
        throw new IllegalStateException("Python runtime not packaged (PLUGIN-05)");
    }
}
