<template>
  <div class="auth-page">
    <div class="auth-card">
      <h2 class="auth-title">注册账号</h2>
      <p class="auth-sub">注册后可以留言,方便我回复你</p>

      <el-form
        ref="formRef"
        :model="form"
        :rules="rules"
        label-position="top"
        @keyup.enter="handleSubmit"
      >
        <el-form-item label="邮箱" prop="email">
          <el-input v-model="form.email" placeholder="用于登录,不会公开" clearable />
        </el-form-item>

        <el-form-item label="昵称" prop="nickname">
          <el-input v-model="form.nickname" placeholder="2-20 个字符,对外展示" clearable />
        </el-form-item>

        <el-form-item label="密码" prop="password">
          <el-input
            v-model="form.password"
            type="password"
            placeholder="至少 8 位,需同时含字母和数字"
            show-password
          />
        </el-form-item>

        <el-form-item label="确认密码" prop="confirm">
          <el-input v-model="form.confirm" type="password" placeholder="再输入一次" show-password />
        </el-form-item>

        <el-form-item label="图形验证码" prop="captchaCode">
          <div class="captcha-row">
            <el-input v-model="form.captchaCode" placeholder="输入图中字符" maxlength="4" />
            <img
              v-if="captcha.image"
              :src="captcha.image"
              class="captcha-img"
              title="看不清?点击换一张"
              alt="图形验证码"
              @click="loadCaptcha"
            />
            <span v-else class="captcha-placeholder" @click="loadCaptcha">加载中…</span>
          </div>
        </el-form-item>

        <el-button type="primary" class="submit-btn" :loading="loading" @click="handleSubmit">
          注册并登录
        </el-button>
      </el-form>

      <div class="auth-foot">
        已有账号?<router-link to="/signin">去登录</router-link>
      </div>
      <div class="auth-note">
        当前为本地开发版本:邮箱暂不做验证,注册后直接可用
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { fetchCaptcha } from '@/api/account'
import { useSiteUserStore } from '@/store/siteUser'

const router = useRouter()
const store = useSiteUserStore()

const formRef = ref()
const loading = ref(false)
const captcha = reactive({ id: '', image: '' })

const form = reactive({
  email: '',
  nickname: '',
  password: '',
  confirm: '',
  captchaCode: ''
})

// 前端校验只是体验优化:后端会用同一套规则再校验一遍(直接 curl 就能绕过前端)
const rules = {
  email: [
    { required: true, message: '请输入邮箱', trigger: 'blur' },
    { type: 'email', message: '邮箱格式不正确', trigger: 'blur' }
  ],
  nickname: [
    { required: true, message: '请输入昵称', trigger: 'blur' },
    { min: 2, max: 20, message: '昵称长度需在 2-20 个字符之间', trigger: 'blur' }
  ],
  password: [
    { required: true, message: '请输入密码', trigger: 'blur' },
    { min: 8, max: 64, message: '密码长度需在 8-64 位之间', trigger: 'blur' },
    { pattern: /^(?=.*[A-Za-z])(?=.*\d).+$/, message: '密码需同时包含字母和数字', trigger: 'blur' }
  ],
  confirm: [
    { required: true, message: '请再输入一次密码', trigger: 'blur' },
    {
      validator: (rule, value, callback) => {
        if (value !== form.password) {
          callback(new Error('两次输入的密码不一致'))
        } else {
          callback()
        }
      },
      trigger: 'blur'
    }
  ],
  captchaCode: [{ required: true, message: '请输入图形验证码', trigger: 'blur' }]
}

async function loadCaptcha() {
  try {
    const res = await fetchCaptcha()
    captcha.id = res.data.captchaId
    captcha.image = res.data.image
    form.captchaCode = ''
  } catch (e) {
    // 响应拦截器已经弹过提示,这里不重复报错
  }
}

async function handleSubmit() {
  // validate() 校验不通过时会 reject,用 catch 转成 false,避免未处理的 Promise 异常
  const valid = await formRef.value.validate().catch(() => false)
  if (!valid) {
    return
  }
  loading.value = true
  try {
    const user = await store.register({
      email: form.email,
      nickname: form.nickname,
      password: form.password,
      captchaId: captcha.id,
      captchaCode: form.captchaCode
    })
    ElMessage.success(`注册成功,欢迎 ${user.nickname}`)
    router.push('/')
  } catch (e) {
    // 验证码是**一次性**的(后端校验后立即删除),提交失败必须换一张,
    // 否则用户会拿着已作废的验证码反复失败,以为是自己的问题
    loadCaptcha()
  } finally {
    loading.value = false
  }
}

onMounted(loadCaptcha)
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

.captcha-row {
  display: flex;
  gap: 10px;
  align-items: center;
  width: 100%;
}

.captcha-img {
  height: 40px;
  width: 120px;
  flex-shrink: 0;
  border-radius: 8px;
  border: 1px solid #e0e6ef;
  cursor: pointer;
  background: #f4f7fc;
}

.captcha-placeholder {
  height: 40px;
  width: 120px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  color: #8a94a6;
  border: 1px dashed #d5dded;
  border-radius: 8px;
  cursor: pointer;
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
