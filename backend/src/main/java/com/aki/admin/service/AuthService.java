package com.aki.admin.service;

import com.aki.admin.common.BusinessException;
import com.aki.admin.dto.LoginRequest;
import com.aki.admin.entity.SysRole;
import com.aki.admin.entity.SysUser;
import com.aki.admin.mapper.SysRoleMapper;
import com.aki.admin.mapper.SysUserMapper;
import com.aki.admin.security.JwtUtil;
import com.aki.admin.security.RedisKeys;
import com.aki.admin.security.UserContext;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

/**
 * 认证服务:登录/退出/当前用户
 */
@Service
public class AuthService {

    private final SysUserMapper sysUserMapper;
    private final SysRoleMapper sysRoleMapper;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;
    private final StringRedisTemplate redisTemplate;

    @Value("${aki.jwt.expire-seconds}")
    private long expireSeconds;

    public AuthService(SysUserMapper sysUserMapper, SysRoleMapper sysRoleMapper,
                       PasswordEncoder passwordEncoder, JwtUtil jwtUtil,
                       StringRedisTemplate redisTemplate) {
        this.sysUserMapper = sysUserMapper;
        this.sysRoleMapper = sysRoleMapper;
        this.passwordEncoder = passwordEncoder;
        this.jwtUtil = jwtUtil;
        this.redisTemplate = redisTemplate;
    }

    /**
     * 登录:校验密码 -> 签发 JWT -> 写入 Redis
     */
    public Map<String, Object> login(LoginRequest request) {
        SysUser user = sysUserMapper.selectOne(
                new LambdaQueryWrapper<SysUser>().eq(SysUser::getUsername, request.getUsername()));
        if (user == null || !passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new BusinessException("用户名或密码错误");
        }
        if (user.getStatus() == null || user.getStatus() != 1) {
            throw new BusinessException("账号已被禁用,请联系管理员");
        }
        // 显式声明认证域:本方法只处理后台账号,签发 admin 域 token。
        // 站点访客是另一条链路(site_user 表 + SiteAuthInterceptor),两者不可混用。
        String token = jwtUtil.createToken(user.getId(), user.getUsername(), JwtUtil.SCOPE_ADMIN);
        // 登录态写入 Redis(8h),退出/过期即失效
        redisTemplate.opsForValue().set(RedisKeys.loginTokenAdmin(token),
                String.valueOf(user.getId()), Duration.ofSeconds(expireSeconds));

        Map<String, Object> result = new HashMap<>();
        result.put("token", token);
        result.put("user", buildUserInfo(user));
        return result;
    }

    /**
     * 退出登录:删除 Redis 中的 token
     */
    public void logout(String authorization) {
        if (StringUtils.hasText(authorization) && authorization.startsWith("Bearer ")) {
            String token = authorization.substring(7);
            redisTemplate.delete(RedisKeys.loginTokenAdmin(token));
        }
    }

    /**
     * 当前登录用户信息
     */
    public Map<String, Object> me() {
        SysUser user = sysUserMapper.selectById(UserContext.getUserId());
        if (user == null) {
            throw new BusinessException("用户不存在");
        }
        return buildUserInfo(user);
    }

    private Map<String, Object> buildUserInfo(SysUser user) {
        Map<String, Object> info = new HashMap<>();
        info.put("id", user.getId());
        info.put("username", user.getUsername());
        info.put("nickname", user.getNickname());
        info.put("roleId", user.getRoleId());
        info.put("status", user.getStatus());
        SysRole role = user.getRoleId() != null ? sysRoleMapper.selectById(user.getRoleId()) : null;
        info.put("roleName", role != null ? role.getName() : null);
        info.put("roleCode", role != null ? role.getCode() : null);
        return info;
    }
}
