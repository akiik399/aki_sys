package com.aki.admin.security;

/**
 * Redis 键常量
 */
public final class RedisKeys {

    private RedisKeys() {
    }

    /** 登录 token -> 用户ID,登录态存储于 Redis,退出登录/过期即失效 */
    public static final String LOGIN_TOKEN = "aki:login:token:";

    public static String loginToken(String token) {
        return LOGIN_TOKEN + token;
    }
}
