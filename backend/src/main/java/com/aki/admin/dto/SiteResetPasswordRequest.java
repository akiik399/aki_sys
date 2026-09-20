package com.aki.admin.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 重置密码请求(找回密码第三步:用一次性令牌设置新密码)
 *
 * 拆成两步(验码换令牌 -> 用令牌改密)的原因:
 * 改密码这一步不必再传一次验证码,避免"用户在这一步慢慢想新密码、
 * 结果验证码过期"的尴尬;而 resetToken 一次性、10 分钟,泄露窗口比验证码更短。
 */
public class SiteResetPasswordRequest {

    @NotBlank(message = "重置令牌不能为空")
    private String resetToken;

    @NotBlank(message = "新密码不能为空")
    @Size(min = 8, max = 64, message = "密码长度需在 8-64 位之间")
    @Pattern(regexp = "^(?=.*[A-Za-z])(?=.*\\d).+$", message = "密码需同时包含字母和数字")
    private String newPassword;

    public String getResetToken() {
        return resetToken;
    }

    public void setResetToken(String resetToken) {
        this.resetToken = resetToken;
    }

    public String getNewPassword() {
        return newPassword;
    }

    public void setNewPassword(String newPassword) {
        this.newPassword = newPassword;
    }
}
