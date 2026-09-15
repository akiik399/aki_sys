package com.aki.admin.service;

import com.aki.admin.common.BusinessException;
import com.aki.admin.dto.SysUserDTO;
import com.aki.admin.entity.SysUser;
import com.aki.admin.mapper.SysUserMapper;
import com.aki.admin.security.UserContext;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

/**
 * 用户管理服务
 */
@Service
public class SysUserService {

    private final SysUserMapper sysUserMapper;
    private final PasswordEncoder passwordEncoder;

    public SysUserService(SysUserMapper sysUserMapper, PasswordEncoder passwordEncoder) {
        this.sysUserMapper = sysUserMapper;
        this.passwordEncoder = passwordEncoder;
    }

    /**
     * 分页查询用户(密码已 @JsonIgnore 不会泄露)
     */
    public Page<SysUser> page(long page, long size, String username, Long roleId, Integer status) {
        LambdaQueryWrapper<SysUser> wrapper = new LambdaQueryWrapper<>();
        if (StringUtils.hasText(username)) {
            wrapper.like(SysUser::getUsername, username);
        }
        if (roleId != null) {
            wrapper.eq(SysUser::getRoleId, roleId);
        }
        if (status != null) {
            wrapper.eq(SysUser::getStatus, status);
        }
        wrapper.orderByDesc(SysUser::getId);
        return sysUserMapper.selectPage(new Page<>(page, size), wrapper);
    }

    public SysUser getById(Long id) {
        SysUser user = sysUserMapper.selectById(id);
        if (user == null) {
            throw new BusinessException("用户不存在");
        }
        return user;
    }

    /**
     * 新增用户
     */
    public void create(SysUserDTO dto) {
        if (!StringUtils.hasText(dto.getPassword())) {
            throw new BusinessException("新增用户必须设置密码");
        }
        checkUsernameUnique(dto.getUsername(), null);
        SysUser user = new SysUser();
        user.setUsername(dto.getUsername());
        user.setPassword(passwordEncoder.encode(dto.getPassword()));
        user.setNickname(dto.getNickname());
        user.setRoleId(dto.getRoleId());
        user.setStatus(dto.getStatus());
        sysUserMapper.insert(user);
    }

    /**
     * 编辑用户
     */
    public void update(SysUserDTO dto) {
        if (dto.getId() == null) {
            throw new BusinessException("缺少用户 ID");
        }
        SysUser exist = sysUserMapper.selectById(dto.getId());
        if (exist == null) {
            throw new BusinessException("用户不存在");
        }
        checkUsernameUnique(dto.getUsername(), dto.getId());
        exist.setUsername(dto.getUsername());
        exist.setNickname(dto.getNickname());
        exist.setRoleId(dto.getRoleId());
        exist.setStatus(dto.getStatus());
        if (StringUtils.hasText(dto.getPassword())) {
            exist.setPassword(passwordEncoder.encode(dto.getPassword()));
        }
        sysUserMapper.updateById(exist);
    }

    /**
     * 删除用户(禁止删除自己)
     */
    public void delete(Long id) {
        if (id.equals(UserContext.getUserId())) {
            throw new BusinessException("不能删除当前登录账号");
        }
        if (sysUserMapper.selectById(id) == null) {
            throw new BusinessException("用户不存在");
        }
        sysUserMapper.deleteById(id);
    }

    /**
     * 重置密码
     */
    public void resetPassword(Long id, String rawPassword) {
        SysUser user = sysUserMapper.selectById(id);
        if (user == null) {
            throw new BusinessException("用户不存在");
        }
        user.setPassword(passwordEncoder.encode(rawPassword));
        sysUserMapper.updateById(user);
    }

    private void checkUsernameUnique(String username, Long excludeId) {
        LambdaQueryWrapper<SysUser> wrapper = new LambdaQueryWrapper<SysUser>()
                .eq(SysUser::getUsername, username);
        if (excludeId != null) {
            wrapper.ne(SysUser::getId, excludeId);
        }
        if (sysUserMapper.selectCount(wrapper) > 0) {
            throw new BusinessException("用户名已存在: " + username);
        }
    }
}
