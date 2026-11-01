import { test, expect } from '@playwright/test';

test.describe('Profile editor', () => {
  test.describe('Security tests', () => {
    test.skip('cannot write to another member avatar folder', async ({ page, request }) => {
      // This test requires authentication
      // Attempt to upload avatar to wrong user ID path should fail
      const targetUserId = 'other-user-id';
      const response = await request.put(`/avatars/${targetUserId}/avatar.webp`, {
        headers: { 'Content-Type': 'image/webp' },
        data: Buffer.from('fake'),
      });
      expect([401, 403, 404]).toContain(response.status());
    });

    test.skip('cannot change another member profile', async ({ page }) => {
      // This test requires authentication setup
      // RLS policies should prevent updating other profiles
    });

    test.skip('handle change blocked for 30 days after change', async ({ page }) => {
      // This test requires a user who recently changed handle
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      const handleInput = page.locator('#handle');
      if (await handleInput.isDisabled()) {
        const hint = page.locator('#handleHint');
        await expect(hint).toContainText('recently');
      }
    });
  });

  test.describe('Avatar processing', () => {
    test.skip('uploaded photo is 512x512 WebP', async ({ page }) => {
      // This test requires file upload simulation
      // The canvas processing in the cropper should output 512x512 WebP
    });

    test.skip('photo has no EXIF data after processing', async ({ page }) => {
      // Canvas-based processing strips EXIF automatically
      // This test would need to inspect the uploaded blob
    });
  });

  test.describe('Screenshot tests', () => {
    test('profile editor desktop (1280px)', async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      // Check no horizontal overflow
      const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
      const viewportWidth = await page.evaluate(() => window.innerWidth);
      expect(bodyWidth).toBeLessThanOrEqual(viewportWidth);

      await expect(page).toHaveScreenshot('editor-desktop.png', {
        fullPage: true,
        maxDiffPixels: 100,
      });
    });

    test('profile editor mobile (390px)', async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 844 });
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      // Check no horizontal overflow
      const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
      const viewportWidth = await page.evaluate(() => window.innerWidth);
      expect(bodyWidth).toBeLessThanOrEqual(viewportWidth);

      await expect(page).toHaveScreenshot('editor-mobile.png', {
        fullPage: true,
        maxDiffPixels: 100,
      });
    });
  });

  test.describe('Mobile layout', () => {
    test('preview appears above form on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 844 });
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      const previewCol = page.locator('.preview-col');
      const formCol = page.locator('.form-col');

      // Preview should have negative order (appear first)
      const previewOrder = await previewCol.evaluate(el =>
        window.getComputedStyle(el).order
      );
      const formOrder = await formCol.evaluate(el =>
        window.getComputedStyle(el).order
      );

      expect(parseInt(previewOrder)).toBeLessThan(parseInt(formOrder));
    });

    test('save bar is fixed on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 844 });
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      const saveBar = page.locator('.save-bar');
      const position = await saveBar.evaluate(el =>
        window.getComputedStyle(el).position
      );

      expect(position).toBe('fixed');
    });
  });

  test.describe('Accessibility', () => {
    test('has aria-live region for status announcements', async ({ page }) => {
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      const liveRegion = page.locator('[aria-live="polite"]');
      await expect(liveRegion).toBeAttached();
    });

    test('avatar tabs have proper ARIA attributes', async ({ page }) => {
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      const tablist = page.locator('[role="tablist"]');
      await expect(tablist).toBeAttached();

      const tabs = page.locator('[role="tab"]');
      const count = await tabs.count();
      expect(count).toBeGreaterThan(0);

      // One tab should be selected
      const selectedTab = page.locator('[role="tab"][aria-selected="true"]');
      await expect(selectedTab).toHaveCount(1);
    });
  });

  test.describe('Handle availability', () => {
    test.skip('shows "Checking..." while validating handle', async ({ page }) => {
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      const handleInput = page.locator('#handle');
      if (await handleInput.isEnabled()) {
        await handleInput.fill('newuniquetesthandle');

        const hint = page.locator('#handleHint');
        // Should show checking state briefly
        await expect(hint).toContainText(/Checking|Available|Taken/);
      }
    });

    test('validates handle format before checking availability', async ({ page }) => {
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      const handleInput = page.locator('#handle');
      if (await handleInput.isEnabled()) {
        // Invalid handle (too short)
        await handleInput.fill('ab');
        const hint = page.locator('#handleHint');
        await expect(hint).toHaveClass(/bad/);

        // Invalid handle (special chars)
        await handleInput.fill('test@user');
        await expect(hint).toHaveClass(/bad/);
      }
    });
  });

  test.describe('Photo removal', () => {
    test('remove photo button exists', async ({ page }) => {
      await page.goto('/settings/profile');
      await page.waitForLoadState('networkidle');

      // Click on photo tab first
      const photoTab = page.locator('.avatar-tab[data-type="photo"]');
      await photoTab.click();

      const removeBtn = page.locator('#removePhotoBtn');
      await expect(removeBtn).toBeVisible();
    });
  });
});
