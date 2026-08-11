package org.codexnotif.server.model;

public record BindStatusResponse(
        String status,
        String deviceToken,
        String email
) {
    public static BindStatusResponse pending(String email) {
        return new BindStatusResponse("pending", null, email);
    }

    public static BindStatusResponse bound(String token, String email) {
        return new BindStatusResponse("bound", token, email);
    }
}
