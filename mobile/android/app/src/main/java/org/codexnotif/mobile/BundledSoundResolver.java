package org.codexnotif.mobile;

import java.net.URI;
import java.net.URISyntaxException;

final class BundledSoundResolver {
    private BundledSoundResolver() {
    }

    static String resourceNameFor(String rawUri, String packageName) {
        if (rawUri == null || rawUri.isEmpty() || packageName == null) {
            return null;
        }

        try {
            final URI uri = new URI(rawUri);
            if (!"android.resource".equals(uri.getScheme()) ||
                    !packageName.equals(uri.getAuthority())) {
                return null;
            }

            final String path = uri.getPath();
            if (path == null) return null;

            final String[] segments = path.split("/");
            if (segments.length != 3 || !"raw".equals(segments[1])) {
                return null;
            }

            final String name = segments[2];
            switch (name) {
                case "tone_alert":
                case "tone_chime":
                case "tone_hajimi":
                case "tone_phone":
                case "tone_soft":
                    return name;
                default:
                    return null;
            }
        } catch (URISyntaxException error) {
            return null;
        }
    }
}
