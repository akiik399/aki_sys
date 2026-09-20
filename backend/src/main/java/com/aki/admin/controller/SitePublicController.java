package com.aki.admin.controller;

import com.aki.admin.common.Result;
import com.aki.admin.dto.SiteLoginRequest;
import com.aki.admin.dto.SiteRegisterRequest;
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
}
