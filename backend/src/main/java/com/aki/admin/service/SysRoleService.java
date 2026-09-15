package com.aki.admin.service;

import com.aki.admin.common.BusinessException;
import com.aki.admin.dto.RoleDTO;
import com.aki.admin.entity.SysRole;
import com.aki.admin.entity.SysUser;
import com.aki.admin.mapper.SysRoleMapper;
import com.aki.admin.mapper.SysUserMapper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.List;

/**
 * 角色管理服务
 */
@Service
public class SysRoleService {

    private final SysRoleMapper sysRoleMapper;
    private final SysUserMapper sysUserMapper;

    public SysRoleService(SysRoleMapper sysRoleMapper, SysUserMapper sysUserMapper) {
        this.sysRoleMapper = sysRoleMapper;
        this.sysUserMapper = sysUserMapper;
    }

    public Page<SysRole> page(long page, long size, String name) {
        LambdaQueryWrapper<SysRole> wrapper = new LambdaQueryWrapper<>();
        if (StringUtils.hasText(name)) {
            wrapper.like(SysRole::getName, name);
        }
        wrapper.orderByAsc(SysRole::getId);
        return sysRoleMapper.selectPage(new Page<>(page, size), wrapper);
    }

    /**
     * 全部角色(用于下拉框)
     */
    public List<SysRole> listAll() {
        return sysRoleMapper.selectList(new LambdaQueryWrapper<SysRole>().orderByAsc(SysRole::getId));
    }

    public void create(RoleDTO dto) {
        checkCodeUnique(dto.getCode(), null);
        SysRole role = new SysRole();
        role.setName(dto.getName());
        role.setCode(dto.getCode());
        role.setRemark(dto.getRemark());
        sysRoleMapper.insert(role);
    }

    public void update(RoleDTO dto) {
        if (dto.getId() == null) {
            throw new BusinessException("缺少角色 ID");
        }
        SysRole exist = sysRoleMapper.selectById(dto.getId());
        if (exist == null) {
            throw new BusinessException("角色不存在");
        }
        checkCodeUnique(dto.getCode(), dto.getId());
        exist.setName(dto.getName());
        exist.setCode(dto.getCode());
        exist.setRemark(dto.getRemark());
        sysRoleMapper.updateById(exist);
    }

    public void delete(Long id) {
        SysRole role = sysRoleMapper.selectById(id);
        if (role == null) {
            throw new BusinessException("角色不存在");
        }
        if ("ADMIN".equals(role.getCode())) {
            throw new BusinessException("系统内置角色不允许删除");
        }
        Long used = sysUserMapper.selectCount(
                new LambdaQueryWrapper<SysUser>().eq(SysUser::getRoleId, id));
        if (used != null && used > 0) {
            throw new BusinessException("仍有 " + used + " 个用户使用该角色,无法删除");
        }
        sysRoleMapper.deleteById(id);
    }

    private void checkCodeUnique(String code, Long excludeId) {
        LambdaQueryWrapper<SysRole> wrapper = new LambdaQueryWrapper<SysRole>()
                .eq(SysRole::getCode, code);
        if (excludeId != null) {
            wrapper.ne(SysRole::getId, excludeId);
        }
        if (sysRoleMapper.selectCount(wrapper) > 0) {
            throw new BusinessException("角色编码已存在: " + code);
        }
    }
}
