import { defineConfig } from 'vitest/config';
import { vitestCiLowMemory } from '../../vitest.ci-low-memory';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    ...vitestCiLowMemory(),
  },
});
