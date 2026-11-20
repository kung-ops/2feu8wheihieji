package android.os;
public class Build {
    // Not compile-time constants (like the real android.jar), so javac
    // doesn't inline them into the test apps.
    public static final String MODEL = System.getProperty("x");
    public static class VERSION {
        public static final int SDK_INT = Integer.getInteger("x", 0);
        public static final String RELEASE = System.getProperty("x");
    }
}
