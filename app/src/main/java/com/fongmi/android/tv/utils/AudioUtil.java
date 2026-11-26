package com.fongmi.android.tv.utils;

import android.text.TextUtils;

import com.fongmi.android.tv.api.SiteApi;
import com.fongmi.android.tv.api.config.VodConfig;
import com.fongmi.android.tv.bean.Result;
import com.fongmi.android.tv.bean.Site;

import java.util.Locale;

public class AudioUtil {

    private static final String[] EXTENSIONS = {".mp3", ".flac", ".m4a", ".aac", ".wav", ".ogg", ".oga", ".opus", ".ape", ".wma", ".amr", ".mka"};

    public static boolean isAudio(Result result) {
        if (result == null || result.getUrl().isEmpty()) return false;
        String format = result.getFormat();
        if (!TextUtils.isEmpty(format) && format.toLowerCase(Locale.ROOT).contains("audio")) return true;
        return isAudioUrl(result.getUrl().v()) || isAudioUrl(result.getRealUrl());
    }

    /**
     * 批次 2.1：配置判定由调用方注入，本类不再读全局设置。
     *
     * <p>为什么改成传 {@code siteEnabled} 谓词而不是注入 {@code SettingSource}：
     * {@code utils} 最终并入 {@code :core:common}，不能反向依赖 {@code :core:setting}
     * （主方案 §2.1）。本类仍负责"站点解析"这件纯逻辑（{@code VodConfig} 查询），
     * 只把"这个站点是否在音频配置里启用"这个业务判断交回上层。
     *
     * <p>参数是 {@code (key, name) -> boolean} 而不是 {@code boolean}，因为需要站点的
     * key 与 name 两个字段才能判定——这是原实现就有的语义，没有新增能力。
     */
    public static boolean isAudioSiteEnabled(String key, java.util.function.BiPredicate<String, String> siteEnabled) {
        if (TextUtils.isEmpty(key) || SiteApi.PUSH.equals(key)) return true;
        Site site = VodConfig.get().getSite(key);
        return siteEnabled.test(site.getKey(), site.getName());
    }

    public static boolean isAudioUrl(String url) {
        String text = normalize(url);
        if (text.startsWith("mp3://") || text.startsWith("music://")) return true;
        int query = text.indexOf('?');
        if (query != -1) text = text.substring(0, query);
        int fragment = text.indexOf('#');
        if (fragment != -1) text = text.substring(0, fragment);
        for (String extension : EXTENSIONS) if (text.endsWith(extension)) return true;
        return false;
    }

    public static String cleanUrl(String url) {
        if (TextUtils.isEmpty(url)) return "";
        if (url.startsWith("mp3://")) return url.substring(6);
        if (url.startsWith("music://")) return url.substring(8);
        if (url.startsWith("file://") && !url.startsWith("file:///")) return "file:///" + url.substring(7);
        return url;
    }

    private static String normalize(String url) {
        return TextUtils.isEmpty(url) ? "" : url.trim().toLowerCase(Locale.ROOT);
    }
}
