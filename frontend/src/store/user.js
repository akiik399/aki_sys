import { defineStore } from 'pinia'
import { login as apiLogin, logout as apiLogout, me as apiMe } from '@/api/auth'

const TOKEN_KEY = 'aki_token'
const USER_KEY = 'aki_user'

export const useUserStore = defineStore('user', {
  state: () => ({
    token: localStorage.getItem(TOKEN_KEY) || '',
    user: JSON.parse(localStorage.getItem(USER_KEY) || 'null')
  }),
  actions: {
    async login(form) {
      const res = await apiLogin(form)
      this.token = res.data.token
      this.user = res.data.user
      localStorage.setItem(TOKEN_KEY, this.token)
      localStorage.setItem(USER_KEY, JSON.stringify(this.user))
      return res.data.user
    },
    async logout() {
      try {
        await apiLogout()
      } catch (e) {
        // 忽略退出接口异常,本地必定清理
      }
      this.token = ''
      this.user = null
      localStorage.removeItem(TOKEN_KEY)
      localStorage.removeItem(USER_KEY)
    },
    async refreshMe() {
      const res = await apiMe()
      this.user = res.data
      localStorage.setItem(USER_KEY, JSON.stringify(res.data))
      return res.data
    }
  }
})
