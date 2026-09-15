import request from './request'

export function pageRoles(params) {
  return request.get('/roles', { params })
}

export function allRoles() {
  return request.get('/roles/all')
}

export function createRole(data) {
  return request.post('/roles', data)
}

export function updateRole(data) {
  return request.put('/roles', data)
}

export function deleteRole(id) {
  return request.delete(`/roles/${id}`)
}
