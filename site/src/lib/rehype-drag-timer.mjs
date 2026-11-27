// Rehype plugin for every Markdown file the site renders (docs/releases/*.md and the guides):
//  - adds a "#" anchor link to h2–h4 (ids come from rehypeHeadingIds, which runs first)
//  - in release notes, demotes headings by one level (their "# Drag Timer 1.7.0" sits under the page's h1) and
//    prefixes heading ids with the version, so "Highlights" in two releases doesn't produce the same id twice
//  - points relative links to repository files at GitHub
//  - makes tables scroll horizontally on narrow screens instead of overflowing
const REPO = 'https://github.com/SaiBarathR/drag-timer/blob/main/';

function walk(node, fn, parent = null, index = 0) {
  fn(node, parent, index);
  if (node.children) {
    // copy: fn may replace children
    node.children.slice().forEach((child) => walk(child, fn, node, node.children.indexOf(child)));
  }
}

export function rehypeDragTimer() {
  return (tree, file) => {
    const path = String(file?.path || file?.history?.[0] || '');
    const release = path.match(/[\\/]docs[\\/]releases[\\/](v[^\\/]+)\.md$/)?.[1];
    const sourceDir = release ? 'docs/releases/' : '';

    walk(tree, (node, parent, index) => {
      if (node.type !== 'element') return;

      if (release && /^h[1-5]$/.test(node.tagName)) {
        node.tagName = 'h' + (Number(node.tagName[1]) + 1);
        if (node.properties?.id) node.properties.id = `${release}-${node.properties.id}`;
      }

      if (/^h[2-4]$/.test(node.tagName) && node.properties?.id) {
        node.children.push({
          type: 'element',
          tagName: 'a',
          properties: { className: ['anchor'], href: '#' + node.properties.id, ariaLabel: 'Link to this section' },
          children: [{ type: 'text', value: '#' }],
        });
      }

      if (node.tagName === 'a' && typeof node.properties?.href === 'string') {
        const href = node.properties.href;
        if (/^[a-z]+:/i.test(href) || href.startsWith('#') || href.startsWith('/')) {
          if (/^https?:/i.test(href)) node.properties.rel = ['noopener'];
          return;
        }
        const [target, hash = ''] = href.split('#');
        const clean = new URL(target, 'https://x/' + sourceDir).pathname.slice(1);
        node.properties.href = REPO + clean + (hash ? '#' + hash : '');
      }

      if (node.tagName === 'img' && node.properties) {
        node.properties.loading = 'lazy';
        node.properties.decoding = 'async';
      }

      if (node.tagName === 'table' && parent && parent.tagName !== 'div') {
        parent.children[index] = {
          type: 'element',
          tagName: 'div',
          properties: { className: ['table-wrap'], tabIndex: 0 },
          children: [node],
        };
      }
    });
  };
}
