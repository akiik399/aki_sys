package com.aki.admin.initializer;

import com.aki.admin.entity.SysRole;
import com.aki.admin.entity.SysUser;
import com.aki.admin.mapper.SysRoleMapper;
import com.aki.admin.mapper.SysUserMapper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * 首次启动初始化内置角色与管理员账号(幂等)
 * 管理员账号: admin / admin123
 */
@Component
public class DataInitializer implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DataInitializer.class);

    private final SysRoleMapper sysRoleMapper;
    private final SysUserMapper sysUserMapper;
    private final PasswordEncoder passwordEncoder;

    public DataInitializer(SysRoleMapper sysRoleMapper, SysUserMapper sysUserMapper,
                           PasswordEncoder passwordEncoder) {
        this.sysRoleMapper = sysRoleMapper;
        this.sysUserMapper = sysUserMapper;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public void run(ApplicationArguments args) {
        initRoles();
        initAdmin();
    }

    private void initRoles() {
        if (sysRoleMapper.selectCount(null) > 0) {
            return;
        }
        SysRole admin = new SysRole();
        admin.setName("超级管理员");
        admin.setCode("ADMIN");
        admin.setRemark("系统内置,拥有全部权限");
        sysRoleMapper.insert(admin);

        SysRole user = new SysRole();
        user.setName("普通用户");
        user.setCode("USER");
        user.setRemark("普通业务用户");
        sysRoleMapper.insert(user);

        log.info("[初始化] 内置角色 ADMIN / USER 创建完成");
    }

    private void initAdmin() {
        if (sysUserMapper.selectCount(null) > 0) {
            return;
        }
        SysRole adminRole = sysRoleMapper.selectOne(
                new LambdaQueryWrapper<SysRole>().eq(SysRole::getCode, "ADMIN"));
        SysUser admin = new SysUser();
        admin.setUsername("admin");
        admin.setPassword(passwordEncoder.encode("admin123"));
        admin.setNickname("系统管理员");
        admin.setRoleId(adminRole != null ? adminRole.getId() : null);
        admin.setStatus(1);
        sysUserMapper.insert(admin);
        log.info("[初始化] 管理员账号创建完成: admin / admin123");
    }
}
