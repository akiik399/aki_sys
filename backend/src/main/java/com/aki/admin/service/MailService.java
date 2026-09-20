package com.aki.admin.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

import java.util.Arrays;

/**
 * 邮件发送。
 *
 * 两种模式,由 {@code aki.mail.mode} 决定:
 * <pre>
 *   smtp -> 走真实 SMTP(spring-boot-starter-mail)。生产唯一允许的模式。
 *   log  -> 把邮件内容打到应用日志里,不发出去。**仅供本地开发**
 * </pre>
 *
 * 为什么要有 log 模式:本地开发没有 Mailpit/Docker 时,总不能为了看一眼验证码
 * 就去申请真邮箱授权码。但它有两个必须靠工程手段挡住的风险,所以:
 * <ol>
 *   <li>application-prod.yml 里 mode 直接写死 smtp(不给环境变量覆盖的机会),
 *       生产环境无法进入 log 模式;</li>
 *   <li>构造时再校验一次:若当前激活了 prod profile 且模式是 log,直接启动失败。
 *       防止有人把 dev 的配置整体搬到生产还浑然不觉。</li>
 * </ol>
 *
 * 即使如此,log 模式本身仍是"把凭证写进日志"的行为 —— 只在本机开发用,
 * 日志一旦外传就等于验证码公开。
 */
@Service
public class MailService {

    private static final Logger log = LoggerFactory.getLogger(MailService.class);

    private static final String MODE_SMTP = "smtp";
    private static final String MODE_LOG = "log";

    private final ObjectProvider<JavaMailSender> mailSenderProvider;
    private final String mode;
    private final String from;

    public MailService(ObjectProvider<JavaMailSender> mailSenderProvider,
                       @Value("${aki.mail.mode:log}") String mode,
                       @Value("${aki.mail.from:no-reply@localhost}") String from,
                       Environment environment) {
        this.mailSenderProvider = mailSenderProvider;
        this.mode = mode;
        this.from = from;

        // 兜底防线:生产 profile 下绝不允许 log 模式
        boolean prodActive = Arrays.asList(environment.getActiveProfiles()).contains("prod");
        if (prodActive && MODE_LOG.equalsIgnoreCase(mode)) {
            throw new IllegalStateException(
                    "禁止在生产环境使用 aki.mail.mode=log(它会把验证码写进日志)。请配置 SMTP。");
        }
    }

    /**
     * 发送一封纯文本邮件。发送失败只记日志、不抛异常 ——
     * 调用方(发验证码接口)不该因为邮件服务抖动就返回 500,
     * 否则会暴露"这个邮箱到底存不存在"这类信息,也会让用户体验莫名失败。
     *
     * @return 是否发送成功
     */
    public boolean send(String to, String subject, String text) {
        if (MODE_LOG.equalsIgnoreCase(mode)) {
            log.warn("[开发模式-邮件未真实发送] 收件人={} 主题={}\n{}", to, subject, text);
            return true;
        }
        JavaMailSender sender = mailSenderProvider.getIfAvailable();
        if (sender == null) {
            log.error("aki.mail.mode=smtp 但未配置 spring.mail.host,邮件无法发送(收件人={})", to);
            return false;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(from);
            message.setTo(to);
            message.setSubject(subject);
            message.setText(text);
            sender.send(message);
            return true;
        } catch (Exception e) {
            // 只记收件人,不记正文(正文里有验证码)
            log.error("邮件发送失败,收件人={}", to, e);
            return false;
        }
    }
}
