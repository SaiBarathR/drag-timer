// @ts-check
import { defineConfig } from 'astro/config';
import { rehypeHeadingIds, unified } from '@astrojs/markdown-remark';
import { rehypeDragTimer } from './src/lib/rehype-drag-timer.mjs';
import { codeThemes } from './src/lib/code-themes.mjs';

// GitHub Pages project site: every URL lives under /drag-timer/.
export default defineConfig({
  site: 'https://saibarathr.github.io',
  base: '/drag-timer',
  trailingSlash: 'always',
  // Astro 7's HTML compression drops the space between a line of text and an inline element on the next line.
  compressHTML: false,
  build: { format: 'directory', inlineStylesheets: 'auto' },
  markdown: {
    shikiConfig: {
      themes: codeThemes,
      defaultColor: false,
      wrap: false,
    },
    processor: unified({ rehypePlugins: [rehypeHeadingIds, rehypeDragTimer] }),
  },
  vite: {
    // docs/releases and Packaging/Info.plist live outside site/.
    server: { fs: { allow: ['..'] } },
  },
});
