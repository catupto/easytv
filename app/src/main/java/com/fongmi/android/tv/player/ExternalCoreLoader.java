package com.fongmi.android.tv.player;

import android.content.Context;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * 外置原生内核包的发现、校验与解压。
 *
 * <p>原生 .so 不再打进主 APK。用户把内核包放到
 * {@code <external-files>/ext/cores/<core>-<abi>.zip}，并附带同名 {@code .sha256}
 * 清单（文件内为 zip 包整体 SHA-256 十六进制）。本类校验后解压到应用私有目录，
 * 供 {@link android.util.Log} 之外的加载器用绝对路径 System.load。
 *
 * <p>信任边界：包由用户自行放置，sha256 只用于防损坏/传输篡改，不做签名。
 * 与自有插件框架一致——用户只应从可信来源取包。
 *
 * <p>W^X 前提：targetSdk 保持 28，私有目录下 so 可 dlopen。
 */
public final class ExternalCoreLoader {

    private static final String EXT_DIR = "ext/cores";
    private static final String OUT_DIR = "external-cores";
    private static final String VERSION_FILE = ".version";

    private ExternalCoreLoader() {
    }

    /** 用户放置内核包的目录。 */
    public static File extDir(Context context) {
        File base = context.getExternalFilesDir(null);
        return new File(base == null ? context.getFilesDir() : base, EXT_DIR);
    }

    /** 内核解压后的私有目录。 */
    public static File outDir(Context context, String core, String abi) {
        return new File(new File(context.getFilesDir(), OUT_DIR), core + File.separator + abi);
    }

    /**
     * 返回已就位的 so 目录；未就位返回 null。只查文件，不触发解压。
     */
    public static File installedDir(Context context, String core, String abi) {
        File dir = outDir(context, core, abi);
        File marker = new File(dir, VERSION_FILE);
        return marker.isFile() && dir.isDirectory() ? dir : null;
    }

    /**
     * 确保内核包就位：校验 sha256 -> 解压 -> 写版本 marker。阻塞，调用方放后台线程。
     *
     * @return null 表示可用，否则为失败原因
     */
    public static synchronized String ensure(Context context, String core, String abi) {
        File installed = installedDir(context, core, abi);
        if (installed != null) return null;
        File zip = new File(extDir(context), core + "-" + abi + ".zip");
        File sum = new File(extDir(context), core + "-" + abi + ".zip.sha256");
        if (!zip.isFile()) return "缺少外置内核包: " + zip.getAbsolutePath();
        if (!sum.isFile()) return "缺少校验清单: " + sum.getAbsolutePath();
        try {
            String expected = readFirstLine(sum).trim();
            String actual = sha256(zip);
            if (!expected.equalsIgnoreCase(actual)) return "内核包 sha256 不匹配";
            File dir = outDir(context, core, abi);
            File tmp = new File(dir.getParentFile(), core + "-" + abi + ".tmp");
            deleteRecursively(tmp);
            unzip(zip, tmp);
            writeVersion(tmp, actual);
            deleteRecursively(dir);
            if (!tmp.renameTo(dir)) return "无法写入内核目录: " + dir;
            return null;
        } catch (Throwable e) {
            return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
        }
    }

    private static void unzip(File zip, File out) throws IOException {
        if (!out.exists() && !out.mkdirs()) throw new IOException("Unable to create " + out);
        try (ZipFile archive = new ZipFile(zip)) {
            Enumeration<? extends ZipEntry> entries = archive.entries();
            byte[] buffer = new byte[64 * 1024];
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                String name = entry.getName();
                if (name.contains("..") || name.startsWith("/")) throw new IOException("Unsafe zip entry: " + name);
                if (entry.isDirectory()) continue;
                File target = new File(out, name);
                File parent = target.getParentFile();
                if (parent != null && !parent.exists() && !parent.mkdirs()) throw new IOException("Unable to create " + parent);
                try (InputStream in = archive.getInputStream(entry); FileOutputStream fos = new FileOutputStream(target)) {
                    int read;
                    while ((read = in.read(buffer)) != -1) fos.write(buffer, 0, read);
                }
            }
        }
    }

    private static void writeVersion(File dir, String version) throws IOException {
        try (FileOutputStream out = new FileOutputStream(new File(dir, VERSION_FILE))) {
            out.write(version.getBytes("UTF-8"));
        }
    }

    private static String readFirstLine(File file) throws IOException {
        try (InputStream in = new FileInputStream(file)) {
            byte[] bytes = new byte[256];
            int read = in.read(bytes);
            return read < 0 ? "" : new String(bytes, 0, read, "UTF-8").split("\\R", 2)[0];
        }
    }

    private static String sha256(File file) throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(file)) {
            byte[] buffer = new byte[64 * 1024];
            int read;
            while ((read = in.read(buffer)) != -1) digest.update(buffer, 0, read);
        }
        byte[] hash = digest.digest();
        StringBuilder sb = new StringBuilder(hash.length * 2);
        for (byte b : hash) sb.append(String.format("%02x", b));
        return sb.toString();
    }

    private static void deleteRecursively(File file) {
        if (file == null || !file.exists()) return;
        File[] children = file.listFiles();
        if (children != null) for (File child : children) deleteRecursively(child);
        file.delete();
    }
}
