package com.aki.admin.common;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.time.Duration;

/**
 * 基于 Redis 固定窗口计数的轻量限流。
 *
 * 用途:注册、登录等公开接口的按来源 IP 限流,防机器人批量注册与密码暴力破解。
 *
 * 已知取舍:
 *   - 固定窗口(而非滑动窗口/令牌桶):实现最简单,代价是窗口边界处可能瞬时放行
 *     接近两倍的量。对个人站点够用,不必为此引入 Lua 脚本或 Sentinel。
 *   - INCR 与 EXPIRE 不是原子的:若进程恰好死在两者之间,该键会永不过期。
 *     概率极低且只影响一个 IP 的计数,故不做 Lua 化处理。
 *   - Redis 不可用时不在这里吞异常:整条认证链路本来都依赖 Redis
 *     (验证码、登录态都存那儿),此时请求必然失败,没有 fail-open 的意义。
 */
@Component
public class RateLimiter {

    private final StringRedisTemplate redis;

    public RateLimiter(StringRedisTemplate redis) {
        this.redis = redis;
    }

    /**
     * 计数并检查。超限抛 BusinessException。
     *
     * @param key    限流键(请带业务前缀,见 RedisKeys)
     * @param limit  窗口内允许的最大次数
     * @param window 窗口长度
     */
    public void check(String key, int limit, Duration window) {
        Long count = redis.opsForValue().increment(key);
        if (count == null) {
            return;
        }
        if (count == 1L) {
            redis.expire(key, window);
        }
        if (count > limit) {
            throw new BusinessException("操作过于频繁,请稍后再试");
        }
    }

    /**
     * 取请求来源 IP。
     *
     * 优先读 X-Forwarded-For / X-Real-IP:生产环境应用只监听 127.0.0.1,
     * 请求全部经 nginx 转发,不读这两个头就只会拿到 127.0.0.1,限流会退化成全局计数。
     *
     * 安全提醒:X-Forwarded-For 是客户端可伪造的头。这里敢信任它,前提是
     * 后端不直接对外暴露(application-prod.yml 里 nginx 反代到 127.0.0.1:8080)。
     * 若哪天把 8080 开到公网,攻击者伪造该头即可绕过限流。
     */
    public String clientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (StringUtils.hasText(forwarded)) {
            // 取第一段:格式为 "客户端IP, 代理1, 代理2"
            return forwarded.split(",")[0].trim();
        }
        String realIp = request.getHeader("X-Real-IP");
        if (StringUtils.hasText(realIp)) {
            return realIp.trim();
        }
        return request.getRemoteAddr();
    }
}
