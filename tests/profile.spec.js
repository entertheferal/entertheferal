import { test, expect } from '@playwright/test';

test.describe('Profile page', () => {
  test.describe('Security tests', () => {
    test('cannot access another member avatar folder via path traversal', async ({ page }) => {
      // Attempt to access avatar with path traversal should fail
      const response = await page.request.get('/avatars/../../../etc/passwd');
      expect(response.status()).toBe(404);
    });

    test('icon must be from allowlist', async ({ page }) => {
      // Icons should only load from images/avatars directory
      await page.goto('/u/testuser');
      await page.waitForLoadState('networkidle');

      // Check that any icon images only come from allowed path
      const iconSrcs = await page.locator('.avatar img.icon').evaluateAll(imgs =>
        imgs.map(img => img.src)
      );
      for (const src of iconSrcs) {
        expect(src).toContain('/images/avatars/');
        expect(src).not.toContain('..');
      }
    });

    test('cover must be from allowlist', async ({ page }) => {
      await page.goto('/u/testuser');
      await page.waitForLoadState('networkidle');

      const coverSrcs = await page.locator('.cover-img').evaluateAll(imgs =>
        imgs.map(img => img.src)
      );
      for (const src of coverSrcs) {
        expect(src).toContain('/images/covers/');
        expect(src).not.toContain('..');
      }
    });
  });

  test.describe('Screenshot tests', () => {
    test('profile page desktop (1280px)', async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await page.goto('/u/testuser');
      await page.waitForLoadState('networkidle');

      // Check no horizontal overflow
      const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
      const viewportWidth = await page.evaluate(() => window.innerWidth);
      expect(bodyWidth).toBeLessThanOrEqual(viewportWidth);

      await expect(page).toHaveScreenshot('profile-desktop.png', {
        fullPage: true,
        maxDiffPixels: 100,
      });
    });

    test('profile page mobile (390px)', async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 844 });
      await page.goto('/u/testuser');
      await page.waitForLoadState('networkidle');

      // Check no horizontal overflow
      const bodyWidth = await page.evaluate(() => document.body.scrollWidth);
      const viewportWidth = await page.evaluate(() => window.innerWidth);
      expect(bodyWidth).toBeLessThanOrEqual(viewportWidth);

      await expect(page).toHaveScreenshot('profile-mobile.png', {
        fullPage: true,
        maxDiffPixels: 100,
      });
    });
  });

  test.describe('Display tests', () => {
    test('displays dual-layer cover effect', async ({ page }) => {
      await page.goto('/u/testuser');
      await page.waitForLoadState('networkidle');

      // Should have two cover images for the dual-layer effect
      const coverImages = await page.locator('.cover .cover-img').count();
      expect(coverImages).toBe(2);

      // Check transforms are applied
      const layer1 = page.locator('.cover-img.cv-layer-1');
      const layer2 = page.locator('.cover-img.cv-layer-2');

      if (await layer1.count() > 0) {
        await expect(layer1).toHaveCSS('transform', /rotate/);
      }
      if (await layer2.count() > 0) {
        await expect(layer2).toHaveCSS('transform', /rotate.*scaleX|scaleX.*rotate/);
      }
    });

    test('role icons use filled circle (mk-event)', async ({ page }) => {
      await page.goto('/u/testuser');
      await page.waitForLoadState('networkidle');

      // If roles exist, they should use mk-event not mk-challenge
      const roleIcons = page.locator('.role .mk');
      const count = await roleIcons.count();

      for (let i = 0; i < count; i++) {
        await expect(roleIcons.nth(i)).toHaveClass(/mk-event/);
        await expect(roleIcons.nth(i)).not.toHaveClass(/mk-challenge/);
      }
    });

    test('no awards placeholder comment in output', async ({ page }) => {
      await page.goto('/u/testuser');
      const html = await page.content();
      expect(html).not.toContain('Awards section will go here');
    });
  });

  test.describe('Account deletion tests', () => {
    test.skip('after account deletion, avatar returns 404', async ({ page, request }) => {
      // This test requires a test account setup
      // Skip in regular runs, enable for integration testing
      const userId = 'deleted-test-user-id';
      const avatarResponse = await request.get(`/avatars/${userId}/avatar.webp`);
      expect(avatarResponse.status()).toBe(404);
    });

    test.skip('after account deletion, profile shows not-found', async ({ page }) => {
      // This test requires a test account setup
      await page.goto('/u/deleted-test-user');
      await expect(page.locator('.notfound')).toBeVisible();
      await expect(page.locator('.notfound h2')).toHaveText('Not found');
    });
  });
});
