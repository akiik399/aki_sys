/**
 * 站点级配置:改这一个文件就能改全站标题、SEO 描述、导航栏与页脚。
 * 阶段 1 接入后端后,昵称/头像/标语等会改为从 /api/public/profile 读取,这里只留兜底默认值。
 */

// 全站名称(浏览器标题、站点头部、页脚版权都用它)
export const siteName = 'Aki 的个人主页'

// 头部左上角展示的短名,太长会挤掉导航
export const siteShortName = 'Aki'

// SEO 描述(阶段 5 会写进 meta description / OG 标签)
export const siteDescription = '一个后端开发者的个人主页:项目作品、技术文章与经历。'

// 作者署名(页脚版权)
export const author = 'Aki'

/**
 * 公开区导航。
 * path 必须与 router/index.js 里的公开路由一致;改这里导航栏自动跟着变。
 */
export const navItems = [
  { path: '/', title: '首页' },
  { path: '/projects', title: '项目' },
  { path: '/posts', title: '文章' },
  { path: '/timeline', title: '时间线' },
  { path: '/message', title: '留言' },
  { path: '/about', title: '关于' }
]

// 管理后台入口(导航栏右侧的"后台"链接)
export const adminEntry = '/admin'
