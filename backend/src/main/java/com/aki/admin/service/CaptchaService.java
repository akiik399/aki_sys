package com.aki.admin.service;

import com.aki.admin.common.BusinessException;
import com.aki.admin.security.RedisKeys;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import javax.imageio.ImageIO;
import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.Duration;
import java.util.Base64;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

/**
 * 图形验证码:用 Java2D 直接画 PNG,不引第三方依赖(kaptcha 之类没必要)。
 *
 * 作用:公开注册接口一旦上线必然被机器人盯上,它是第一道闸。
 *
 * 部署注意:Java2D 在无头环境下需要系统里存在**至少一种字体**。精简的
 * Linux 镜像(以及某些 Docker 基础镜像)可能没装,表现为生成验证码时抛
 * 「Fontconfig head is null」之类的异常。部署时确保装了 fontconfig +
 * 一套基础字体(如 fonts-dejavu-core)即可。这里用的是逻辑字体 SANS_SERIF,
 * 不绑定具体字体文件。
 */
@Service
public class CaptchaService {

    /** 去掉易混淆字符:I O 0 1 2 Z —— 用户看不清会导致无谓的失败重试 */
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXY3456789";

    private static final int CODE_LENGTH = 4;
    private static final int WIDTH = 120;
    private static final int HEIGHT = 40;

    /** 有效期:足够填完表单,又不至于让攻击者有大把时间撞码 */
    private static final Duration TTL = Duration.ofMinutes(2);

    private final StringRedisTemplate redis;

    public CaptchaService(StringRedisTemplate redis) {
        this.redis = redis;
    }

    /**
     * 生成一张新验证码。
     *
     * @return captchaId 与可直接塞进 img src 的 data URL
     */
    public Map<String, String> create() {
        ThreadLocalRandom random = ThreadLocalRandom.current();
        StringBuilder sb = new StringBuilder(CODE_LENGTH);
        for (int i = 0; i < CODE_LENGTH; i++) {
            sb.append(ALPHABET.charAt(random.nextInt(ALPHABET.length())));
        }
        String code = sb.toString();
        String captchaId = UUID.randomUUID().toString().replace("-", "");

        // 答案统一小写存储,校验时也小写化 —— 否则用户大小写不一致会被误判为错
        redis.opsForValue().set(RedisKeys.captcha(captchaId), code.toLowerCase(Locale.ROOT), TTL);

        Map<String, String> result = new HashMap<>();
        result.put("captchaId", captchaId);
        result.put("image", "data:image/png;base64," + Base64.getEncoder().encodeToString(render(code)));
        return result;
    }

    /**
     * 校验并消费验证码。
     *
     * 无论校验成功还是失败都立即删除:验证码是**一次性**凭证。
     * 若失败时保留,攻击者就能拿同一个 captchaId 在 2 分钟内无限次撞码
     * (4 位 × 31 字符 = 92 万种组合,足够被撞开)。
     * 代价是用户输错后必须点图刷新,这个体验损失是值得的。
     */
    public void verify(String captchaId, String input) {
        if (captchaId == null || captchaId.isBlank() || input == null || input.isBlank()) {
            throw new BusinessException("请先获取图形验证码");
        }
        String key = RedisKeys.captcha(captchaId);
        String expected = redis.opsForValue().get(key);
        redis.delete(key);
        if (expected == null) {
            throw new BusinessException("验证码已过期,请点击图片刷新后重试");
        }
        if (!expected.equals(input.trim().toLowerCase(Locale.ROOT))) {
            throw new BusinessException("验证码错误");
        }
    }

    private byte[] render(String code) {
        BufferedImage image = new BufferedImage(WIDTH, HEIGHT, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = image.createGraphics();
        try {
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            ThreadLocalRandom random = ThreadLocalRandom.current();

            g.setColor(new Color(0xF4, 0xF7, 0xFC));
            g.fillRect(0, 0, WIDTH, HEIGHT);

            // 干扰线:让简单的二值化切分失效
            for (int i = 0; i < 6; i++) {
                g.setColor(new Color(random.nextInt(120) + 100, random.nextInt(120) + 100, random.nextInt(120) + 100));
                g.drawLine(random.nextInt(WIDTH), random.nextInt(HEIGHT), random.nextInt(WIDTH), random.nextInt(HEIGHT));
            }

            // 逐字绘制,每个字单独随机旋转与偏移,进一步增加 OCR 难度
            int step = WIDTH / (CODE_LENGTH + 1);
            for (int i = 0; i < code.length(); i++) {
                g.setFont(new Font(Font.SANS_SERIF, Font.BOLD, 24 + random.nextInt(5)));
                g.setColor(new Color(random.nextInt(80), random.nextInt(80), random.nextInt(100) + 60));
                int x = step * (i + 1) - 10;
                int y = HEIGHT - 12 + random.nextInt(6);
                double angle = (random.nextDouble() - 0.5) * 0.6;
                g.rotate(angle, x, y);
                g.drawString(String.valueOf(code.charAt(i)), x, y);
                g.rotate(-angle, x, y);
            }

            // 噪点
            for (int i = 0; i < 40; i++) {
                g.setColor(new Color(random.nextInt(200) + 55, random.nextInt(200) + 55, random.nextInt(200) + 55));
                g.fillRect(random.nextInt(WIDTH), random.nextInt(HEIGHT), 1, 1);
            }
        } finally {
            g.dispose();
        }

        try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            ImageIO.write(image, "png", out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new BusinessException("验证码生成失败,请稍后重试");
        }
    }
}
