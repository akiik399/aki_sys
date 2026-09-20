import { createRouter, createWebHistory } from 'vue-router'
import { siteName } from '@/config/site'
import ComingSoon from '@/views/site/ComingSoon.vue'

/**
 * 路由分两个区:
 *   公开区  → SiteLayout,游客直接访问,不需要登录
 *   管理区  → /admin/**,meta.requiresAuth 标记,强制登录(沿用 JWT + Redis 登录态)
 *
 * 守卫采用**白名单**:只有显式标了 requiresAuth 的路由才拦登录,
 * 其余一律放行。这样以后新增公开页面不需要动守卫,
 * 也不会再出现"游客一进首页就被踢去登录页"的问题。
 */
const routes = [
  // ---------------- 公开区 ----------------
  {
    path: '/',
    component: () => import('@/layout/SiteLayout.vue'),
    children: [
      {
        path: '',
        name: 'Home',
        component: () => import('@/views/site/Home.vue'),
        meta: { title: '首页' }
      },
      // 阶段 1-3 会用真实页面替换下面这几条占位路由
      {
        path: 'projects',
        name: 'Projects',
        component: ComingSoon,
        meta: { title: '项目', desc: '项目作品列表与详情,阶段 1 上线。' },
        props: (route) => ({ title: route.meta.title, description: route.meta.desc })
      },
      {
        path: 'posts',
        name: 'Posts',
        component: ComingSoon,
        meta: { title: '文章', desc: '技术文章列表与详情,阶段 2 上线。' },
        props: (route) => ({ title: route.meta.title, description: route.meta.desc })
      },
      {
        path: 'timeline',
        name: 'Timeline',
        component: ComingSoon,
        meta: { title: '时间线', desc: '学习与工作经历时间轴,阶段 3 上线。' },
        props: (route) => ({ title: route.meta.title, description: route.meta.desc })
      },
      {
        path: 'message',
        name: 'Message',
        component: ComingSoon,
        meta: { title: '留言', desc: '留言板与联系表单,阶段 3 上线。' },
        props: (route) => ({ title: route.meta.title, description: route.meta.desc })
      },
      {
        path: 'about',
        name: 'About',
        component: ComingSoon,
        meta: { title: '关于', desc: '关于我,阶段 1 与首页一起完善。' },
        props: (route) => ({ title: route.meta.title, description: route.meta.desc })
      },
      // 站点访客认证页:属于公开区(无需登录),放在 SiteLayout 里保持站点外观一致
      {
        path: 'signup',
        name: 'SignUp',
        component: () => import('@/views/site/SignUp.vue'),
        meta: { title: '注册' }
      },
      {
        path: 'signin',
        name: 'SignIn',
        component: () => import('@/views/site/SignIn.vue'),
        meta: { title: '登录' }
      },
      // 公开区兜底 404(放在子路由最后,确保优先匹配上面的具名路由)
      {
        path: ':pathMatch(.*)*',
        name: 'NotFound',
        component: () => import('@/views/site/NotFound.vue'),
        meta: { title: '页面不存在' }
      }
    ]
  },

  // ---------------- 登录页 ----------------
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/Login.vue'),
    meta: { title: '登录' }
  },

  // ---------------- 管理区(需登录) ----------------
  {
    path: '/admin',
    component: () => import('@/layout/AdminLayout.vue'),
    redirect: '/admin/dashboard',
    meta: { requiresAuth: true },
    children: [
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('@/views/Dashboard.vue'),
        meta: { title: '控制台', requiresAuth: true }
      },
      {
        path: 'system/user',
        name: 'UserList',
        component: () => import('@/views/system/UserList.vue'),
        meta: { title: '用户管理', requiresAuth: true }
      },
      {
        path: 'system/role',
        name: 'RoleList',
        component: () => import('@/views/system/RoleList.vue'),
        meta: { title: '角色管理', requiresAuth: true }
      }
    ]
  }
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior() {
    return { top: 0 }
  }
})

// 守卫:只拦标记了 requiresAuth 的路由(白名单),未登录带上 redirect 回跳
router.beforeEach((to) => {
  const token = localStorage.getItem('aki_token')
  const requiresAuth = to.matched.some((record) => record.meta?.requiresAuth)

  if (requiresAuth && !token) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }
  if (to.path === '/login' && token) {
    return { path: '/admin' }
  }
  return true
})

// 浏览器标题:公开区和后台共用,登录页也带上站点名
router.afterEach((to) => {
  document.title = to.meta?.title ? `${to.meta.title} · ${siteName}` : siteName
})

export default router
