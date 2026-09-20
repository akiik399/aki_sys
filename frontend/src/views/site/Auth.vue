<template>
  <div class="auth-page">
    <div class="auth-card">
      <!-- ---------- 找回密码:标题 + 步骤条 ---------- -->
      <template v-if="mode === 'forgot'">
        <h2 class="auth-title">找回密码</h2>
        <p class="auth-sub">通过邮箱验证码重置密码</p>
        <el-steps :active="resetStep" simple class="reset-steps">
          <el-step title="验证邮箱" />
          <el-step title="填写验证码" />
          <el-step title="设置新密码" />
        </el-steps>
      </template>

      <!-- ---------- 登录 / 注册:Tab ---------- -->
      <template v-else>
        <div class="tabs">
          <button
            class="tab"
            :class="{ active: mode === 'login' }"
            type="button"
            @click="switchMode('login')"
          >
            登录
          </button>
          <button
            class="tab"
            :class="{ active: mode === 'register' }"
            type="button"
            @click="switchMode('register')"
          >
            注册
          </button>
        </div>
      </template>

      <!-- ================= 登录 ================= -->
      <el-form
        v-if="mode === 'login'"
        ref="loginFormRef"
        :model="loginForm"
        :rules="loginRules"
        label-position="top"
        @keyup.enter="handleLogin"
      >
        <el-form-item label="邮箱" prop="email">
          <el-input v-model="loginForm.email" placeholder="注册时填的邮箱" clearable />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input v-model="loginForm.password" type="password" placeholder="你的密码" show-password />
        </el-form-item>

        <div class="row-between">
          <span />
          <a class="text-link" @click="switchMode('forgot')">忘记密码?</a>
        </div>

        <el-button type="primary" class="submit-btn" :loading="loading" @click="handleLogin">
          登 录
        </el-button>
      </el-form>

      <!-- ================= 注册 ================= -->
      <el-form
        v-else-if="mode === 'register'"
        ref="regFormRef"
        :model="regForm"
        :rules="regRules"
        label-position="top"
        @keyup.enter="handleRegister"
      >
        <el-form-item label="邮箱" prop="email">
          <el-input v-model="regForm.email" placeholder="用于登录,不会公开" clearable />
        </el-form-item>
        <el-form-item label="昵称" prop="nickname">
          <el-input v-model="regForm.nickname" placeholder="2-20 个字符,对外展示" clearable />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input
            v-model="regForm.password"
            type="password"
            placeholder="至少 8 位,需同时含字母和数字"
            show-password
          />
        </el-form-item>
        <el-form-item label="确认密码" prop="confirm">
          <el-input v-model="regForm.confirm" type="password" placeholder="再输入一次" show-password />
        </el-form-item>
        <el-form-item label="图形验证码" prop="captchaCode">
          <div class="captcha-row">
            <el-input v-model="regForm.captchaCode" placeholder="输入图中字符" maxlength="4" />
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

        <el-button type="primary" class="submit-btn" :loading="loading" @click="handleRegister">
          注册并登录
        </el-button>
      </el-form>

      <!-- ================= 找回密码 ================= -->
      <div v-else>
        <!-- 第 1 步:验证邮箱 -->
        <el-form
          v-if="resetStep === 0"
          ref="reset0Ref"
          :model="forgot"
          :rules="reset0Rules"
          label-position="top"
          @keyup.enter="handleSendResetCode"
        >
          <el-form-item label="注册邮箱" prop="email">
            <el-input v-model="forgot.email" placeholder="你注册时用的邮箱" clearable />
          </el-form-item>
          <el-form-item label="图形验证码" prop="captchaCode">
            <div class="captcha-row">
              <el-input v-model="forgot.captchaCode" placeholder="输入图中字符" maxlength="4" />
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
          <el-button type="primary" class="submit-btn" :loading="loading" @click="handleSendResetCode">
            发送验证码
          </el-button>
        </el-form>

        <!-- 第 2 步:填邮箱验证码 -->
        <el-form
          v-else-if="resetStep === 1"
          ref="reset1Ref"
          :model="forgot"
          :rules="reset1Rules"
          label-position="top"
          @keyup.enter="handleVerifyResetCode"
        >
          <el-alert
            type="info"
            :closable="false"
            show-icon
            :title="`验证码已发送到 ${forgot.email}`"
            description="如果该邮箱已注册,你会收到一封含 6 位验证码的邮件(5 分钟内有效)。没收到请检查垃圾邮件。"
          />
          <el-form-item label="邮箱验证码" prop="code">
            <el-input v-model="forgot.code" placeholder="6 位数字" maxlength="6" />
          </el-form-item>
          <el-button type="primary" class="submit-btn" :loading="loading" @click="handleVerifyResetCode">
            下一步
          </el-button>
          <div class="row-between">
            <a class="text-link" @click="backToFirstStep">换个邮箱</a>
            <span class="text-muted">没收到?等 60 秒后可重新发送</span>
          </div>
        </el-form>

        <!-- 第 3 步:设置新密码 -->
        <el-form
          v-else
          ref="reset2Ref"
          :model="forgot"
          :rules="reset2Rules"
          label-position="top"
          @keyup.enter="handleResetPassword"
        >
          <el-form-item label="新密码" prop="newPassword">
            <el-input
              v-model="forgot.newPassword"
              type="password"
              placeholder="至少 8 位,需同时含字母和数字"
              show-password
            />
          </el-form-item>
          <el-form-item label="确认新密码" prop="confirm">
            <el-input v-model="forgot.confirm" type="password" placeholder="再输入一次" show-password />
          </el-form-item>
          <el-button type="primary" class="submit-btn" :loading="loading" @click="handleResetPassword">
            重置密码
          </el-button>
          <div class="row-between">
            <span class="text-muted">重置成功后,该账号所有已登录设备都会被强制下线</span>
          </div>
        </el-form>
      </div>

      <!-- ---------- 底部 ---------- -->
      <div class="auth-foot">
        <template v-if="mode === 'forgot'">
          <a class="text-link" @click="backToLogin">← 返回登录</a>
        </template>
        <template v-else-if="mode === 'login'">
          还没有账号?<a class="text-link" @click="switchMode('register')">去注册</a>
        </template>
        <template v-else>
          已有账号?<a class="text-link" @click="switchMode('login')">去登录</a>
        </template>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import {
  fetchCaptcha,
  sendResetCode,
  verifyResetCode,
  resetPassword
} from '@/api/account'
import { useSiteUserStore } from '@/store/siteUser'

const route = useRoute()
const router = useRouter()
const store = useSiteUserStore()

const mode = ref('login')
const loading = ref(false)
const captcha = reactive({ id: '', image: '' })

// 登录
const loginFormRef = ref()
const loginForm = reactive({ email: '', password: '' })

// 注册
const regFormRef = ref()
const regForm = reactive({ email: '', nickname: '', password: '', confirm: '', captchaCode: '' })

// 找回密码
const resetStep = ref(0)
const reset0Ref = ref()
const reset1Ref = ref()
const reset2Ref = ref()
const resetToken = ref('')
const forgot = reactive({ email: '', captchaCode: '', code: '', newPassword: '', confirm: '' })

// ---- 复用的校验片段(前端只是体验优化,后端有同一套规则再校验一遍) ----
const emailRules = [
  { required: true, message: '请输入邮箱', trigger: 'blur' },
  { type: 'email', message: '邮箱格式不正确', trigger: 'blur' }
]
const passwordRules = [
  { required: true, message: '请输入密码', trigger: 'blur' },
  { min: 8, max: 64, message: '密码长度需在 8-64 位之间', trigger: 'blur' },
  { pattern: /^(?=.*[A-Za-z])(?=.*\d).+$/, message: '密码需同时包含字母和数字', trigger: 'blur' }
]
const captchaRules = [{ required: true, message: '请输入图形验证码', trigger: 'blur' }]
const confirmRule = (getPassword) => [
  { required: true, message: '请再输入一次密码', trigger: 'blur' },
  {
    validator: (rule, value, callback) => {
      if (value !== getPassword()) {
        callback(new Error('两次输入的密码不一致'))
      } else {
        callback()
      }
    },
    trigger: 'blur'
  }
]

const loginRules = { email: emailRules, password: [{ required: true, message: '请输入密码', trigger: 'blur' }] }
const regRules = {
  email: emailRules,
  nickname: [
    { required: true, message: '请输入昵称', trigger: 'blur' },
    { min: 2, max: 20, message: '昵称长度需在 2-20 个字符之间', trigger: 'blur' }
  ],
  password: passwordRules,
  confirm: confirmRule(() => regForm.password),
  captchaCode: captchaRules
}
const reset0Rules = { email: emailRules, captchaCode: captchaRules }
const reset1Rules = [
  { required: true, message: '请输入验证码', trigger: 'blur' },
  { len: 6, message: '验证码为 6 位数字', trigger: 'blur' }
]
const reset2Rules = {
  newPassword: passwordRules,
  confirm: confirmRule(() => forgot.newPassword)
}

async function loadCaptcha() {
  try {
    const res = await fetchCaptcha()
    captcha.id = res.data.captchaId
    captcha.image = res.data.image
    regForm.captchaCode = ''
    forgot.captchaCode = ''
  } catch (e) {
    // 响应拦截器已提示
  }
}

/** 校验辅助:校验失败时 validate() 会 reject,转成 false 避免未处理的 Promise 异常 */
async function validate(formRef) {
  return formRef.value.validate().catch(() => false)
}

function switchMode(next) {
  mode.value = next
  if (next === 'forgot') {
    resetStep.value = 0
  }
  // 图形验证码是一次性的,切换模式后必须换一张
  if (next !== 'login') {
    loadCaptcha()
  }
}

function backToLogin() {
  mode.value = 'login'
}

function backToFirstStep() {
  resetStep.value = 0
  loadCaptcha()
}

async function handleLogin() {
  if (!(await validate(loginFormRef))) return
  loading.value = true
  try {
    const user = await store.login({ email: loginForm.email, password: loginForm.password })
    ElMessage.success(`欢迎回来,${user.nickname}`)
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : ''
    router.push(redirect || '/')
  } catch (e) {
    // 拦截器已提示(统一话术:"邮箱或密码错误")
  } finally {
    loading.value = false
  }
}

async function handleRegister() {
  if (!(await validate(regFormRef))) return
  loading.value = true
  try {
    const user = await store.register({
      email: regForm.email,
      nickname: regForm.nickname,
      password: regForm.password,
      captchaId: captcha.id,
      captchaCode: regForm.captchaCode
    })
    ElMessage.success(`注册成功,欢迎 ${user.nickname}`)
    router.push('/')
  } catch (e) {
    // 验证码一次性,失败必须换一张
    loadCaptcha()
  } finally {
    loading.value = false
  }
}

/** 找回密码第 1 步:发验证码 */
async function handleSendResetCode() {
  if (!(await validate(reset0Ref))) return
  loading.value = true
  try {
    const res = await sendResetCode({
      email: forgot.email,
      captchaId: captcha.id,
      captchaCode: forgot.captchaCode
    })
    // 注意:后端无论邮箱是否注册都返回同一句话,这里不要自作聪明去判断
    ElMessage.success(res.msg || '如果该邮箱已注册,验证码已发送')
    forgot.code = ''
    resetStep.value = 1
  } catch (e) {
    loadCaptcha()
  } finally {
    loading.value = false
  }
}

/** 找回密码第 2 步:验码换令牌 */
async function handleVerifyResetCode() {
  if (!(await validate(reset1Ref))) return
  loading.value = true
  try {
    const res = await verifyResetCode({ email: forgot.email, code: forgot.code })
    resetToken.value = res.data.resetToken
    forgot.newPassword = ''
    forgot.confirm = ''
    resetStep.value = 2
  } catch (e) {
    // 验证码错误/过期由拦截器提示,用户可以直接改输入重试(有 5 次机会)
  } finally {
    loading.value = false
  }
}

/** 找回密码第 3 步:改密 */
async function handleResetPassword() {
  if (!(await validate(reset2Ref))) return
  loading.value = true
  try {
    await resetPassword({ resetToken: resetToken.value, newPassword: forgot.newPassword })
    ElMessage.success('密码已重置,请用新密码登录')
    // 回到登录页并预填邮箱,省得用户再打一遍
    loginForm.email = forgot.email
    loginForm.password = ''
    mode.value = 'login'
    resetStep.value = 0
    resetToken.value = ''
    forgot.code = ''
    forgot.newPassword = ''
    forgot.confirm = ''
  } catch (e) {
    // 令牌过期等错误由拦截器提示
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  // 支持 /signin?mode=register 这样的深链(导航栏的「注册」按钮就指向它)
  const q = route.query.mode
  if (q === 'register' || q === 'forgot') {
    mode.value = q
  }
  if (mode.value !== 'login') {
    loadCaptcha()
  }
})
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
  padding: 24px 26px 20px;
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
  font-size: 21px;
  font-weight: 700;
}

.auth-sub {
  margin: 0 0 18px;
  font-size: 13px;
  color: #8a94a6;
}

/* ---------- 登录 / 注册 Tab ---------- */
.tabs {
  display: flex;
  gap: 6px;
  margin-bottom: 18px;
  padding: 4px;
  border-radius: 12px;
  background: rgba(43, 108, 255, 0.06);
}

.tab {
  flex: 1;
  padding: 9px 0;
  font-size: 14px;
  font-family: inherit;
  color: #5a6472;
  background: transparent;
  border: none;
  border-radius: 9px;
  cursor: pointer;
  transition: all 0.18s;
}

.tab:hover {
  color: #2b6cff;
}

.tab.active {
  color: #2b6cff;
  font-weight: 600;
  background: #fff;
  box-shadow: 0 2px 8px -2px rgba(16, 24, 40, 0.16);
}

.reset-steps {
  margin-bottom: 18px;
  background: transparent;
}

/* ---------- 表单 ---------- */
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

.row-between {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin: 2px 0 12px;
  font-size: 12px;
}

.text-link {
  color: #2b6cff;
  cursor: pointer;
  text-decoration: none;
}

.text-link:hover {
  text-decoration: underline;
}

.text-muted {
  color: #aab3c0;
}

.auth-foot {
  margin-top: 16px;
  padding-top: 12px;
  border-top: 1px dashed #e4e9f2;
  text-align: center;
  font-size: 13px;
  color: #5a6472;
}
</style>
