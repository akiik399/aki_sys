package com.aki.admin.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 用户新增/编辑请求
 */
public class SysUserDTO {

    private Long id;

    @NotBlank(message = "用户名不能为空")
    @Size(max = 50, message = "用户名最长 50 个字符")
    private String username;

    /** 新增时必填,编辑时留空表示不修改 */
    @Size(min = 6, max = 32, message = "密码长度 6-32 位")
    private String password;

    @Size(max = 50, message = "昵称最长 50 个字符")
    private String nickname;

    @NotNull(message = "请选择角色")
    private Long roleId;

    @NotNull(message = "请选择状态")
    private Integer status;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getNickname() {
        return nickname;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
    }

    public Long getRoleId() {
        return roleId;
    }

    public void setRoleId(Long roleId) {
        this.roleId = roleId;
    }

    public Integer getStatus() {
        return status;
    }

    public void setStatus(Integer status) {
        this.status = status;
    }
}
