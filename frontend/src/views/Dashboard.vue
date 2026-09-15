<template>
  <div>
    <el-card class="page-card">
      <template #header>你好,{{ store.user?.nickname || store.user?.username }}</template>
      <p>欢迎使用 aki_sys 后台管理系统。技术栈:</p>
      <el-descriptions :column="2" border style="margin-top: 12px">
        <el-descriptions-item label="后端">
          Spring Boot 3.4.4 · MyBatis-Plus 3.5.9 · JWT · Redis · MySQL 8
        </el-descriptions-item>
        <el-descriptions-item label="前端">
          Vue 3.5 · Vite 5 · Element Plus · Pinia · Axios
        </el-descriptions-item>
        <el-descriptions-item label="默认账号">admin / admin123</el-descriptions-item>
        <el-descriptions-item label="接口文档">
          <a href="http://localhost:8080/swagger-ui.html" target="_blank">
            http://localhost:8080/swagger-ui.html
          </a>
        </el-descriptions-item>
      </el-descriptions>

      <el-alert
        style="margin-top: 16px"
        type="info"
        :closable="false"
        show-icon
        title="登录态说明"
        description="登录成功后后端会把 token 写入 Redis(有效期 8 小时),所有受保护接口需携带该 token;退出登录会立即删除 Redis 中的登录态,使 token 失效。"
      />
    </el-card>
  </div>
</template>

<script setup>
import { useUserStore } from '@/store/user'

const store = useUserStore()
</script>
