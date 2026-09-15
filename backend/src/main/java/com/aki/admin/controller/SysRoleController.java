package com.aki.admin.controller;

import com.aki.admin.common.Result;
import com.aki.admin.dto.RoleDTO;
import com.aki.admin.entity.SysRole;
import com.aki.admin.service.SysRoleService;
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

import java.util.List;

/**
 * 角色管理接口
 */
@RestController
@RequestMapping("/api/roles")
public class SysRoleController {

    private final SysRoleService sysRoleService;

    public SysRoleController(SysRoleService sysRoleService) {
        this.sysRoleService = sysRoleService;
    }

    @GetMapping
    public Result<Page<SysRole>> page(@RequestParam(defaultValue = "1") long page,
                                      @RequestParam(defaultValue = "10") long size,
                                      @RequestParam(required = false) String name) {
        return Result.ok(sysRoleService.page(page, size, name));
    }

    @GetMapping("/all")
    public Result<List<SysRole>> all() {
        return Result.ok(sysRoleService.listAll());
    }

    @PostMapping
    public Result<Void> create(@Valid @RequestBody RoleDTO dto) {
        sysRoleService.create(dto);
        return Result.ok("新增成功", null);
    }

    @PutMapping
    public Result<Void> update(@Valid @RequestBody RoleDTO dto) {
        sysRoleService.update(dto);
        return Result.ok("保存成功", null);
    }

    @DeleteMapping("/{id}")
    public Result<Void> delete(@PathVariable Long id) {
        sysRoleService.delete(id);
        return Result.ok("删除成功", null);
    }
}
