<template>
  <el-container class="layout">
    <el-aside width="220px" class="aside">
      <div class="logo">个人主页 · 后台</div>
      <el-menu
        :default-active="$route.path"
        router
        background-color="#001529"
        text-color="#c0c4cc"
        active-text-color="#409eff"
      >
        <el-menu-item index="/admin/dashboard">
          <el-icon><HomeFilled /></el-icon>
          <span>控制台</span>
        </el-menu-item>
        <el-sub-menu index="/admin/system">
          <template #title>
            <el-icon><Setting /></el-icon>
            <span>系统管理</span>
          </template>
          <el-menu-item index="/admin/system/user">
            <el-icon><User /></el-icon>
            <span>用户管理</span>
          </el-menu-item>
          <el-menu-item index="/admin/system/role">
            <el-icon><Avatar /></el-icon>
            <span>角色管理</span>
          </el-menu-item>
        </el-sub-menu>
        <!-- 阶段 1 起在这里追加内容管理菜单:个人资料 / 技能 / 项目 / 文章 / 留言 / 访问日志 -->
        <el-menu-item index="/">
          <el-icon><Link /></el-icon>
          <span>返回主页</span>
        </el-menu-item>
      </el-menu>
    </el-aside>

    <el-container>
      <el-header class="header">
        <div class="header-title">{{ $route.meta.title }}</div>
        <el-dropdown @command="handleCommand">
          <span class="user-box">
            <el-icon><UserFilled /></el-icon>
            <span>{{ store.user?.nickname || store.user?.username || '未登录' }}</span>
            <el-icon><ArrowDown /></el-icon>
          </span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item command="logout" divided>退出登录</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </el-header>

      <el-main class="main">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useUserStore } from '@/store/user'
import {
  HomeFilled,
  Setting,
  User,
  Avatar,
  UserFilled,
  ArrowDown,
  Link
} from '@element-plus/icons-vue'

const router = useRouter()
const store = useUserStore()

async function handleCommand(command) {
  if (command === 'logout') {
    await store.logout()
    router.push('/login')
  }
}
</script>

<style scoped>
.layout {
  height: 100%;
}
.aside {
  background-color: #001529;
  overflow-x: hidden;
}
.logo {
  height: 60px;
  line-height: 60px;
  text-align: center;
  color: #fff;
  font-size: 16px;
  font-weight: 600;
  letter-spacing: 1px;
}
.aside :deep(.el-menu) {
  border-right: none;
}
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid #e8e8e8;
  background: #fff;
}
.header-title {
  font-size: 16px;
  font-weight: 600;
}
.user-box {
  display: flex;
  align-items: center;
  gap: 4px;
  cursor: pointer;
  color: #333;
}
.main {
  background: #f0f2f5;
}
</style>
