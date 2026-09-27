// @ts-check
const { defineConfig, devices } = require('@playwright/test');

const PORT = 4173;
// BASE_URL permite correr la suite contra un despliegue (p. ej. producción en Vercel).
const BASE_URL = process.env.BASE_URL;

module.exports = defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: [['html', { open: 'never' }], ['list']],
  use: {
    baseURL: BASE_URL ?? `http://127.0.0.1:${PORT}`,
    trace: 'retain-on-failure',
    screenshot: 'on',
  },
  projects: [
    { name: 'chromium-375', use: { ...devices['Desktop Chrome'], viewport: { width: 375, height: 800 } } },
    { name: 'chromium-1440', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
  ],
  webServer: BASE_URL ? undefined : {
    command: `python3 -m http.server ${PORT} --bind 127.0.0.1`,
    url: `http://127.0.0.1:${PORT}/index.html`,
    reuseExistingServer: !process.env.CI,
  },
});
