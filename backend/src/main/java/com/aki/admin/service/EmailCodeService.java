package com.aki.admin.service;

import com.aki.admin.common.BusinessException;
import com.aki.admin.common.RateLimiter;
import com.aki.admin.security.RedisKeys;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.LocalDate;
import java.util.concurrent.ThreadLocalRandom;

/**
 * 邮箱验证码:发送与校验。
 *
 * 它保护的接口(发码)是**全站最危险的接口**:攻击者能让你的域名给任意第三方邮箱
 * 发骚扰信、把你的 SMTP 额度打满、甚至让你的发信域名进黑名单。
 * 所以四道闸一个都不能少:图形验证码 -> IP 限流 -> 邮箱+场景冷却 -> 每日配额。
 *
 * 分成 {@link #guard} 与 {@link #dispatch} 两步是有意的:
 * 前者与"邮箱是否存在"无关,必须先执行(否则未注册邮箱会绕过所有限流,
 * 顺便把发码接口变成账号枚举工具);后者只在邮箱确实存在时才做。
 */
@Service
public class EmailCodeService {

    /** 找回密码场景。将来加"验证码登录"时,只需再定义一个 scene 常量 */
    public static final String SCENE_RESET = "reset";

    private static final Duration CODE_TTL = Duration.ofMinutes(5);
    private static final Duration COOLDOWN = Duration.ofSeconds(60);
    private static final int MAX_VERIFY_ATTEMPTS = 5;
    private static final int DAILY_QUOTA_PER_EMAIL = 10;
    private static final int SEND_LIMIT_PER_MINUTE_PER_IP = 5;

    private static final SecureRandom RANDOM = new SecureRandom();

    private final StringRedisTemplate redis;
    private final MailService mailService;
    private final CaptchaService captchaService;
    private final RateLimiter rateLimiter;

    public EmailCodeService(StringRedisTemplate redis, MailService mailService,
                            CaptchaService captchaService, RateLimiter rateLimiter) {
        this.redis = redis;
        this.mailService = mailService;
        this.captchaService = captchaService;
        this.rateLimiter = rateLimiter;
    }

    /**
     * 发送前的前置校验,与邮箱是否存在无关。
     * 顺序:图形验证码 -> IP 限流 -> 冷却 -> 每日配额。
     */
    public void guard(String scene, String email, String captchaId, String captchaCode,
                      HttpServletRequest request) {
        // 1) 图形验证码:连验证码都不解,说明是脚本
        captchaService.verify(captchaId, captchaCode);

        // 2) 按来源 IP 限流:防用我们的服务轰炸第三方邮箱
        rateLimiter.check(RedisKeys.rateSendCodeIp(rateLimiter.clientIp(request)),
                SEND_LIMIT_PER_MINUTE_PER_IP, Duration.ofMinutes(1));

        // 3) 同一邮箱同一场景的冷却:防用户连点导致的重复发信
        String cooldownKey = RedisKeys.emailCodeCooldown(scene, email);
        if (Boolean.TRUE.equals(redis.hasKey(cooldownKey))) {
            throw new BusinessException("验证码已发送,请 60 秒后再试");
        }

        // 4) 每日配额:即使换了 IP 也不能无限制给同一个邮箱发
        String quotaKey = RedisKeys.emailCodeQuota(email, LocalDate.now().toString());
        Long used = redis.opsForValue().increment(quotaKey);
        if (used != null && used == 1L) {
            redis.expire(quotaKey, Duration.ofDays(1));
        }
        if (used != null && used > DAILY_QUOTA_PER_EMAIL) {
            throw new BusinessException("该邮箱今日验证码发送次数已达上限,请明天再试");
        }
    }

    /**
     * 生成验证码并发送。调用方必须确认邮箱确实存在后再调它。
     */
    public void dispatch(String scene, String email) {
        String code = String.format("%06d", RANDOM.nextInt(1_000_000));
        redis.opsForValue().set(RedisKeys.emailCode(scene, email), code, CODE_TTL);
        // 换了新码,旧的尝试次数清零
        redis.delete(RedisKeys.emailCodeTry(scene, email));
        // 冷却键:放在真正发送之前,避免发送失败时用户狂点
        redis.opsForValue().set(RedisKeys.emailCodeCooldown(scene, email), "1", COOLDOWN);

        boolean sent = mailService.send(email, subjectOf(scene), bodyOf(scene, code));
        if (!sent) {
            throw new BusinessException("验证码发送失败,请稍后重试");
        }
    }

    /**
     * 校验并消费验证码。
     *
     * 与图形验证码不同,这里**失败时不立即作废**:邮箱验证码有尝试次数上限
     * (5 次),用户可以放心重输,体验更好;超过上限才作废并强制重新获取。
     */
    public void verify(String scene, String email, String input) {
        if (input == null || input.isBlank()) {
            throw new BusinessException("请输入验证码");
        }
        String codeKey = RedisKeys.emailCode(scene, email);
        String tryKey = RedisKeys.emailCodeTry(scene, email);

        Long tries = redis.opsForValue().increment(tryKey);
        if (tries != null && tries == 1L) {
            redis.expire(tryKey, CODE_TTL);
        }
        if (tries != null && tries > MAX_VERIFY_ATTEMPTS) {
            redis.delete(codeKey);
            throw new BusinessException("验证码错误次数过多,请重新获取");
        }

        String expected = redis.opsForValue().get(codeKey);
        if (expected == null) {
            throw new BusinessException("验证码已过期,请重新获取");
        }
        if (!expected.equals(input.trim())) {
            throw new BusinessException("验证码错误");
        }
        // 成功即一次性消费
        redis.delete(codeKey);
        redis.delete(tryKey);
    }

    private String subjectOf(String scene) {
        if (SCENE_RESET.equals(scene)) {
            return "【个人主页】重置密码验证码";
        }
        return "【个人主页】验证码";
    }

    private String bodyOf(String scene, String code) {
        String action = SCENE_RESET.equals(scene) ? "重置密码" : "登录";
        return "你正在" + action + ",验证码是:" + code + "\n\n"
                + "验证码 5 分钟内有效,请勿转发给他人。\n"
                + "如果这不是你本人的操作,忽略本邮件即可。";
    }
}
