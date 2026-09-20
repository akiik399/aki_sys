package com.aki.admin.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.annotation.JsonIgnore;

import java.time.LocalDateTime;

/**
 * 站点访客账号
 *
 * 与 {@link SysUser} 是两张表、两条互不相通的认证域:
 * 后台账号在 sys_user,访客在 site_user,各自的登录态和拦截器都是独立的
 * (见 docs/用户注册与验证码登录方案.md 第一节)。
 *
 * 注意本类**刻意没有 roleId 字段**:访客不需要任何角色,没有字段就不可能出现
 * "给访客配了后台角色"这种误操作。后台权限一律只认 sys_user。
 */
@TableName("site_user")
public class SiteUser {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 邮箱,同时作为登录名(统一小写存储) */
    private String email;

    /** 密码(BCrypt),序列化时隐藏。纯验证码注册的用户可能为 null */
    @JsonIgnore
    private String password;

    /** 昵称,对外展示 */
    private String nickname;

    private String avatar;

    /** 1 正常 0 禁用 */
    private Integer status;

    /** 邮箱是否已验证 1 是 0 否(2a 阶段不强制验证,2b 接邮件后置 1) */
    private Integer emailVerified;

    private LocalDateTime lastLoginAt;

    private Integer loginCount;

    private LocalDateTime createdAt;

    private LocalDateTime updatedAt;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getNickname() {
        return nickname;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
    }

    public String getAvatar() {
        return avatar;
    }

    public void setAvatar(String avatar) {
        this.avatar = avatar;
    }

    public Integer getStatus() {
        return status;
    }

    public void setStatus(Integer status) {
        this.status = status;
    }

    public Integer getEmailVerified() {
        return emailVerified;
    }

    public void setEmailVerified(Integer emailVerified) {
        this.emailVerified = emailVerified;
    }

    public LocalDateTime getLastLoginAt() {
        return lastLoginAt;
    }

    public void setLastLoginAt(LocalDateTime lastLoginAt) {
        this.lastLoginAt = lastLoginAt;
    }

    public Integer getLoginCount() {
        return loginCount;
    }

    public void setLoginCount(Integer loginCount) {
        this.loginCount = loginCount;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(LocalDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
