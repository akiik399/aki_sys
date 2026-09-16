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
          <!-- 开发环境指向本地后端;生产构建时 VITE_API_DOC_URL 为空,改为提示文案。
               原来这里硬编码 http://localhost:8080/swagger-ui.html,线上访问者点开
               只会打开自己的本机 8080,而生产配置(application-prod.yml)又把
               Swagger 关掉了,所以那行在生产环境一定是死链。 -->
          <a v-if="apiDocUrl" :href="apiDocUrl" target="_blank" rel="noopener">{{ apiDocUrl }}</a>
          <span v-else style="color: var(--el-text-color-secondary)">
            生产环境已关闭(需要时改 application-prod.yml 并加 IP 白名单)
          </span>
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

// import.meta.env 的值在【构建时】就替换成字面量了,所以生产包里不会留下
// localhost 这种开发地址;开发时未设置则回退到本地 Swagger 地址。
const apiDocUrl = import.meta.env.PROD
  ? (import.meta.env.VITE_API_DOC_URL || '')
  : (import.meta.env.VITE_API_DOC_URL || 'http://localhost:8080/swagger-ui.html')
</script>
