package com.aki.admin.common;

/**
 * 统一响应结果
 */
public class Result<T> {

    public static final int CODE_OK = 200;
    public static final int CODE_BAD = 500;
    public static final int CODE_UNAUTHORIZED = 401;

    private int code;
    private String msg;
    private T data;

    public Result() {
    }

    public Result(int code, String msg, T data) {
        this.code = code;
        this.msg = msg;
        this.data = data;
    }

    public static <T> Result<T> ok() {
        return new Result<>(CODE_OK, "操作成功", null);
    }

    public static <T> Result<T> ok(T data) {
        return new Result<>(CODE_OK, "操作成功", data);
    }

    public static <T> Result<T> ok(String msg, T data) {
        return new Result<>(CODE_OK, msg, data);
    }

    public static <T> Result<T> error(String msg) {
        return new Result<>(CODE_BAD, msg, null);
    }

    public static <T> Result<T> error(int code, String msg) {
        return new Result<>(code, msg, null);
    }

    public int getCode() {
        return code;
    }

    public void setCode(int code) {
        this.code = code;
    }

    public String getMsg() {
        return msg;
    }

    public void setMsg(String msg) {
        this.msg = msg;
    }

    public T getData() {
        return data;
    }

    public void setData(T data) {
        this.data = data;
    }
}
