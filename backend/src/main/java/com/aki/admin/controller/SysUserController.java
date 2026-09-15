package com.aki.admin.controller;

import com.aki.admin.common.Result;
import com.aki.admin.dto.PasswordRequest;
import com.aki.admin.dto.SysUserDTO;
import com.aki.admin.entity.SysUser;
import com.aki.admin.service.SysUserService;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 用户管理接口
 */
@RestController
@RequestMapping("/api/users")
public class SysUserController {

    private final SysUserService sysUserService;

    public SysUserController(SysUserService sysUserService) {
        this.sysUserService = sysUserService;
    }

    @GetMapping
    public Result<Page<SysUser>> page(@RequestParam(defaultValue = "1") long page,
                                      @RequestParam(defaultValue = "10") long size,
                                      @RequestParam(required = false) String username,
                                      @RequestParam(required = false) Long roleId,
                                      @RequestParam(required = false) Integer status) {
        return Result.ok(sysUserService.page(page, size, username, roleId, status));
    }

    @GetMapping("/{id}")
    public Result<SysUser> get(@PathVariable Long id) {
        return Result.ok(sysUserService.getById(id));
    }

    @PostMapping
    public Result<Void> create(@Valid @RequestBody SysUserDTO dto) {
        sysUserService.create(dto);
        return Result.ok("新增成功", null);
    }

    @PutMapping
    public Result<Void> update(@Valid @RequestBody SysUserDTO dto) {
        sysUserService.update(dto);
        return Result.ok("保存成功", null);
    }

    @DeleteMapping("/{id}")
    public Result<Void> delete(@PathVariable Long id) {
        sysUserService.delete(id);
        return Result.ok("删除成功", null);
    }

    @PutMapping("/{id}/password")
    public Result<Void> resetPassword(@PathVariable Long id, @Valid @RequestBody PasswordRequest request) {
        sysUserService.resetPassword(id, request.getPassword());
        return Result.ok("密码已重置", null);
    }
}
