package android.app;
public class ActivityManager {
    public static class MemoryInfo { public long availMem; public long totalMem; public boolean lowMemory; public MemoryInfo() {} }
    public void getMemoryInfo(MemoryInfo m) {}
    public int getMemoryClass() { return 0; }
    public boolean isLowRamDevice() { return false; }
}
