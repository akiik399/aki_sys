package com.aki.admin.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * 站点访客登录请求(2a 阶段:邮箱 + 密码)
 */
public class SiteLoginRequest {

    @NotBlank(message = "邮箱不能为空")
    private String email;

    @NotBlank(message = "密码不能为空")
    private String password;

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
}
