package com.aki.admin.security;

/**
 * Redis 键常量
 *
 * 前缀分离不只是命名习惯,它是**权限隔离的一部分**:
 * 后台登录态只认 {@code aki:login:admin:},站点登录态只认 {@code aki:login:site:}。
 * 这样即便某一侧将来写错了代码,也读不到另一侧的会话。
 *
 * 排查提示:不要用 {@code KEYS aki:*} 列键,会阻塞 Redis;用 {@code SCAN}。
 */
public final class RedisKeys {

    private RedisKeys() {
    }

    /** 管理后台登录态:token -> sys_user.id */
    public static final String LOGIN_TOKEN_ADMIN = "aki:login:admin:";

    /** 站点访客登录态:token -> site_user.id */
    public static final String LOGIN_TOKEN_SITE = "aki:login:site:";

    /**
     * 站点访客的会话反向索引:siteUserId -> token 集合(Set)。
     * 用于"改密码后踢下线"—— 密码一改,必须让该用户已签发的所有 token 立即失效,
     * 否则盗号者手里的 token 照样能用,改密码就失去了意义。
     * 前缀用 idx: 而不是 user:,是为了和 LOGIN_TOKEN_SITE + token 的键在语义上无歧义。
     */
    public static final String SITE_USER_TOKENS = "aki:login:site:idx:";

    public static String loginTokenAdmin(String token) {
        return LOGIN_TOKEN_ADMIN + token;
    }

    public static String loginTokenSite(String token) {
        return LOGIN_TOKEN_SITE + token;
    }

    public static String siteUserTokens(Long siteUserId) {
        return SITE_USER_TOKENS + siteUserId;
    }
}
