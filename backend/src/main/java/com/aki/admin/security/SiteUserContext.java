package com.aki.admin.security;

/**
 * 当前登录的**站点访客**上下文(ThreadLocal)。
 *
 * 故意和 {@link UserContext}(管理后台用户)分成两个类,而不是在同一个类里加个类型标记:
 * 分成两个类之后,"站点接口里误用了后台用户上下文"这种错误在**编译期**就不成立,
 * 而不是等到运行时才发现取到了一个不该有的身份。
 */
public final class SiteUserContext {

    private SiteUserContext() {
    }

    private static final ThreadLocal<Long> USER_ID = new ThreadLocal<>();
    private static final ThreadLocal<String> EMAIL = new ThreadLocal<>();

    public static void set(Long siteUserId, String email) {
        USER_ID.set(siteUserId);
        EMAIL.set(email);
    }

    public static Long getUserId() {
        return USER_ID.get();
    }

    public static String getEmail() {
        return EMAIL.get();
    }

    public static void clear() {
        USER_ID.remove();
        EMAIL.remove();
    }
}
