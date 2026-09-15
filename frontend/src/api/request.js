import axios from 'axios'
import { ElMessage } from 'element-plus'

const request = axios.create({
  baseURL: '/api',
  timeout: 15000
})

// 请求拦截:附带 token
request.interceptors.request.use((config) => {
  const token = localStorage.getItem('aki_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// 响应拦截:统一处理业务码
request.interceptors.response.use(
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
      ElMessage.error(error.response.data?.msg || '登录已失效,请重新登录')
      localStorage.removeItem('aki_token')
      localStorage.removeItem('aki_user')
      if (location.pathname !== '/login') {
        location.href = '/login'
      }
    } else {
      ElMessage.error(error.response?.data?.msg || error.message || '网络错误')
    }
    return Promise.reject(error)
  }
)

export default request
