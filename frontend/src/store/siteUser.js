import { defineStore } from 'pinia'
import { login as apiLogin, register as apiRegister, logout as apiLogout, me as apiMe } from '@/api/account'
import { getSiteToken, setSiteToken, clearSiteToken } from '@/api/siteRequest'

/**
 * 站点访客登录状态。
 *
 * 与后台的 store/user.js 是两个独立 store:token 分开存、用户对象结构也不同。
 * 混用会导致前后台登录态互相覆盖。
 */
export const useSiteUserStore = defineStore('siteUser', {
  state: () => ({
    token: getSiteToken(),
    user: null,
    // 是否已经尝试过拉取用户信息(避免首屏闪烁:还没拉之前不要当成未登录来渲染)
    loaded: false
  }),

  getters: {
    isLoggedIn: (state) => !!state.token,
    displayName: (state) => state.user?.nickname || state.user?.email || ''
  },

  actions: {
    async register(form) {
      const res = await apiRegister(form)
      this.applySession(res.data)
      return res.data.user
    },

    async login(form) {
      const res = await apiLogin(form)
      this.applySession(res.data)
      return res.data.user
    },

    /**
     * 拉取当前访客信息。token 失效(401)时静默清空状态 ——
     * 用户下次操作自然会看到需要重新登录,不必在浏览公开页面时被弹窗打断。
     */
    async fetchMe() {
      if (!this.token) {
        this.loaded = true
        return null
      }
      try {
        const res = await apiMe()
        this.user = res.data
        return res.data
      } catch (e) {
        this.clear()
        return null
      } finally {
        this.loaded = true
      }
    },

    async logout() {
      try {
        await apiLogout()
      } catch (e) {
        // 忽略退出接口异常,本地必定清理
      }
      this.clear()
    },

    applySession(data) {
      this.token = data.token
      setSiteToken(data.token)
      this.user = data.user
      this.loaded = true
    },

    clear() {
      this.token = ''
      this.user = null
      this.loaded = true
      clearSiteToken()
    }
  }
})
