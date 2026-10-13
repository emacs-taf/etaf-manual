// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import sidebar from './src/sidebar.mjs';

// The content under src/content/docs and the sidebar module are generated from
// `book/` by scripts/export-site.el; run `npm run export` first (the build and
// dev scripts do).
const wenkai = 'https://cdn.jsdelivr.net/npm/lxgw-wenkai-webfont@1.7.0';

export default defineConfig({
  site: 'https://etaf.top',
  // Astro's smartypants rewrites -- and quotes in headings before ids are
  // generated, which would break anchors referenced by the book sources.
  markdown: { smartypants: false },
  integrations: [
    starlight({
      title: 'ETAF Reference Manual',
      favicon: '/favicon.svg',
      logo: { src: './src/assets/etaf-icon.svg' },
      customCss: ['./src/styles/custom.css'],
      // Chinese text and code render in LXGW WenKai, subset by unicode-range,
      // so a page fetches only the glyph files it uses.
      head: [
        { tag: 'link', attrs: { rel: 'stylesheet', href: `${wenkai}/lxgwwenkai-regular.css` } },
        { tag: 'link', attrs: { rel: 'stylesheet', href: `${wenkai}/lxgwwenkai-bold.css` } },
        { tag: 'link', attrs: { rel: 'stylesheet', href: `${wenkai}/lxgwwenkaimono-regular.css` } },
      ],
      locales: {
        root: { label: 'English', lang: 'en' },
        'zh-cn': { label: '简体中文' },
      },
      sidebar,
    }),
  ],
});
