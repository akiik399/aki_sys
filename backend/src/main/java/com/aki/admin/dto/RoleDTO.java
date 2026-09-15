package com.aki.admin.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 角色新增/编辑请求
 */
public class RoleDTO {

    private Long id;

    @NotBlank(message = "角色名称不能为空")
    @Size(max = 50, message = "角色名称最长 50 个字符")
    private String name;

    @NotBlank(message = "角色编码不能为空")
    @Pattern(regexp = "^[A-Z][A-Z0-9_]{1,49}$", message = "角色编码须为大写字母/数字/下划线(2-50位)")
    private String code;

    @Size(max = 200, message = "备注最长 200 个字符")
    private String remark;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getCode() {
        return code;
    }

    public void setCode(String code) {
        this.code = code;
    }

    public String getRemark() {
        return remark;
    }

    public void setRemark(String remark) {
        this.remark = remark;
    }
}
