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

    /**
     * 用户放置内核包的目录（首选）。
     *
     * <p>必须主动 mkdirs：如果用户从未用文件管理器建过这个目录，或该目录曾被 adb shell
     * 以 shell 属主创建（导致 App 无权访问），由 App 自己创建可保证属主正确。
     */
    public static File extDir(Context context) {
        File base = context.getExternalFilesDir(null);
        File dir = new File(base == null ? context.getFilesDir() : base, EXT_DIR);
        if (!dir.isDirectory()) dir.mkdirs();
        return dir;
    }

    /**
     * 备选包目录：公共 Download/easytv-cores。
     *
     * <p>当应用私有 ext/cores 因权限问题（例如被 adb shell 以 shell 属主创建）
     * 而读不到包时，用户可以把包放到这里——公共 Download 目录任何方式写入
     * （文件管理器 / adb push）权限都正确，App 用 READ_EXTERNAL_STORAGE 即可读取。
     */
    private static File publicPkgDir() {
        return new File(android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOWNLOADS), "easytv-cores");
    }

    /** 按优先级返回所有可能的包目录。 */
    private static File[] packageDirs(Context context) {
        return new File[]{extDir(context), publicPkgDir()};
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
        StringBuilder tried = new StringBuilder();
        String lastError = null;
        // 逐个候选目录完整尝试：某个目录里的包损坏/校验失败时，
        // 必须继续尝试下一个目录，而不是选中第一个存在的文件就放弃。
        for (File dir : packageDirs(context)) {
            File zip = new File(dir, core + "-" + abi + ".zip");
            File sum = new File(dir, core + "-" + abi + ".zip.sha256");
            tried.append(zip.getAbsolutePath()).append(' ');
            if (!zip.isFile() || !sum.isFile()) continue;
            try {
                String expected = readFirstLine(sum).trim();
                String actual = sha256(zip);
                if (!expected.equalsIgnoreCase(actual)) {
                    lastError = "内核包 sha256 不匹配: " + zip.getAbsolutePath();
                    continue;
                }
                File out = outDir(context, core, abi);
                File tmp = new File(out.getParentFile(), core + "-" + abi + ".tmp");
                deleteRecursively(tmp);
                unzip(zip, tmp);
                writeVersion(tmp, actual);
                deleteRecursively(out);
                if (!tmp.renameTo(out)) return "无法写入内核目录: " + out;
                return null;
            } catch (Throwable e) {
                lastError = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            }
        }
        return lastError != null ? lastError : "缺少外置内核包或校验清单（已查找: " + tried + "）";
    }

    /**
     * 按设备支持的 ABI 顺序尝试就位内核包，返回第一个可用的 so 目录。
     *
     * <p>这是给加载器用的统一入口：它先对【每个】ABI 调用 {@link #ensure}（会触发首次解压），
     * 再取目录。不要先只用 installedDir() 过滤 ABI——首次安装时还没有解压目录，
     * 那样会导致包永远得不到解压机会（MPV 曾经的 bug）。
     *
     * @return 可用的 so 目录；全部失败返回 null
     */
    public static File ensureAny(Context context, String core) {
        // 只用设备首选 ABI。64 位设备上若同时放了 arm64-v8a 和 armeabi-v7a 包，
        // 绝不能降级加载 32 位 so——dlopen 会因架构不匹配失败
        // （"is 32-bit instead of 64-bit"），且一旦加载失败 loadError 会污染整个进程。
        String[] abis = android.os.Build.SUPPORTED_ABIS;
        if (abis.length == 0) return null;
        String abi = abis[0];
        String error = ensure(context, core, abi);
        if (error != null) return null;
        return installedDir(context, core, abi);
    }

    /** 诊断信息：列出每个 ABI 的包状态，供失败时展示，避免静默失败。 */
    public static String diagnose(Context context, String core) {
        StringBuilder sb = new StringBuilder();
        for (File dir : packageDirs(context)) {
            String[] listed = dir.list();
            sb.append("dir=").append(dir.getAbsolutePath())
                    .append(" listable=").append(listed != null)
                    .append(" files=").append(listed == null ? -1 : listed.length).append('\n');
        }
        for (String abi : android.os.Build.SUPPORTED_ABIS) {
            String error = ensure(context, core, abi);
            sb.append(core).append('/').append(abi).append(": ")
                    .append(error == null ? "OK" : error).append('\n');
        }
        return sb.toString();
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
