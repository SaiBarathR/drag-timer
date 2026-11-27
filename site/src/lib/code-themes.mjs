// GitHub's light and dark code themes with their purple tokens (function names, attributes) recoloured to the
// site's coral, so code blocks match the rest of the site.
import githubLight from '@shikijs/themes/github-light';
import githubDark from '@shikijs/themes/github-dark-default';

function recolour(theme, name, map) {
  let json = JSON.stringify(theme);
  for (const [from, to] of Object.entries(map)) json = json.replace(new RegExp(from, 'gi'), to);
  return { ...JSON.parse(json), name };
}

// Comments and green tokens are darkened a little so they keep 4.5:1 contrast on the site's code background.
export const dragLight = recolour(githubLight, 'drag-timer-light', { '#6f42c1': '#a8362b', '#6a737d': '#5b6169', '#22863a': '#1a6e2f', '#d73a49': '#b8293a', '#e36209': '#a84a00' });
export const dragDark = recolour(githubDark, 'drag-timer-dark', { '#d2a8ff': '#ff9a84', '#bc8cff': '#f58a78' });
export const codeThemes = { light: dragLight, dark: dragDark };
