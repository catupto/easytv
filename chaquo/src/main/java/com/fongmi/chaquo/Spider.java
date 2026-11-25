package com.fongmi.chaquo;

import android.content.Context;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

// PLUGIN-05: Python runtime removed. Compatibility shell extends the base Spider
// with no-op behaviour; kept only so existing callers/tests still compile.
// Legacy (PyObject, PyObject, String) constructor represented as (Object, Object, String).
public class Spider extends com.github.catvod.crawler.Spider {

    private final String api;

    public Spider(Object app, Object obj, String api) {
        this.api = api;
    }

    @Override
    public void init(Context context, String extend) {
    }

    @Override
    public String homeContent(boolean filter) {
        return null;
    }

    @Override
    public String homeVideoContent() {
        return null;
    }

    @Override
    public String categoryContent(String tid, String pg, boolean filter, HashMap<String, String> extend) {
        return null;
    }

    @Override
    public String detailContent(List<String> ids) {
        return null;
    }

    @Override
    public String searchContent(String key, boolean quick) {
        return null;
    }

    @Override
    public String searchContent(String key, boolean quick, String pg) {
        return null;
    }

    @Override
    public String playerContent(String flag, String id, List<String> vipFlags) {
        return null;
    }

    @Override
    public String liveContent(String url) {
        return null;
    }

    @Override
    public boolean manualVideoCheck() {
        return false;
    }

    @Override
    public boolean isVideoFormat(String url) {
        return false;
    }

    @Override
    public Object[] proxy(Map<String, String> params) throws Exception {
        return null;
    }

    @Override
    public String action(String action) {
        return null;
    }

    public String subtitleInit(String config) {
        return null;
    }

    public String subtitleSearch(String request) {
        return null;
    }

    public String subtitleResolve(String request) {
        return null;
    }

    @Override
    public void destroy() {
    }
}
