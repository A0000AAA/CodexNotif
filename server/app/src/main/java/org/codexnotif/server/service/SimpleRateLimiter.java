package org.codexnotif.server.service;

import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class SimpleRateLimiter {

    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();

    public boolean allow(String key, int maxRequests, long windowSeconds) {
        long now = Instant.now().getEpochSecond();

        Bucket bucket = buckets.compute(key, (ignored, current) -> {
            if (current == null || now - current.windowStart >= windowSeconds) {
                return new Bucket(now, 1);
            }

            current.count++;
            return current;
        });

        return bucket.count <= maxRequests;
    }

    private static final class Bucket {
        private final long windowStart;
        private int count;

        private Bucket(long windowStart, int count) {
            this.windowStart = windowStart;
            this.count = count;
        }
    }
}
