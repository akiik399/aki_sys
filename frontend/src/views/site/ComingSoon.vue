<template>
  <div class="coming-soon">
    <el-empty :description="description">
      <template #description>
        <p class="title">{{ title }}</p>
        <p class="desc">{{ description }}</p>
      </template>
      <el-button type="primary" @click="$router.push('/')">返回首页</el-button>
    </el-empty>
  </div>
</template>

<script setup>
/**
 * 公开区占位页:阶段 0 先把路由和导航打通,游客点任何一项都有页面可看,
 * 不会撞 404。阶段 1-3 会用真实页面逐个替换掉 router 里指向它的路由。
 */
defineProps({
  title: { type: String, default: '建设中' },
  description: { type: String, default: '这个板块还在施工中,敬请期待。' }
})
</script>

<style scoped>
.coming-soon {
  padding: 48px 20px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  backdrop-filter: blur(14px) saturate(150%);
  -webkit-backdrop-filter: blur(14px) saturate(150%);
  border: 1px solid rgba(255, 255, 255, 0.9);
  box-shadow:
    0 1px 2px rgba(16, 24, 40, 0.04),
    0 18px 36px -24px rgba(16, 24, 40, 0.45);
}
.title {
  font-size: 16px;
  font-weight: 600;
  color: #1f2329;
  margin: 0 0 6px;
}
.desc {
  font-size: 13px;
  color: #8a94a6;
  margin: 0 0 8px;
}
</style>
