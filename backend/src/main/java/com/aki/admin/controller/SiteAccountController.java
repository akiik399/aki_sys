package com.aki.admin.controller;

import com.aki.admin.common.Result;
import com.aki.admin.service.SiteAccountService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * 站点访客的账号接口(需要 scope=site 的登录态)。
 *
 * 全部挂在 /api/account/ 下:WebConfig 里这个前缀由 SiteAuthInterceptor 守卫,
 * 并且已从后台拦截器的范围中排除 —— 两条认证域各管各的,不会互相误拦。
 */
@RestController
@RequestMapping("/api/account")
public class SiteAccountController {

    private final SiteAccountService siteAccountService;

    public SiteAccountController(SiteAccountService siteAccountService) {
        this.siteAccountService = siteAccountService;
    }

    @PostMapping("/logout")
    public Result<Void> logout(@RequestHeader(value = "Authorization", required = false) String authorization) {
        siteAccountService.logout(authorization);
        return Result.ok();
    }

    @GetMapping("/me")
    public Result<Map<String, Object>> me() {
        return Result.ok(siteAccountService.me());
    }
}
