<template>
  <div class="site">
    <!-- 背景层:纯 CSS 极光渐变 + 细点阵,固定不随内容滚动 -->
    <div class="bg-aurora" aria-hidden="true"></div>

    <header class="site-header">
      <div class="site-header-inner">
        <router-link to="/" class="brand">{{ siteShortName }}</router-link>

        <nav class="nav">
          <router-link
            v-for="item in navItems"
            :key="item.path"
            :to="item.path"
            class="nav-link"
            :class="{ active: isActive(item.path) }"
          >
            {{ item.title }}
          </router-link>
        </nav>

        <div class="header-right">
          <router-link :to="adminEntry" class="admin-link">后台</router-link>

          <!-- 站点访客登录态:未登录显示登录/注册,已登录显示昵称 -->
          <template v-if="siteUser.isLoggedIn">
            <el-dropdown @command="handleCommand">
              <span class="user-chip">
                {{ siteUser.displayName || '我的账号' }}
                <el-icon><ArrowDown /></el-icon>
              </span>
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item command="logout">退出登录</el-dropdown-item>
                </el-dropdown-menu>
              </template>
            </el-dropdown>
          </template>
          <template v-else>
            <router-link to="/signin" class="auth-link">登录</router-link>
            <router-link to="/signup" class="auth-link primary">注册</router-link>
          </template>
        </div>
      </div>
    </header>

    <main class="site-main">
      <router-view />
    </main>

    <footer class="site-footer">
      <div>© {{ year }} {{ author }} · {{ siteName }}</div>
      <div class="footer-sub">Spring Boot 3 · Vue 3 · MySQL · Redis</div>
    </footer>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { ElMessage } from 'element-plus'
import { ArrowDown } from '@element-plus/icons-vue'
import {
  siteName,
  siteShortName,
  author,
  navItems,
  adminEntry
} from '@/config/site'
import { useSiteUserStore } from '@/store/siteUser'

const route = useRoute()
const siteUser = useSiteUserStore()
const year = computed(() => new Date().getFullYear())

/**
 * 站点 token 失效时,siteRequest 的响应拦截器会广播 site-auth-expired。
 * 在这里清掉 Pinia 状态,导航栏就能立刻回到"未登录"外观 ——
 * 拦截器刻意不做跳转(访客可能只是在浏览公开页面,不该被弹走)。
 */
function onAuthExpired() {
  siteUser.clear()
}

onMounted(() => {
  // 刷新页面后靠它把昵称补回来(有没有 token 由 store 内部判断)
  siteUser.fetchMe()
  window.addEventListener('site-auth-expired', onAuthExpired)
})

onUnmounted(() => {
  window.removeEventListener('site-auth-expired', onAuthExpired)
})

async function handleCommand(command) {
  if (command === 'logout') {
    await siteUser.logout()
    ElMessage.success('已退出登录')
  }
}

// 首页只在精确匹配时高亮,其余按前缀匹配(/posts/xxx 也算"文章")
function isActive(path) {
  return path === '/' ? route.path === '/' : route.path.startsWith(path)
}
</script>

<style scoped>
.site {
  position: relative;
  min-height: 100%;
  display: flex;
  flex-direction: column;
  background: #f6f8fc;
  color: #1f2329;
}

/* ---------- 背景层 ---------- */
.bg-aurora {
  position: fixed;
  inset: 0;
  z-index: 0;
  pointer-events: none;
  background:
    radial-gradient(820px 420px at 8% -6%, rgba(43, 108, 255, 0.2), transparent 62%),
    radial-gradient(760px 420px at 96% 2%, rgba(139, 92, 246, 0.18), transparent 64%),
    radial-gradient(680px 460px at 50% 104%, rgba(20, 184, 166, 0.14), transparent 62%),
    linear-gradient(180deg, #f9fbfe 0%, #eef3fb 55%, #e9eef8 100%);
  animation: aurora-drift 26s ease-in-out infinite alternate;
}

/* 细点阵:顶部清楚、往下渐隐,避免整屏噪点 */
.bg-aurora::after {
  content: '';
  position: absolute;
  inset: 0;
  background-image: radial-gradient(rgba(31, 35, 41, 0.055) 1px, transparent 1px);
  background-size: 22px 22px;
  -webkit-mask-image: linear-gradient(180deg, rgba(0, 0, 0, 0.9), transparent 70%);
  mask-image: linear-gradient(180deg, rgba(0, 0, 0, 0.9), transparent 70%);
}

@keyframes aurora-drift {
  from {
    transform: translate3d(0, 0, 0) scale(1);
  }
  to {
    transform: translate3d(0, -16px, 0) scale(1.045);
  }
}

@media (prefers-reduced-motion: reduce) {
  .bg-aurora {
    animation: none;
  }
}

/* ---------- 顶栏 ---------- */
.site-header {
  position: sticky;
  top: 0;
  z-index: 10;
  background: rgba(255, 255, 255, 0.72);
  backdrop-filter: blur(14px) saturate(160%);
  -webkit-backdrop-filter: blur(14px) saturate(160%);
  border-bottom: 1px solid rgba(255, 255, 255, 0.7);
  box-shadow: 0 1px 0 rgba(16, 24, 40, 0.04), 0 8px 24px -20px rgba(16, 24, 40, 0.5);
}

.site-header-inner {
  max-width: 1040px;
  margin: 0 auto;
  padding: 0 20px;
  height: 60px;
  display: flex;
  align-items: center;
  gap: 20px;
}

.brand {
  font-size: 18px;
  font-weight: 700;
  letter-spacing: 0.5px;
  flex-shrink: 0;
  text-decoration: none;
  background: linear-gradient(120deg, #1e3a8a, #2b6cff 55%, #6d5cf6);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.nav {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
  flex: 1;
}

.nav-link {
  position: relative;
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 14px;
  color: #5a6472;
  text-decoration: none;
  transition: color 0.18s, background 0.18s;
}

.nav-link:hover {
  color: #2b6cff;
  background: rgba(43, 108, 255, 0.08);
}

.nav-link.active {
  color: #2b6cff;
  font-weight: 600;
  background: rgba(43, 108, 255, 0.1);
}

.admin-link {
  flex-shrink: 0;
  font-size: 13px;
  color: #5a6472;
  text-decoration: none;
  padding: 5px 14px;
  border-radius: 20px;
  background: rgba(255, 255, 255, 0.7);
  border: 1px solid rgba(43, 108, 255, 0.22);
  transition: all 0.18s;
}

.admin-link:hover {
  color: #fff;
  background: linear-gradient(120deg, #2b6cff, #6d5cf6);
  border-color: transparent;
  box-shadow: 0 8px 18px -8px rgba(43, 108, 255, 0.7);
}

/* ---------- 右侧:后台入口 + 站点访客登录态 ---------- */
.header-right {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}

.user-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 13px;
  color: #1f2329;
  cursor: pointer;
  padding: 5px 12px;
  border-radius: 20px;
  background: rgba(255, 255, 255, 0.72);
  border: 1px solid rgba(43, 108, 255, 0.2);
  transition: all 0.18s;
}

.user-chip:hover {
  border-color: rgba(43, 108, 255, 0.45);
  color: #2b6cff;
}

.auth-link {
  font-size: 13px;
  color: #5a6472;
  text-decoration: none;
  padding: 5px 12px;
  border-radius: 20px;
  transition: all 0.18s;
}

.auth-link:hover {
  color: #2b6cff;
  background: rgba(43, 108, 255, 0.08);
}

.auth-link.primary {
  color: #fff;
  background: linear-gradient(120deg, #2b6cff, #6d5cf6);
  box-shadow: 0 8px 18px -10px rgba(43, 108, 255, 0.8);
}

.auth-link.primary:hover {
  color: #fff;
  transform: translateY(-1px);
}

/* ---------- 内容与页脚 ---------- */
.site-main {
  position: relative;
  z-index: 1;
  flex: 1;
  max-width: 1040px;
  width: 100%;
  margin: 0 auto;
  padding: 28px 20px 48px;
}

.site-footer {
  position: relative;
  z-index: 1;
  border-top: 1px solid rgba(255, 255, 255, 0.8);
  padding: 22px 20px;
  text-align: center;
  font-size: 13px;
  color: #8a94a6;
  background: rgba(255, 255, 255, 0.6);
  backdrop-filter: blur(10px);
}

.footer-sub {
  margin-top: 6px;
  font-size: 12px;
  color: #aab3c0;
}

@media (max-width: 640px) {
  .site-header-inner {
    height: auto;
    padding: 10px 16px;
    flex-wrap: wrap;
    gap: 10px;
  }
  .nav {
    order: 3;
    width: 100%;
    overflow-x: auto;
    flex-wrap: nowrap;
  }
  .nav-link {
    white-space: nowrap;
  }
  .site-main {
    padding: 20px 16px 36px;
  }
}
</style>
