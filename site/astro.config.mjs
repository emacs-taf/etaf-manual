// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import sidebar from './src/sidebar.mjs';

// The content under src/content/docs and the sidebar module are generated from
// `book/` by scripts/export-site.el; run `npm run export` first (the build and
// dev scripts do).
export default defineConfig({
  site: 'https://etaf.top',
  // Astro's smartypants rewrites -- and quotes in headings before ids are
  // generated, which would break anchors referenced by the book sources.
  markdown: { smartypants: false },
  integrations: [
    starlight({
      title: 'ETAF Reference Manual',
      favicon: '/favicon.svg',
      locales: {
        root: { label: 'English', lang: 'en' },
        'zh-cn': { label: '简体中文' },
      },
      sidebar,
    }),
  ],
});
