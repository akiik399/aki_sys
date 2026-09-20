import siteRequest from './siteRequest'

/** 图形验证码:返回 { captchaId, image(data URL) } */
export function fetchCaptcha() {
  return siteRequest.get('/public/captcha')
}

/** 注册(需图形验证码),成功即登录 */
export function register(data) {
  return siteRequest.post('/public/register', data)
}

/** 登录(邮箱 + 密码) */
export function login(data) {
  return siteRequest.post('/public/login', data)
}

// ---------------- 找回密码(三步) ----------------

/** 第一步:发送验证码(需图形验证码)。无论邮箱是否注册,返回话术一致 */
export function sendResetCode(data) {
  return siteRequest.post('/public/reset/code', data)
}

/** 第二步:校验验证码,换一次性重置令牌 */
export function verifyResetCode(data) {
  return siteRequest.post('/public/reset/verify', data)
}

/** 第三步:用令牌设置新密码 */
export function resetPassword(data) {
  return siteRequest.post('/public/reset/confirm', data)
}

/** 退出登录 */
export function logout() {
  return siteRequest.post('/account/logout')
}

/** 当前登录访客 */
export function me() {
  return siteRequest.get('/account/me')
}
