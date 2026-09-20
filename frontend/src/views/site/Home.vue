<template>
  <div class="home">
    <!-- Hero:阶段 1 接入 /api/public/profile 后,这里的占位文案改为接口数据 -->
    <section class="hero">
      <div class="avatar">{{ avatarText }}</div>
      <div class="hero-text">
        <h1 class="hero-name">{{ profile.nickname }}</h1>
        <p class="hero-slogan">{{ profile.slogan }}</p>
        <p class="hero-location">{{ profile.location }}</p>

        <div class="socials">
          <a
            v-for="item in profile.socials"
            :key="item.name"
            class="social-btn"
            :href="item.url"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ item.name }}
          </a>
          <a class="social-btn" :href="`mailto:${profile.email}`">邮箱</a>
        </div>

        <!-- 注册入口放一份在首屏:只放在导航栏右上角时太容易被忽略 -->
        <div v-if="!siteUser.isLoggedIn" class="hero-cta">
          <router-link
            :to="{ path: '/signin', query: { mode: 'register' } }"
            class="cta-btn primary"
          >
            注册账号
          </router-link>
          <router-link to="/signin" class="cta-btn">已有账号,去登录</router-link>
        </div>
        <div v-else class="hero-cta">
          <span class="cta-welcome">你好,{{ siteUser.displayName }}</span>
        </div>
      </div>
    </section>

    <!-- 各板块入口:对应 SiteLayout 导航,阶段 1-3 逐个填真实内容 -->
    <section class="sections">
      <router-link
        v-for="item in sections"
        :key="item.path"
        :to="item.path"
        class="section-card"
      >
        <div class="section-title">{{ item.title }}</div>
        <div class="section-desc">{{ item.desc }}</div>
      </router-link>
    </section>

    <el-alert
      class="stage-alert"
      type="info"
      :closable="false"
      show-icon
      title="阶段 0 骨架已就绪"
      description="公开区路由已放行(游客可直接访问),管理后台仍走 JWT + Redis 登录态。下一步(阶段 1)接入 site_profile / site_project / site_skill 三张表的数据与后台增删改。"
    />
  </div>
</template>

<script setup>
import { useSiteUserStore } from '@/store/siteUser'

// 用于首屏的注册/登录入口:已登录时改成显示昵称
const siteUser = useSiteUserStore()

// 阶段 0:先用占位数据把页面结构立起来。
// 阶段 1 会改成 onMounted 里调 GET /api/public/profile,读不到时回落到这份默认值。
const profile = {
  nickname: '你的昵称',
  slogan: '一句话介绍你自己',
  location: '中国 · 某城市',
  email: 'you@example.com',
  socials: [
    { name: 'GitHub', url: 'https://github.com/your-name' },
    { name: '掘金', url: 'https://juejin.cn/user/your-id' }
  ]
}

const avatarText = profile.nickname.slice(0, 1)

const sections = [
  { path: '/projects', title: '项目作品', desc: '做过什么,以及为什么这么做' },
  { path: '/posts', title: '技术文章', desc: '踩过的坑与沉淀下来的笔记' },
  { path: '/timeline', title: '经历时间线', desc: '学习和工作的时间轴' },
  { path: '/message', title: '留言板', desc: '有话想说就留一句' }
]
</script>

<style scoped>
/* ---------- Hero ---------- */
.hero {
  position: relative;
  overflow: hidden;
  display: flex;
  align-items: center;
  gap: 24px;
  padding: 34px 32px;
  border-radius: 20px;
  color: #fff;
  background: linear-gradient(135deg, #1b2f6b 0%, #2b5f9e 46%, #4f46e5 100%);
  box-shadow:
    0 24px 48px -24px rgba(30, 58, 138, 0.75),
    inset 0 1px 0 rgba(255, 255, 255, 0.22);
}

/* 两层光晕:右上高光 + 左下青色反光,让纯渐变不再平板 */
.hero::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    radial-gradient(560px 240px at 88% -12%, rgba(255, 255, 255, 0.3), transparent 62%),
    radial-gradient(420px 220px at 4% 118%, rgba(56, 189, 248, 0.38), transparent 62%);
}

.hero > * {
  position: relative;
  z-index: 1;
}

.avatar {
  width: 92px;
  height: 92px;
  flex-shrink: 0;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 34px;
  font-weight: 700;
  color: #fff;
  background: linear-gradient(140deg, rgba(255, 255, 255, 0.32), rgba(255, 255, 255, 0.12));
  border: 2px solid rgba(255, 255, 255, 0.55);
  box-shadow:
    0 0 0 6px rgba(255, 255, 255, 0.1),
    0 14px 28px -14px rgba(2, 10, 30, 0.8);
}

.hero-name {
  margin: 0;
  font-size: 28px;
  font-weight: 700;
  letter-spacing: 0.5px;
  text-shadow: 0 2px 12px rgba(2, 10, 30, 0.3);
}

.hero-slogan {
  margin: 10px 0 4px;
  font-size: 15px;
  opacity: 0.94;
}

.hero-location {
  margin: 0;
  font-size: 13px;
  opacity: 0.72;
}

.socials {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 18px;
}

.social-btn {
  font-size: 13px;
  color: #fff;
  text-decoration: none;
  padding: 6px 15px;
  border-radius: 20px;
  background: rgba(255, 255, 255, 0.16);
  border: 1px solid rgba(255, 255, 255, 0.32);
  backdrop-filter: blur(6px);
  transition: all 0.18s;
}

.social-btn:hover {
  background: rgba(255, 255, 255, 0.3);
  transform: translateY(-1px);
}

/* ---------- 首屏的注册 / 登录入口 ---------- */
.hero-cta {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 16px;
}

.cta-btn {
  font-size: 14px;
  padding: 8px 20px;
  border-radius: 22px;
  text-decoration: none;
  color: #fff;
  background: rgba(255, 255, 255, 0.18);
  border: 1px solid rgba(255, 255, 255, 0.4);
  backdrop-filter: blur(6px);
  transition: all 0.18s;
}

.cta-btn:hover {
  background: rgba(255, 255, 255, 0.3);
  transform: translateY(-1px);
}

/* 主按钮反白,和背景的深蓝渐变拉开对比 —— 入口要一眼能找到 */
.cta-btn.primary {
  background: #fff;
  color: #1b2f6b;
  font-weight: 600;
  border-color: #fff;
  box-shadow: 0 10px 24px -12px rgba(2, 10, 30, 0.9);
}

.cta-btn.primary:hover {
  background: #f2f6ff;
}

.cta-welcome {
  font-size: 14px;
  color: rgba(255, 255, 255, 0.9);
  padding: 8px 0;
}

/* ---------- 板块卡片(玻璃拟态) ---------- */
.sections {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 14px;
  margin: 22px 0;
}

.section-card {
  display: block;
  padding: 18px;
  border-radius: 14px;
  text-decoration: none;
  color: inherit;
  background: rgba(255, 255, 255, 0.72);
  backdrop-filter: blur(12px) saturate(150%);
  -webkit-backdrop-filter: blur(12px) saturate(150%);
  border: 1px solid rgba(255, 255, 255, 0.9);
  box-shadow:
    0 1px 2px rgba(16, 24, 40, 0.04),
    0 14px 30px -20px rgba(16, 24, 40, 0.45);
  transition: transform 0.18s, box-shadow 0.18s, border-color 0.18s;
}

.section-card:hover {
  transform: translateY(-3px);
  border-color: rgba(43, 108, 255, 0.35);
  box-shadow:
    0 2px 4px rgba(16, 24, 40, 0.05),
    0 20px 38px -20px rgba(43, 108, 255, 0.5);
}

.section-title {
  font-size: 15px;
  font-weight: 600;
  margin-bottom: 6px;
}

.section-desc {
  font-size: 13px;
  color: #8a94a6;
  line-height: 1.55;
}

/* 提示条也做半透明,避免在渐变背景上过于生硬 */
.stage-alert {
  border-radius: 12px;
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
}

@media (max-width: 640px) {
  .hero {
    flex-direction: column;
    text-align: center;
    padding: 26px 20px;
  }
  .socials {
    justify-content: center;
  }
}
</style>
