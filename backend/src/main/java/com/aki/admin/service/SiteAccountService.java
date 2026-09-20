package com.aki.admin.service;

import com.aki.admin.common.BusinessException;
import com.aki.admin.common.RateLimiter;
import com.aki.admin.dto.SiteEmailCodeRequest;
import com.aki.admin.dto.SiteLoginRequest;
import com.aki.admin.dto.SiteRegisterRequest;
import com.aki.admin.dto.SiteResetPasswordRequest;
import com.aki.admin.dto.SiteResetVerifyRequest;
import com.aki.admin.entity.SiteUser;
import com.aki.admin.mapper.SiteUserMapper;
import com.aki.admin.security.JwtUtil;
import com.aki.admin.security.RedisKeys;
import com.aki.admin.security.SiteUserContext;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * 站点访客账号服务:注册 / 登录 / 退出 / 当前用户。
 *
 * 与后台的 {@link AuthService} 是两条独立链路:
 *   - 本类只操作 site_user 表,永远不会去查 sys_user
 *   - 签发的 token 一律带 scope=site,后台拦截器会直接拒绝(阶段 1 已实现并验证)
 *   - 登录态写在 aki:login:site: 前缀下,与后台的登录态互不可见
 */
@Service
public class SiteAccountService {

    private static final Logger log = LoggerFactory.getLogger(SiteAccountService.class);

    /** 一次性重置令牌有效期 */
    private static final Duration RESET_TOKEN_TTL = Duration.ofMinutes(10);

    /** 同一 IP 每小时允许的注册尝试次数 */
    private static final int REGISTER_LIMIT_PER_HOUR = 10;
    /** 同一 IP 每分钟允许的登录尝试次数(防密码暴力破解) */
    private static final int LOGIN_LIMIT_PER_MINUTE = 20;

    private final SiteUserMapper siteUserMapper;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;
    private final StringRedisTemplate redisTemplate;
    private final CaptchaService captchaService;
    private final RateLimiter rateLimiter;
    private final EmailCodeService emailCodeService;

    @Value("${aki.jwt.expire-seconds}")
    private long expireSeconds;

    /** 注册开关:被刷爆时可以一键关掉,不用改代码重新发版 */
    @Value("${aki.site.register-enabled:true}")
    private boolean registerEnabled;

    public SiteAccountService(SiteUserMapper siteUserMapper, PasswordEncoder passwordEncoder,
                              JwtUtil jwtUtil, StringRedisTemplate redisTemplate,
                              CaptchaService captchaService, RateLimiter rateLimiter,
                              EmailCodeService emailCodeService) {
        this.siteUserMapper = siteUserMapper;
        this.passwordEncoder = passwordEncoder;
        this.jwtUtil = jwtUtil;
        this.redisTemplate = redisTemplate;
        this.captchaService = captchaService;
        this.rateLimiter = rateLimiter;
        this.emailCodeService = emailCodeService;
    }

    /**
     * 注册:限流 -> 校验图形验证码 -> 建号 -> 直接签发登录态(注册即登录)
     */
    public Map<String, Object> register(SiteRegisterRequest request, HttpServletRequest httpRequest) {
        if (!registerEnabled) {
            throw new BusinessException("当前未开放注册");
        }
        // 限流放最前面:机器人批量注册不该有机会去消耗验证码校验
        rateLimiter.check(RedisKeys.rateRegisterIp(rateLimiter.clientIp(httpRequest)),
                REGISTER_LIMIT_PER_HOUR, Duration.ofHours(1));
        captchaService.verify(request.getCaptchaId(), request.getCaptchaCode());

        SiteUser user = new SiteUser();
        user.setEmail(normalizeEmail(request.getEmail()));
        user.setNickname(request.getNickname().trim());
        user.setPassword(passwordEncoder.encode(request.getPassword()));
        user.setStatus(1);
        // 2a 阶段还没接邮件通道,邮箱先不做验证;2b 接上后再置 1
        user.setEmailVerified(0);
        user.setLoginCount(0);
        try {
            siteUserMapper.insert(user);
        } catch (DuplicateKeyException e) {
            // 靠唯一索引兜住并发:先 select 再 insert 在并发下会双双通过检查,只有唯一索引可靠。
            // 代价是这里会告诉调用方"该邮箱已注册" —— 注册接口回避不了这一点,
            // 否则用户不知道为什么注册失败。真正需要防账号枚举的是找回密码接口。
            throw new BusinessException("该邮箱已注册,请直接登录");
        }
        return issueSession(user, httpRequest);
    }

    /**
     * 登录(2a:邮箱 + 密码)
     */
    public Map<String, Object> login(SiteLoginRequest request, HttpServletRequest httpRequest) {
        // 按 IP 限流:没有它就可以对着一个邮箱无限撞密码
        rateLimiter.check(RedisKeys.rateLoginIp(rateLimiter.clientIp(httpRequest)),
                LOGIN_LIMIT_PER_MINUTE, Duration.ofMinutes(1));

        SiteUser user = siteUserMapper.selectOne(
                new LambdaQueryWrapper<SiteUser>().eq(SiteUser::getEmail, normalizeEmail(request.getEmail())));
        // 三种失败(邮箱不存在 / 密码为空 / 密码不匹配)统一话术:不泄露邮箱是否已注册
        if (user == null || user.getPassword() == null
                || !passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new BusinessException("邮箱或密码错误");
        }
        if (user.getStatus() == null || user.getStatus() != 1) {
            throw new BusinessException("账号已被禁用");
        }
        return issueSession(user, httpRequest);
    }

    /**
     * 退出登录。除了删掉登录态,还要把它从反向索引里摘掉,
     * 否则索引会无限增长(那也是后续"改密踢下线"要用的集合)。
     */
    public void logout(String authorization) {
        if (!StringUtils.hasText(authorization) || !authorization.startsWith("Bearer ")) {
            return;
        }
        String token = authorization.substring(7);
        String tokenKey = RedisKeys.loginTokenSite(token);
        String userId = redisTemplate.opsForValue().get(tokenKey);
        redisTemplate.delete(tokenKey);
        if (StringUtils.hasText(userId)) {
            redisTemplate.opsForSet().remove(RedisKeys.siteUserTokens(Long.valueOf(userId)), token);
        }
    }

    /**
     * 当前登录访客信息。身份来自 SiteUserContext(由 SiteAuthInterceptor 写入),
     * 不信任任何请求参数里的 id。
     */
    public Map<String, Object> me() {
        SiteUser user = siteUserMapper.selectById(SiteUserContext.getUserId());
        if (user == null) {
            throw new BusinessException("账号不存在");
        }
        return buildUserInfo(user);
    }

    /**
     * 签发站点登录态。
     * scope 固定为 site —— 这一处如果写错成 admin,访客就直接拿到后台权限,
     * 所以 JwtUtil 刻意不提供"不带 scope"的重载,必须在这里显式写出来。
     */
    private Map<String, Object> issueSession(SiteUser user, HttpServletRequest httpRequest) {
        String token = jwtUtil.createToken(user.getId(), user.getEmail(), JwtUtil.SCOPE_SITE);
        Duration ttl = Duration.ofSeconds(expireSeconds);

        redisTemplate.opsForValue().set(RedisKeys.loginTokenSite(token), String.valueOf(user.getId()), ttl);
        // 反向索引:siteUserId -> 该用户当前所有 token。
        // 改密码时靠它把该用户已签发的 token 全部作废(否则盗号者手里的 token 照样能用)。
        String indexKey = RedisKeys.siteUserTokens(user.getId());
        redisTemplate.opsForSet().add(indexKey, token);
        redisTemplate.expire(indexKey, ttl);

        // 更新登录统计(updateById 只更新非 null 字段,这里只动两个字段)
        SiteUser update = new SiteUser();
        update.setId(user.getId());
        update.setLastLoginAt(LocalDateTime.now());
        update.setLoginCount((user.getLoginCount() == null ? 0 : user.getLoginCount()) + 1);
        siteUserMapper.updateById(update);

        Map<String, Object> result = new HashMap<>();
        result.put("token", token);
        result.put("user", buildUserInfo(user));
        return result;
    }

    // ---------------- 找回密码(三步:发码 -> 验码换令牌 -> 用令牌改密) ----------------

    /**
     * 第一步:发送找回密码验证码。
     *
     * **对外返回统一话术**,无论邮箱是否注册过。原因:
     * 如果这里区分"邮箱不存在",这个接口就成了账号枚举工具 ——
     * 攻击者拿一份邮箱表挨个试,就能筛出你站点的注册用户。
     *
     * 注意 {@link EmailCodeService#guard} 必须无条件执行:它负责图形验证码、
     * IP 限流、冷却与日配额。若把它挪到"邮箱存在"之后再执行,未注册邮箱就能
     * 绕过全部限流,顺带把发码接口变成高频枚举器。
     */
    public void sendResetCode(SiteEmailCodeRequest request, HttpServletRequest httpRequest) {
        String email = normalizeEmail(request.getEmail());
        emailCodeService.guard(EmailCodeService.SCENE_RESET, email,
                request.getCaptchaId(), request.getCaptchaCode(), httpRequest);

        SiteUser user = findByEmail(email);
        if (user != null && user.getStatus() != null && user.getStatus() == 1) {
            emailCodeService.dispatch(EmailCodeService.SCENE_RESET, email);
        } else {
            // 不发送,但也不报错(见方法注释)。这里会有极小的时序差异
            // (发了邮件的那条路径更慢),个人站点不为此再引入固定延时。
            log.info("找回密码请求了未注册或已禁用的邮箱,已忽略发送");
        }
    }

    /**
     * 第二步:校验验证码,换发一次性重置令牌。
     */
    public Map<String, Object> verifyResetCode(SiteResetVerifyRequest request) {
        String email = normalizeEmail(request.getEmail());
        emailCodeService.verify(EmailCodeService.SCENE_RESET, email, request.getCode());

        SiteUser user = findByEmail(email);
        if (user == null) {
            // 正常走不到:发码阶段就不会给未注册邮箱发。兜底防伪造。
            throw new BusinessException("验证码无效,请重新获取");
        }
        String token = UUID.randomUUID().toString().replace("-", "");
        redisTemplate.opsForValue().set(RedisKeys.resetToken(token),
                String.valueOf(user.getId()), RESET_TOKEN_TTL);

        Map<String, Object> result = new HashMap<>();
        result.put("resetToken", token);
        return result;
    }

    /**
     * 第三步:用一次性令牌设置新密码。
     *
     * 改完密码必须**踢掉该用户所有已登录会话**,否则"改密码"这个动作就失去意义 ——
     * 盗号者手里那串 token 在 8 小时有效期内照样能用。
     */
    public void resetPassword(SiteResetPasswordRequest request) {
        String key = RedisKeys.resetToken(request.getResetToken());
        String userId = redisTemplate.opsForValue().get(key);
        if (userId == null) {
            throw new BusinessException("重置链接已过期,请重新获取验证码");
        }
        // 一次性:取到就删,防止同一个令牌被用两次
        redisTemplate.delete(key);

        SiteUser user = siteUserMapper.selectById(Long.valueOf(userId));
        if (user == null) {
            throw new BusinessException("账号不存在");
        }
        SiteUser update = new SiteUser();
        update.setId(user.getId());
        update.setPassword(passwordEncoder.encode(request.getNewPassword()));
        siteUserMapper.updateById(update);

        revokeAllSessions(user.getId());
        log.info("站点访客 id={} 已重置密码,并踢掉其全部登录会话", user.getId());
    }

    /**
     * 删除该用户所有已签发的站点 token(靠登录时维护的反向索引)。
     * 退出登录只删单个 token,这里是批量版。
     */
    private void revokeAllSessions(Long siteUserId) {
        String indexKey = RedisKeys.siteUserTokens(siteUserId);
        Set<String> tokens = redisTemplate.opsForSet().members(indexKey);
        if (tokens != null) {
            for (String token : tokens) {
                redisTemplate.delete(RedisKeys.loginTokenSite(token));
            }
        }
        redisTemplate.delete(indexKey);
    }

    private SiteUser findByEmail(String email) {
        return siteUserMapper.selectOne(
                new LambdaQueryWrapper<SiteUser>().eq(SiteUser::getEmail, email));
    }

    private Map<String, Object> buildUserInfo(SiteUser user) {
        Map<String, Object> info = new HashMap<>();
        info.put("id", user.getId());
        info.put("email", user.getEmail());
        info.put("nickname", user.getNickname());
        info.put("avatar", user.getAvatar());
        info.put("emailVerified", user.getEmailVerified());
        return info;
    }

    /**
     * 邮箱统一转小写存储与查询。
     * 表上的唯一索引用 utf8mb4_unicode_ci 排序规则,本身已大小写不敏感,
     * 这里再统一一次是为了避免"库里存的是 Foo@x.com"这种不一致的数据。
     */
    private String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase(Locale.ROOT);
    }
}
