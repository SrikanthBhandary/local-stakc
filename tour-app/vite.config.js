import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  base: './', // relative asset paths — needed for path-style S3 URLs like /item-backup/index.html
  build: {
    outDir: 'dist'
  }
});
