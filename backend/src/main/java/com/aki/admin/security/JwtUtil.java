package com.aki.admin.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;

/**
 * JWT 工具
 *
 * 重点:所有 token 都必须带 scope,用来区分**两条互不相通的认证域**:
 * <pre>
 *   admin -> 管理后台(sys_user 表)
 *   site  -> 公开站点的访客(site_user 表)
 * </pre>
 *
 * 为什么必须有:两张表的 id 各自从 1 开始。若 token 不带 scope,
 * 一个访客的 token 里 sub=1 会被后台拦截器当成 sys_user 的 1 号(即 admin),
 * 直接拿到管理员权限。scope 是这条越权路径上的第一道闸。
 *
 * 因此这里**故意不提供"不带 scope"的重载**:让调用方每次都明确写出自己属于哪个域,
 * 避免以后有人顺手调了默认版本、无意间签发出带 admin 权限的 token。
 */
@Component
public class JwtUtil {

    /** 管理后台 */
    public static final String SCOPE_ADMIN = "admin";

    /** 公开站点访客 */
    public static final String SCOPE_SITE = "site";

    private static final String CLAIM_SCOPE = "scope";
    private static final String CLAIM_USERNAME = "username";

    @Value("${aki.jwt.secret}")
    private String secret;

    @Value("${aki.jwt.expire-seconds}")
    private long expireSeconds;

    private SecretKey key() {
        return Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 生成 token。scope 必须显式传入(见类注释),取值 {@link #SCOPE_ADMIN} 或 {@link #SCOPE_SITE}。
     */
    public String createToken(Long userId, String username, String scope) {
        Date now = new Date();
        Date expiry = new Date(now.getTime() + expireSeconds * 1000);
        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim(CLAIM_USERNAME, username)
                .claim(CLAIM_SCOPE, scope)
                .issuedAt(now)
                .expiration(expiry)
                .signWith(key())
                .compact();
    }

    /**
     * 解析 token,失败抛出 JwtException
     */
    public Claims parse(String token) {
        return Jwts.parser()
                .verifyWith(key())
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    public Long getUserId(Claims claims) {
        return Long.valueOf(claims.getSubject());
    }

    public String getUsername(Claims claims) {
        return claims.get(CLAIM_USERNAME, String.class);
    }

    /**
     * 取 token 的认证域。
     * 注意:本次改造之前签发的旧 token 没有这个 claim,这里会返回 null,
     * 两个拦截器都会拒绝 —— 表现为"升级后需要重新登录一次",属预期行为。
     */
    public String getScope(Claims claims) {
        return claims.get(CLAIM_SCOPE, String.class);
    }
}
