<template>
  <el-card class="page-card">
    <!-- 工具栏 -->
    <div class="table-toolbar">
      <el-input
        v-model="query.username"
        placeholder="按用户名搜索"
        clearable
        style="width: 180px"
        @keyup.enter="handleSearch"
      />
      <el-select
        v-model="query.roleId"
        placeholder="角色"
        clearable
        style="width: 150px"
      >
        <el-option
          v-for="r in roles"
          :key="r.id"
          :label="r.name"
          :value="r.id"
        />
      </el-select>
      <el-select
        v-model="query.status"
        placeholder="状态"
        clearable
        style="width: 130px"
      >
        <el-option label="正常" :value="1" />
        <el-option label="禁用" :value="0" />
      </el-select>
      <el-button type="primary" :icon="Search" @click="handleSearch">查询</el-button>
      <el-button :icon="Refresh" @click="handleReset">重置</el-button>
      <div style="flex: 1"></div>
      <el-button type="primary" :icon="Plus" @click="openCreate">新增用户</el-button>
    </div>

    <!-- 表格 -->
    <el-table v-loading="loading" :data="rows" border stripe>
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column prop="username" label="用户名" min-width="120" />
      <el-table-column prop="nickname" label="昵称" min-width="120" />
      <el-table-column label="角色" width="130">
        <template #default="{ row }">{{ roleName(row.roleId) || '-' }}</template>
      </el-table-column>
      <el-table-column label="状态" width="90" align="center">
        <template #default="{ row }">
          <el-tag :type="row.status === 1 ? 'success' : 'danger'">
            {{ row.status === 1 ? '正常' : '禁用' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="创建时间" width="170">
        <template #default="{ row }">{{ fmtTime(row.createdAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="230" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click="openEdit(row)">编辑</el-button>
          <el-button link type="warning" @click="openResetPwd(row)">重置密码</el-button>
          <el-button
            link
            type="danger"
            :disabled="row.id === store.user?.id"
            @click="handleDelete(row)"
          >
            删除
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <!-- 分页 -->
    <el-pagination
      v-model:current-page="query.page"
      v-model:page-size="query.size"
      :total="total"
      :page-sizes="[10, 20, 50]"
      layout="total, sizes, prev, pager, next, jumper"
      style="margin-top: 14px; justify-content: flex-end"
      @size-change="loadUsers"
      @current-change="loadUsers"
    />

    <!-- 新增/编辑弹窗 -->
    <el-dialog
      v-model="dialog.visible"
      :title="dialog.mode === 'create' ? '新增用户' : '编辑用户'"
      width="480px"
      destroy-on-close
    >
      <el-form ref="formRef" :model="form" :rules="formRules" label-width="80px">
        <el-form-item label="用户名" prop="username">
          <el-input v-model="form.username" placeholder="登录用户名" />
        </el-form-item>
        <el-form-item label="密码" prop="password">
          <el-input
            v-model="form.password"
            type="password"
            show-password
            :placeholder="dialog.mode === 'create' ? '6-32 位密码' : '留空表示不修改'"
          />
        </el-form-item>
        <el-form-item label="昵称" prop="nickname">
          <el-input v-model="form.nickname" placeholder="显示昵称" />
        </el-form-item>
        <el-form-item label="角色" prop="roleId">
          <el-select v-model="form.roleId" placeholder="请选择角色" style="width: 100%">
            <el-option
              v-for="r in roles"
              :key="r.id"
              :label="r.name"
              :value="r.id"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="状态" prop="status">
          <el-radio-group v-model="form.status">
            <el-radio :value="1">正常</el-radio>
            <el-radio :value="0">禁用</el-radio>
          </el-radio-group>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog.visible = false">取消</el-button>
        <el-button type="primary" :loading="dialog.submitting" @click="submitForm">
          保存
        </el-button>
      </template>
    </el-dialog>

    <!-- 重置密码弹窗 -->
    <el-dialog v-model="pwdDialog.visible" title="重置密码" width="420px">
      <el-form ref="pwdFormRef" :model="pwdForm" :rules="pwdRules" label-width="90px">
        <el-form-item label="用户">
          <span>{{ pwdDialog.username }}</span>
        </el-form-item>
        <el-form-item label="新密码" prop="password">
          <el-input
            v-model="pwdForm.password"
            type="password"
            show-password
            placeholder="6-32 位新密码"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="pwdDialog.visible = false">取消</el-button>
        <el-button type="primary" :loading="pwdDialog.submitting" @click="submitResetPwd">
          确定
        </el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Search, Refresh } from '@element-plus/icons-vue'
import dayjs from 'dayjs'
import { useUserStore } from '@/store/user'
import {
  pageUsers,
  createUser,
  updateUser,
  deleteUser,
  resetPassword
} from '@/api/user'
import { allRoles } from '@/api/role'

const store = useUserStore()

const loading = ref(false)
const rows = ref([])
const total = ref(0)
const roles = ref([])
const query = reactive({ page: 1, size: 10, username: '', roleId: null, status: null })

const dialog = reactive({ visible: false, mode: 'create', submitting: false })
const formRef = ref()
const form = reactive({ id: null, username: '', password: '', nickname: '', roleId: null, status: 1 })

const pwdDialog = reactive({ visible: false, submitting: false, username: '' })
const pwdFormRef = ref()
const pwdForm = reactive({ id: null, password: '' })

function roleName(id) {
  return roles.value.find((r) => r.id === id)?.name
}

function fmtTime(v) {
  return v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-'
}

async function loadUsers() {
  loading.value = true
  try {
    const res = await pageUsers({ ...query })
    rows.value = res.data.records || []
    total.value = Number(res.data.total || 0)
  } finally {
    loading.value = false
  }
}

async function loadRoles() {
  const res = await allRoles()
  roles.value = res.data || []
}

function handleSearch() {
  query.page = 1
  loadUsers()
}

function handleReset() {
  query.username = ''
  query.roleId = null
  query.status = null
  query.page = 1
  loadUsers()
}

const formRules = computed(() => {
  const rules = {
    username: [{ required: true, message: '请输入用户名', trigger: 'blur' }],
    roleId: [{ required: true, message: '请选择角色', trigger: 'change' }],
    status: [{ required: true, message: '请选择状态', trigger: 'change' }]
  }
  if (dialog.mode === 'create') {
    rules.password = [
      { required: true, message: '请输入密码', trigger: 'blur' },
      { min: 6, max: 32, message: '密码长度 6-32 位', trigger: 'blur' }
    ]
  }
  return rules
})

function openCreate() {
  dialog.mode = 'create'
  Object.assign(form, { id: null, username: '', password: '', nickname: '', roleId: null, status: 1 })
  dialog.visible = true
}

function openEdit(row) {
  dialog.mode = 'edit'
  Object.assign(form, {
    id: row.id,
    username: row.username,
    password: '',
    nickname: row.nickname,
    roleId: row.roleId,
    status: row.status
  })
  dialog.visible = true
}

async function submitForm() {
  await formRef.value.validate()
  dialog.submitting = true
  try {
    if (dialog.mode === 'create') {
      await createUser({ ...form })
      ElMessage.success('新增成功')
    } else {
      await updateUser({ ...form })
      ElMessage.success('保存成功')
    }
    dialog.visible = false
    loadUsers()
  } finally {
    dialog.submitting = false
  }
}

async function handleDelete(row) {
  await ElMessageBox.confirm(`确定删除用户「${row.username}」吗?`, '提示', {
    type: 'warning',
    confirmButtonText: '删除',
    cancelButtonText: '取消'
  })
  await deleteUser(row.id)
  ElMessage.success('删除成功')
  loadUsers()
}

const pwdRules = {
  password: [
    { required: true, message: '请输入新密码', trigger: 'blur' },
    { min: 6, max: 32, message: '密码长度 6-32 位', trigger: 'blur' }
  ]
}

function openResetPwd(row) {
  pwdDialog.username = row.username
  pwdForm.id = row.id
  pwdForm.password = ''
  pwdDialog.visible = true
}

async function submitResetPwd() {
  await pwdFormRef.value.validate()
  pwdDialog.submitting = true
  try {
    await resetPassword(pwdForm.id, pwdForm.password)
    ElMessage.success('密码已重置')
    pwdDialog.visible = false
  } finally {
    pwdDialog.submitting = false
  }
}

onMounted(() => {
  loadUsers()
  loadRoles()
})
</script>
