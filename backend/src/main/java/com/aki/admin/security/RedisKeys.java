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

    // ---------------- 站点访客:验证码与限流 ----------------

    /** 图形验证码答案:captchaId -> 答案(小写),一次性消费 */
    public static final String CAPTCHA = "aki:captcha:";

    /** 注册接口按来源 IP 限流(固定窗口计数) */
    public static final String RATE_REGISTER_IP = "aki:rate:reg:ip:";

    /** 登录接口按来源 IP 限流(防密码暴力破解) */
    public static final String RATE_LOGIN_IP = "aki:rate:login:ip:";

    public static String captcha(String captchaId) {
        return CAPTCHA + captchaId;
    }

    public static String rateRegisterIp(String ip) {
        return RATE_REGISTER_IP + ip;
    }

    public static String rateLoginIp(String ip) {
        return RATE_LOGIN_IP + ip;
    }

    // ---------------- 站点访客:邮箱验证码(找回密码 / 验证码登录) ----------------

    /** 发码接口按来源 IP 限流(防用你的邮箱配额轰炸第三方邮箱) */
    public static final String RATE_SEND_CODE_IP = "aki:rate:code:ip:";

    /** 邮箱验证码:{scene}:{email} -> 6 位数字,一次性消费 */
    public static final String EMAIL_CODE = "aki:code:";

    /** 单个验证码的校验尝试次数,防暴力猜码(6 位数字也要限次) */
    public static final String EMAIL_CODE_TRY = "aki:code:try:";

    /** 同一邮箱同一场景的发码冷却 */
    public static final String EMAIL_CODE_COOLDOWN = "aki:code:cool:";

    /** 每邮箱每日发码配额 */
    public static final String EMAIL_CODE_QUOTA = "aki:code:quota:";

    /** 验证码校验通过后换发的一次性重置令牌 -> siteUserId */
    public static final String RESET_TOKEN = "aki:reset:";

    public static String rateSendCodeIp(String ip) {
        return RATE_SEND_CODE_IP + ip;
    }

    public static String emailCode(String scene, String email) {
        return EMAIL_CODE + scene + ":" + email;
    }

    public static String emailCodeTry(String scene, String email) {
        return EMAIL_CODE_TRY + scene + ":" + email;
    }

    public static String emailCodeCooldown(String scene, String email) {
        return EMAIL_CODE_COOLDOWN + scene + ":" + email;
    }

    public static String emailCodeQuota(String email, String yyyyMMdd) {
        return EMAIL_CODE_QUOTA + email + ":" + yyyyMMdd;
    }

    public static String resetToken(String token) {
        return RESET_TOKEN + token;
    }
}
