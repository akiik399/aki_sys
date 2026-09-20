import axios from 'axios'
import { ElMessage } from 'element-plus'

/**
 * 站点访客专用的 axios 实例。
 *
 * 为什么**不复用** api/request.js:
 *   1. 那个实例收到 401 会清掉 aki_token 并跳 /login —— 那是**后台登录页**。
 *      访客的 token 失效时会被错误地推进后台登录页。
 *   2. 两个域的 token 必须分开存。若共用一个 localStorage 键,
 *      在同一浏览器里先后登录后台和站点会互相覆盖登录态。
 *
 * 401 的处理策略:清掉本地 token 并广播 site-auth-expired 事件,
 * 由布局层去清 Pinia 状态。**不做自动跳转** —— 访客可能只是在浏览公开页面,
 * 不该因为一个后台请求失败就被弹走。
 */
export const SITE_TOKEN_KEY = 'aki_site_token'

const siteRequest = axios.create({
  baseURL: '/api',
  timeout: 15000
})

export function getSiteToken() {
  return localStorage.getItem(SITE_TOKEN_KEY) || ''
}

export function setSiteToken(token) {
  if (token) {
    localStorage.setItem(SITE_TOKEN_KEY, token)
  }
}

export function clearSiteToken() {
  localStorage.removeItem(SITE_TOKEN_KEY)
}

// 请求拦截:附带站点 token
siteRequest.interceptors.request.use((config) => {
  const token = getSiteToken()
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// 响应拦截:统一处理业务码(本项目所有错误都是 HTTP 200 + 业务码)
siteRequest.interceptors.response.use(
  (response) => {
    const res = response.data
    if (res.code === 200) {
      return res
    }
    ElMessage.error(res.msg || '请求失败')
    return Promise.reject(new Error(res.msg || '请求失败'))
  },
  (error) => {
    if (error.response && error.response.status === 401) {
      clearSiteToken()
      window.dispatchEvent(new CustomEvent('site-auth-expired'))
      ElMessage.error(error.response.data?.msg || '登录已失效,请重新登录')
    } else {
      ElMessage.error(error.response?.data?.msg || error.message || '网络错误')
    }
    return Promise.reject(error)
  }
)

export default siteRequest
