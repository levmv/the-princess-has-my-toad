/* Test-only workaround for raylib querying the video mode of a null primary
 * monitor on X11 servers whose connectors are all disconnected. GLFW can still
 * create an ordinary GLX window on that server. No fake monitor is registered,
 * no display modes are changed, and this object is NEVER linked into the game.
 * A real monitor always uses the unmodified library. The fallback dimensions
 * are only an initial window-placement bound, not an attached display or a
 * measured refresh rate. Use only with a hidden benchmark window.
 */
typedef struct GLFWmonitor GLFWmonitor;
typedef struct { int width, height, redBits, greenBits, blueBits, refreshRate; } GLFWvidmode;
extern const GLFWvidmode *__real_glfwGetVideoMode(GLFWmonitor *);
extern void __real_glfwGetMonitorPos(GLFWmonitor *, int *, int *);
extern void __real_glfwGetMonitorWorkarea(GLFWmonitor *, int *, int *, int *, int *);
extern void __real_glfwGetMonitorPhysicalSize(GLFWmonitor *, int *, int *);
extern const char *__real_glfwGetMonitorName(GLFWmonitor *);
extern GLFWmonitor **__real_glfwGetMonitors(int *);

GLFWmonitor **__wrap_glfwGetMonitors(int *count) {
    int actual = 0;
    GLFWmonitor **monitors = __real_glfwGetMonitors(&actual);
    static GLFWmonitor *placement_only[1] = { 0 };
    if (count) *count = actual ? actual : 1;
    return actual ? monitors : placement_only;
}

const GLFWvidmode *__wrap_glfwGetVideoMode(GLFWmonitor *m) {
    static const GLFWvidmode fallback = { 3840, 2160, 8, 8, 8, 0 };
    return m ? __real_glfwGetVideoMode(m) : &fallback;
}
void __wrap_glfwGetMonitorPos(GLFWmonitor *m, int *x, int *y) {
    if (m) { __real_glfwGetMonitorPos(m, x, y); return; }
    if (x) *x = 0;
    if (y) *y = 0;
}
void __wrap_glfwGetMonitorWorkarea(GLFWmonitor *m, int *x, int *y, int *w, int *h) {
    if (m) { __real_glfwGetMonitorWorkarea(m, x, y, w, h); return; }
    if (x) *x = 0;
    if (y) *y = 0;
    if (w) *w = 3840;
    if (h) *h = 2160;
}
void __wrap_glfwGetMonitorPhysicalSize(GLFWmonitor *m, int *w, int *h) {
    if (m) { __real_glfwGetMonitorPhysicalSize(m, w, h); return; }
    if (w) *w = 0;
    if (h) *h = 0;
}
const char *__wrap_glfwGetMonitorName(GLFWmonitor *m) {
    return m ? __real_glfwGetMonitorName(m) : "no physical monitor (test only)";
}
