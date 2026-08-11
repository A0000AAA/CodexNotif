package org.codexnotif.mobile;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public class BundledSoundResolverTest {
    @Test
    public void resolvesRawResourceOwnedByThisApp() {
        assertEquals(
                "tone_hajimi",
                BundledSoundResolver.resourceNameFor(
                        "android.resource://org.codexnotif.mobile/raw/tone_hajimi",
                        "org.codexnotif.mobile"
                )
        );
    }

    @Test
    public void rejectsResourcesOwnedByAnotherPackage() {
        assertNull(
                BundledSoundResolver.resourceNameFor(
                        "android.resource://another.app/raw/tone_phone",
                        "org.codexnotif.mobile"
                )
        );
    }

    @Test
    public void rejectsContentUris() {
        assertNull(
                BundledSoundResolver.resourceNameFor(
                        "content://media/external/audio/1",
                        "org.codexnotif.mobile"
                )
        );
    }

    @Test
    public void rejectsUnknownBundledResourceNames() {
        assertNull(
                BundledSoundResolver.resourceNameFor(
                        "android.resource://org.codexnotif.mobile/raw/not_packaged",
                        "org.codexnotif.mobile"
                )
        );
    }
}
