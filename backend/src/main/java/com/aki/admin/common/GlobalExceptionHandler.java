package com.aki.admin.common;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * 全局异常处理
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(BusinessException.class)
    public Result<Void> handleBusiness(BusinessException e) {
        return Result.error(e.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public Result<Void> handleValidation(MethodArgumentNotValidException e) {
        FieldError fieldError = e.getBindingResult().getFieldError();
        String msg = fieldError != null ? fieldError.getDefaultMessage() : "参数校验失败";
        return Result.error(400, msg);
    }

    /**
     * 路径没匹配到任何控制器时的兜底(Spring 6.1 的 NoResourceFoundException)。
     * 不加这个分支的话,它会被下面的 handleException(Exception) 吞成 "系统异常" + 500,
     * 既掩盖真实原因(其实只是接口不存在/路径写错),又会在日志里刷一整条无意义的堆栈。
     * 放在 handleException 之前由 Spring 按最具体类型匹配,不影响其它异常分支。
     */
    @ExceptionHandler(NoResourceFoundException.class)
    public Result<Void> handleNoResource(NoResourceFoundException e) {
        return Result.error(404, "接口不存在: " + e.getResourcePath());
    }

    /**
     * 依赖服务(Redis / 数据库)不可用。
     *
     * 不加这个分支的话,Redis 挂掉时会被兜底成
     *   "系统异常: Error in execution"  或  "token 无效或已过期"
     * —— 前者看不出是 Redis,后者更糟:它把"登录态服务不可用"说成"你的 token 有问题",
     * 排查方向会被直接带偏(本项目真踩过:Redis 存不了盘导致登录全线失败,
     * 报的却是 token 相关错误)。
     *
     * 返回 503(服务不可用)而不是 500,语义上更准确:这不是代码 bug,是依赖故障。
     */
    @ExceptionHandler(DataAccessException.class)
    public Result<Void> handleDataAccess(DataAccessException e) {
        log.error("数据访问依赖不可用(Redis / 数据库)", e);
        return Result.error(503, "服务依赖暂时不可用(Redis / 数据库),请稍后重试");
    }

    @ExceptionHandler(Exception.class)
    public Result<Void> handleException(Exception e) {
        log.error("系统异常", e);
        return Result.error("系统异常: " + e.getMessage());
    }
}
