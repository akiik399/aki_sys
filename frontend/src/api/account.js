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

/** 退出登录 */
export function logout() {
  return siteRequest.post('/account/logout')
}

/** 当前登录访客 */
export function me() {
  return siteRequest.get('/account/me')
}
