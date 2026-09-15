<template>
  <div class="not-found">
    <div class="code">404</div>
    <p class="text">这个页面不存在,可能是链接写错了。</p>
    <el-button type="primary" @click="$router.push('/')">回到首页</el-button>
  </div>
</template>

<script setup>
// 公开区的兜底页。注意:这里不再是"重定向回首页",否则站内错链会被静默吞掉,排查不到。
</script>

<style scoped>
.not-found {
  text-align: center;
  padding: 80px 20px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  backdrop-filter: blur(14px) saturate(150%);
  -webkit-backdrop-filter: blur(14px) saturate(150%);
  border: 1px solid rgba(255, 255, 255, 0.9);
  box-shadow:
    0 1px 2px rgba(16, 24, 40, 0.04),
    0 18px 36px -24px rgba(16, 24, 40, 0.45);
}
.code {
  font-size: 68px;
  font-weight: 800;
  line-height: 1;
  letter-spacing: 2px;
  background: linear-gradient(120deg, #b9cffd, #2b6cff 55%, #6d5cf6);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}
.text {
  color: #8a94a6;
  font-size: 14px;
  margin: 14px 0 22px;
}
</style>
