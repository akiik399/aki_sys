<template>
  <div class="auth-page">
    <div class="auth-card">
      <h2 class="auth-title">登录</h2>
      <p class="auth-sub">用注册时填的邮箱登录</p>

      <el-form
        ref="formRef"
        :model="form"
        :rules="rules"
        label-position="top"
        @keyup.enter="handleSubmit"
      >
        <el-form-item label="邮箱" prop="email">
          <el-input v-model="form.email" placeholder="你的邮箱" clearable />
        </el-form-item>

        <el-form-item label="密码" prop="password">
          <el-input v-model="form.password" type="password" placeholder="你的密码" show-password />
        </el-form-item>

        <el-button type="primary" class="submit-btn" :loading="loading" @click="handleSubmit">
          登 录
        </el-button>
      </el-form>

      <div class="auth-foot">
        还没有账号?<router-link to="/signup">去注册</router-link>
      </div>

      <!-- 验证码登录与忘记密码依赖邮件通道,属于下一阶段(2b),这里先如实标注而不是放个点了没反应的链接 -->
      <div class="auth-note">
        验证码登录 / 忘记密码 需要邮件通道,正在开发中
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { ElMessage } from 'element-plus'
import { useSiteUserStore } from '@/store/siteUser'

const router = useRouter()
const route = useRoute()
const store = useSiteUserStore()

const formRef = ref()
const loading = ref(false)
const form = reactive({ email: '', password: '' })

const rules = {
  email: [
    { required: true, message: '请输入邮箱', trigger: 'blur' },
    { type: 'email', message: '邮箱格式不正确', trigger: 'blur' }
  ],
  password: [{ required: true, message: '请输入密码', trigger: 'blur' }]
}

async function handleSubmit() {
  const valid = await formRef.value.validate().catch(() => false)
  if (!valid) {
    return
  }
  loading.value = true
  try {
    const user = await store.login({ email: form.email, password: form.password })
    ElMessage.success(`欢迎回来,${user.nickname}`)
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : ''
    router.push(redirect || '/')
  } catch (e) {
    // 响应拦截器已提示(统一话术:"邮箱或密码错误",不泄露邮箱是否存在)
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.auth-page {
  display: flex;
  justify-content: center;
  padding: 12px 0 32px;
}

.auth-card {
  width: 100%;
  max-width: 420px;
  padding: 28px 26px 22px;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.78);
  backdrop-filter: blur(14px) saturate(150%);
  -webkit-backdrop-filter: blur(14px) saturate(150%);
  border: 1px solid rgba(255, 255, 255, 0.9);
  box-shadow:
    0 1px 2px rgba(16, 24, 40, 0.04),
    0 20px 44px -26px rgba(16, 24, 40, 0.5);
}

.auth-title {
  margin: 0 0 6px;
  font-size: 22px;
  font-weight: 700;
}

.auth-sub {
  margin: 0 0 20px;
  font-size: 13px;
  color: #8a94a6;
}

.submit-btn {
  width: 100%;
  margin-top: 4px;
}

.auth-foot {
  margin-top: 16px;
  text-align: center;
  font-size: 13px;
  color: #5a6472;
}

.auth-foot a {
  color: #2b6cff;
  text-decoration: none;
}

.auth-note {
  margin-top: 12px;
  text-align: center;
  font-size: 12px;
  color: #aab3c0;
}
</style>
