<template>
  <div class="login-wrap">
    <el-card class="login-card">
      <div class="login-title">个人主页 · 后台管理</div>
      <el-form
        ref="formRef"
        :model="form"
        :rules="rules"
        size="large"
        @keyup.enter="handleLogin"
      >
        <el-form-item prop="username">
          <el-input
            v-model="form.username"
            placeholder="用户名"
            :prefix-icon="User"
            clearable
          />
        </el-form-item>
        <el-form-item prop="password">
          <el-input
            v-model="form.password"
            type="password"
            placeholder="密码"
            :prefix-icon="Lock"
            show-password
          />
        </el-form-item>
        <el-form-item>
          <el-button
            type="primary"
            class="login-btn"
            :loading="loading"
            @click="handleLogin"
          >
            登 录
          </el-button>
        </el-form-item>
      </el-form>
      <div class="login-tip">默认账号: admin / admin123</div>
    </el-card>
  </div>
</template>

<script setup>
import { reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { User, Lock } from '@element-plus/icons-vue'
import { useUserStore } from '@/store/user'

const route = useRoute()
const router = useRouter()
const store = useUserStore()

const formRef = ref()
const loading = ref(false)
const form = reactive({ username: '', password: '' })

const rules = {
  username: [{ required: true, message: '请输入用户名', trigger: 'blur' }],
  password: [{ required: true, message: '请输入密码', trigger: 'blur' }]
}

async function handleLogin() {
  await formRef.value.validate()
  loading.value = true
  try {
    const user = await store.login({ ...form })
    ElMessage.success(`欢迎回来, ${user.nickname || user.username}`)
    // 未登录时被守卫拦下来的页面会带上 redirect,登录后回跳;否则进后台控制台
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : ''
    router.push(redirect || '/admin')
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-wrap {
  position: relative;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  /* 与公开站点同一套视觉语言:深蓝极光渐变 + 细点阵 */
  background:
    radial-gradient(900px 520px at 10% 6%, rgba(59, 130, 246, 0.5), transparent 60%),
    radial-gradient(760px 460px at 92% 94%, rgba(99, 102, 241, 0.48), transparent 62%),
    radial-gradient(620px 400px at 78% 4%, rgba(14, 165, 233, 0.34), transparent 60%),
    linear-gradient(140deg, #0b1f45 0%, #142f63 46%, #1e3a8a 100%);
}
.login-wrap::after {
  content: '';
  position: absolute;
  inset: 0;
  pointer-events: none;
  background-image: radial-gradient(rgba(255, 255, 255, 0.09) 1px, transparent 1px);
  background-size: 24px 24px;
  -webkit-mask-image: radial-gradient(72% 62% at 50% 45%, #000 28%, transparent 100%);
  mask-image: radial-gradient(72% 62% at 50% 45%, #000 28%, transparent 100%);
}
.login-card {
  position: relative;
  z-index: 1;
  width: 380px;
  padding: 8px 16px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.94);
  backdrop-filter: blur(16px) saturate(150%);
  -webkit-backdrop-filter: blur(16px) saturate(150%);
  border: 1px solid rgba(255, 255, 255, 0.7);
  box-shadow: 0 28px 64px -24px rgba(2, 10, 30, 0.7);
}
.login-title {
  text-align: center;
  font-size: 20px;
  font-weight: 700;
  margin: 8px 0 24px;
  letter-spacing: 0.5px;
}
.login-btn {
  width: 100%;
}
.login-tip {
  text-align: center;
  color: #999;
  font-size: 12px;
}
</style>
