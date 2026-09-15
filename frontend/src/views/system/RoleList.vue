<template>
  <el-card class="page-card">
    <div class="table-toolbar">
      <el-input
        v-model="query.name"
        placeholder="按角色名称搜索"
        clearable
        style="width: 200px"
        @keyup.enter="handleSearch"
      />
      <el-button type="primary" :icon="Search" @click="handleSearch">查询</el-button>
      <el-button :icon="Refresh" @click="handleReset">重置</el-button>
      <div style="flex: 1"></div>
      <el-button type="primary" :icon="Plus" @click="openCreate">新增角色</el-button>
    </div>

    <el-table v-loading="loading" :data="rows" border stripe>
      <el-table-column prop="id" label="ID" width="70" />
      <el-table-column prop="name" label="角色名称" min-width="140" />
      <el-table-column prop="code" label="角色编码" min-width="140" />
      <el-table-column prop="remark" label="备注" min-width="200" show-overflow-tooltip />
      <el-table-column label="创建时间" width="170">
        <template #default="{ row }">{{ fmtTime(row.createdAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="150" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click="openEdit(row)">编辑</el-button>
          <el-button
            link
            type="danger"
            :disabled="row.code === 'ADMIN'"
            @click="handleDelete(row)"
          >
            删除
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-pagination
      v-model:current-page="query.page"
      v-model:page-size="query.size"
      :total="total"
      :page-sizes="[10, 20, 50]"
      layout="total, sizes, prev, pager, next, jumper"
      style="margin-top: 14px; justify-content: flex-end"
      @size-change="loadRoles"
      @current-change="loadRoles"
    />

    <el-dialog
      v-model="dialog.visible"
      :title="dialog.mode === 'create' ? '新增角色' : '编辑角色'"
      width="460px"
      destroy-on-close
    >
      <el-form ref="formRef" :model="form" :rules="rules" label-width="90px">
        <el-form-item label="角色名称" prop="name">
          <el-input v-model="form.name" placeholder="如: 运营人员" />
        </el-form-item>
        <el-form-item label="角色编码" prop="code">
          <el-input
            v-model="form.code"
            placeholder="大写字母/数字/下划线,如 OPERATOR"
            :disabled="dialog.mode === 'edit' && originalCode === 'ADMIN'"
          />
        </el-form-item>
        <el-form-item label="备注" prop="remark">
          <el-input v-model="form.remark" type="textarea" :rows="3" placeholder="选填" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialog.visible = false">取消</el-button>
        <el-button type="primary" :loading="dialog.submitting" @click="submitForm">
          保存
        </el-button>
      </template>
    </el-dialog>
  </el-card>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Plus, Search, Refresh } from '@element-plus/icons-vue'
import dayjs from 'dayjs'
import { pageRoles, createRole, updateRole, deleteRole } from '@/api/role'

const loading = ref(false)
const rows = ref([])
const total = ref(0)
const query = reactive({ page: 1, size: 10, name: '' })

const dialog = reactive({ visible: false, mode: 'create', submitting: false })
const formRef = ref()
const originalCode = ref('')
const form = reactive({ id: null, name: '', code: '', remark: '' })

const rules = {
  name: [{ required: true, message: '请输入角色名称', trigger: 'blur' }],
  code: [
    { required: true, message: '请输入角色编码', trigger: 'blur' },
    {
      pattern: /^[A-Z][A-Z0-9_]{1,49}$/,
      message: '编码须为大写字母开头,仅含大写字母/数字/下划线(2-50位)',
      trigger: 'blur'
    }
  ]
}

function fmtTime(v) {
  return v ? dayjs(v).format('YYYY-MM-DD HH:mm:ss') : '-'
}

async function loadRoles() {
  loading.value = true
  try {
    const res = await pageRoles({ ...query })
    rows.value = res.data.records || []
    total.value = Number(res.data.total || 0)
  } finally {
    loading.value = false
  }
}

function handleSearch() {
  query.page = 1
  loadRoles()
}

function handleReset() {
  query.name = ''
  query.page = 1
  loadRoles()
}

function openCreate() {
  dialog.mode = 'create'
  originalCode.value = ''
  Object.assign(form, { id: null, name: '', code: '', remark: '' })
  dialog.visible = true
}

function openEdit(row) {
  dialog.mode = 'edit'
  originalCode.value = row.code
  Object.assign(form, { id: row.id, name: row.name, code: row.code, remark: row.remark })
  dialog.visible = true
}

async function submitForm() {
  await formRef.value.validate()
  dialog.submitting = true
  try {
    if (dialog.mode === 'create') {
      await createRole({ ...form })
      ElMessage.success('新增成功')
    } else {
      await updateRole({ ...form })
      ElMessage.success('保存成功')
    }
    dialog.visible = false
    loadRoles()
  } finally {
    dialog.submitting = false
  }
}

async function handleDelete(row) {
  await ElMessageBox.confirm(`确定删除角色「${row.name}」吗?`, '提示', {
    type: 'warning',
    confirmButtonText: '删除',
    cancelButtonText: '取消'
  })
  await deleteRole(row.id)
  ElMessage.success('删除成功')
  loadRoles()
}

onMounted(loadRoles)
</script>
