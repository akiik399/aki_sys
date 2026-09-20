package com.aki.admin.controller;

import com.aki.admin.common.Result;
import com.aki.admin.dto.SiteEmailCodeRequest;
import com.aki.admin.dto.SiteLoginRequest;
import com.aki.admin.dto.SiteRegisterRequest;
import com.aki.admin.dto.SiteResetPasswordRequest;
import com.aki.admin.dto.SiteResetVerifyRequest;
import com.aki.admin.service.CaptchaService;
import com.aki.admin.service.SiteAccountService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * 站点访客的公开认证接口(无需登录)。
 *
 * 放在 /api/public/ 前缀下是有意的:WebConfig 里该前缀被统一放行,
 * 因此"哪些接口不需要登录"在配置里一眼可见,不用逐个方法打注解。
 */
@RestController
@RequestMapping("/api/public")
public class SitePublicController {

    private final CaptchaService captchaService;
    private final SiteAccountService siteAccountService;

    public SitePublicController(CaptchaService captchaService, SiteAccountService siteAccountService) {
        this.captchaService = captchaService;
        this.siteAccountService = siteAccountService;
    }

    /** 生成图形验证码,返回 { captchaId, image(data URL) } */
    @GetMapping("/captcha")
    public Result<Map<String, String>> captcha() {
        return Result.ok(captchaService.create());
    }

    /** 注册(需图形验证码),成功即登录 */
    @PostMapping("/register")
    public Result<Map<String, Object>> register(@Valid @RequestBody SiteRegisterRequest request,
                                                HttpServletRequest httpRequest) {
        return Result.ok("注册成功", siteAccountService.register(request, httpRequest));
    }

    /** 登录(邮箱 + 密码) */
    @PostMapping("/login")
    public Result<Map<String, Object>> login(@Valid @RequestBody SiteLoginRequest request,
                                             HttpServletRequest httpRequest) {
        return Result.ok("登录成功", siteAccountService.login(request, httpRequest));
    }

    // ---------------- 找回密码(三步) ----------------

    /**
     * 第一步:发送验证码。
     * 无论邮箱是否注册,返回的话术都一样 —— 否则这个接口会变成账号枚举工具。
     */
    @PostMapping("/reset/code")
    public Result<Void> sendResetCode(@Valid @RequestBody SiteEmailCodeRequest request,
                                      HttpServletRequest httpRequest) {
        siteAccountService.sendResetCode(request, httpRequest);
        return Result.ok("如果该邮箱已注册,验证码已发送,请查收邮箱", null);
    }

    /** 第二步:校验验证码,换发一次性重置令牌 */
    @PostMapping("/reset/verify")
    public Result<Map<String, Object>> verifyResetCode(@Valid @RequestBody SiteResetVerifyRequest request) {
        return Result.ok(siteAccountService.verifyResetCode(request));
    }

    /** 第三步:用令牌设置新密码(成功后该账号所有旧会话立即失效) */
    @PostMapping("/reset/confirm")
    public Result<Void> resetPassword(@Valid @RequestBody SiteResetPasswordRequest request) {
        siteAccountService.resetPassword(request);
        return Result.ok("密码已重置,请用新密码登录", null);
    }
}
