package com.aki.admin.security;

import com.aki.admin.common.Result;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Claims;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import java.nio.charset.StandardCharsets;

/**
 * 站点访客登录态校验拦截器,只作用于 {@code /api/account/**}。
 *
 * 与管理后台的 {@link AuthInterceptor} 是**两条独立的认证域**:
 * 本拦截器只接受 scope=site 的 token、只查 aki:login:site: 前缀的登录态、
 * 只往 {@link SiteUserContext} 里放身份。站点接口永远不会去查 sys_user 表。
 *
 * 反向同理:{@link AuthInterceptor} 只接受 scope=admin。
 * 任何一侧被绕过,另一侧仍然安全。
 */
@Component
public class SiteAuthInterceptor implements HandlerInterceptor {

    private final JwtUtil jwtUtil;
    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper = new ObjectMapper();

    public SiteAuthInterceptor(JwtUtil jwtUtil, StringRedisTemplate redisTemplate) {
        this.jwtUtil = jwtUtil;
        this.redisTemplate = redisTemplate;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        if (HttpMethod.OPTIONS.matches(request.getMethod())) {
            return true;
        }
        String auth = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (auth == null || !auth.startsWith("Bearer ")) {
            return reject(response, "未登录或 token 缺失");
        }
        String token = auth.substring(7);
        try {
            Claims claims = jwtUtil.parse(token);
            // 只接受站点域:拿后台 token 来调站点接口同样会被拒(而不是当成访客放行)
            if (!JwtUtil.SCOPE_SITE.equals(jwtUtil.getScope(claims))) {
                return reject(response, "token 类型不匹配");
            }
            Long siteUserId = jwtUtil.getUserId(claims);
            String cached = redisTemplate.opsForValue().get(RedisKeys.loginTokenSite(token));
            if (cached == null) {
                return reject(response, "登录已失效,请重新登录");
            }
            SiteUserContext.set(siteUserId, jwtUtil.getUsername(claims));
            return true;
        } catch (Exception e) {
            return reject(response, "token 无效或已过期");
        }
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        // ThreadLocal 必须清理:线程池里的线程会被复用,
        // 不清理会让下一个请求读到上一个请求的身份。
        SiteUserContext.clear();
    }

    private boolean reject(HttpServletResponse response, String msg) throws Exception {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json;charset=UTF-8");
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.getWriter().write(objectMapper.writeValueAsString(Result.error(Result.CODE_UNAUTHORIZED, msg)));
        return false;
    }
}
