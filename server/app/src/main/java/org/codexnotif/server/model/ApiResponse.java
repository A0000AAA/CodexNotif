package org.codexnotif.server.model;

public record ApiResponse(boolean ok, String message) {
    public static ApiResponse ok(String message) {
        return new ApiResponse(true, message);
    }

    public static ApiResponse fail(String message) {
        return new ApiResponse(false, message);
    }
}
