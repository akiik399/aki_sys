package com.aki.admin.config;

import com.aki.admin.security.AuthInterceptor;
import com.aki.admin.security.SiteAuthInterceptor;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web 配置:两条认证域的拦截规则 + 跨域
 *
 * 两条互不相通的认证域:
 * <pre>
 *   /api/**            -> AuthInterceptor     (scope=admin,查 sys_user)
 *   /api/account/**    -> SiteAuthInterceptor (scope=site, 查 site_user)
 * </pre>
 * 站点访客接口统一放在 /api/account/ 前缀下,是为了让"哪条域管哪些接口"
 * 在配置里一眼可见,而不是靠在每个方法里零散地判断。
 */
@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final AuthInterceptor authInterceptor;
    private final SiteAuthInterceptor siteAuthInterceptor;

    public WebConfig(AuthInterceptor authInterceptor, SiteAuthInterceptor siteAuthInterceptor) {
        this.authInterceptor = authInterceptor;
        this.siteAuthInterceptor = siteAuthInterceptor;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        // ---- 后台域 ----
        registry.addInterceptor(authInterceptor)
                .addPathPatterns("/api/**")
                // /api/public/** 是个人主页面向游客的只读接口(以及留言提交、访问埋点),必须放行。
                // /api/account/** 属于站点访客域,**必须**从后台域排除:
                //   若两条规则都命中,后台拦截器会先执行,而它只认 scope=admin,
                //   于是合法的访客 token 会被当成"未登录"直接拒掉。
                .excludePathPatterns("/api/auth/login", "/api/public/**", "/api/account/**", "/error");

        // ---- 站点访客域 ----
        // 只有 /api/account/** 需要访客登录态;登录/注册/发码等无需登录的接口
        // 放在 /api/public/ 下,由上面那条规则统一放行。
        registry.addInterceptor(siteAuthInterceptor)
                .addPathPatterns("/api/account/**");
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/**")
                .allowedOriginPatterns("*")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .allowCredentials(true)
                .maxAge(3600);
    }
}
