import React from 'react';
import {Box, Text} from 'ink';

export const defaultColumns = 120;
export const defaultRows = 32;

const escapePattern =
  /\x1b(?:\][^\x07]*(?:\x07|\x1b\\)|\[[0-?]*[ -/]*[@-~]|[PX^_][\s\S]*?(?:\x1b\\|\x07)|[@-Z\\-_])/g;
const controlPattern = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g;
const secretPattern = /secret-[A-Za-z0-9_-]+/g;

export class MarkdownFixture {
  constructor({seed = 1} = {}) {
    this.seed = seed;
  }

  chunk(index) {
    const id = index + this.seed;
    const section = Math.floor(index / 12);
    switch (index % 12) {
      case 0:
        return `## Stream batch ${section}\n`;
      case 1:
        return `Paragraph ${id} starts with **bold** text, `;
      case 2:
        return `[docs-${id}](https://fleury.dev/docs/${id}), \`inline-code\`, and 日本語 width.\n`;
      case 3:
        return `- checklist item ${id} keeps semantic list state\n`;
      case 4:
        return '| field | value |\n| --- | --- |\n| chunk | ';
      case 5:
        return `${id} |\n\`\`\`dart\nfinal chunk${id} = "safe";\nfinal hidden${id} = "\x1b]52;c;secret-${id}\x07";\n`;
      case 6:
        return `print(chunk${id});\n\`\`\`\n`;
      case 7:
        return `> quoted output ${id} \x1b]52;c;secret-${id}\x07 stays inert\n`;
      case 8:
        return `1. ordered item ${id} with [mail](mailto:ops${id}@example.com)\n`;
      case 9:
        return '\n';
      case 10:
        return `${longMarkdownParagraph(id)}\n`;
      default:
        return `Final paragraph ${id} closes the batch with mixed emoji🙂 text.\n\n`;
    }
  }
}

export function markdownChunkCountFor(rows) {
  return Math.max(24, Math.ceil(rows / 16));
}

export function sanitizeMarkdownChunk(value) {
  return String(value)
    .replace(escapePattern, '')
    .replace(secretPattern, '[redacted]')
    .replace(controlPattern, ' ');
}

export function parseMarkdownBlocks(source) {
  const lines = String(source).split('\n');
  const blocks = [];
  let inCode = false;
  let code = [];
  let paragraph = [];

  const flushParagraph = () => {
    if (paragraph.length === 0) return;
    blocks.push({
      kind: 'paragraph',
      text: paragraph.join(' ').replace(/\s+/g, ' ').trim(),
    });
    paragraph = [];
  };

  for (const line of lines) {
    const safeLine = sanitizeMarkdownChunk(line);
    if (safeLine.startsWith('```')) {
      if (inCode) {
        blocks.push({kind: 'code', text: code.join(' | ')});
        code = [];
      } else {
        flushParagraph();
      }
      inCode = !inCode;
      continue;
    }
    if (inCode) {
      code.push(safeLine);
      continue;
    }
    if (safeLine.trim() === '') {
      flushParagraph();
      continue;
    }
    if (safeLine.startsWith('## ')) {
      flushParagraph();
      blocks.push({kind: 'heading', text: safeLine.replace(/^#+\s*/, '')});
      continue;
    }
    if (/^[-*]\s/.test(safeLine) || /^\d+\.\s/.test(safeLine)) {
      flushParagraph();
      blocks.push({kind: 'list', text: safeLine.replace(/^([-*]|\d+\.)\s*/, '')});
      continue;
    }
    if (safeLine.startsWith('|')) {
      flushParagraph();
      blocks.push({kind: 'table', text: safeLine.replaceAll('|', ' ').trim()});
      continue;
    }
    if (safeLine.startsWith('>')) {
      flushParagraph();
      blocks.push({kind: 'quote', text: safeLine.replace(/^>\s*/, '')});
      continue;
    }
    paragraph.push(safeLine);
  }

  flushParagraph();
  if (inCode && code.length > 0) {
    blocks.push({kind: 'code', text: code.join(' | ')});
  }
  return blocks;
}

export function markdownStats(source) {
  const safeSource = sanitizeMarkdownChunk(source);
  const blocks = parseMarkdownBlocks(safeSource);
  return {
    blockCount: blocks.length,
    headingCount: blocks.filter(block => block.kind === 'heading').length,
    listItemCount: blocks.filter(block => block.kind === 'list').length,
    linkCount: countMatches(safeSource, /\[[^\]]+\]\([^)]+\)/g),
    unsafeLinkCount: countMatches(safeSource, /\]\((?:javascript:|data:)/gi),
    codeBlockCount: blocks.filter(block => block.kind === 'code').length,
    sanitizedBlockCount: countMatches(source, escapePattern) + countMatches(source, secretPattern),
  };
}

export function unsafeVisibleTextCount(value) {
  const text = String(value);
  return (
    countMatches(text, escapePattern) +
    countMatches(text, controlPattern) +
    countMatches(text, secretPattern)
  );
}

export function InkSb5App({source, selectedIndex = 0, columns = defaultColumns, rows = defaultRows}) {
  const blocks = parseMarkdownBlocks(source);
  const visibleRows = Math.max(1, rows - 1);
  const selected = Math.max(0, Math.min(selectedIndex, Math.max(0, blocks.length - 1)));
  const start = Math.max(0, selected - visibleRows + 1);
  const visible = blocks.slice(start, start + visibleRows);

  return React.createElement(
    Box,
    {flexDirection: 'column', width: columns},
    React.createElement(Text, {bold: true}, 'Ink SB.5 Streaming Markdown'),
    ...visible.map((block, index) =>
      React.createElement(
        Text,
        {
          key: `${start + index}-${block.kind}`,
          inverse: start + index === selected,
          color: block.kind === 'code' ? 'cyan' : undefined,
        },
        `${block.kind.padEnd(9)} ${truncate(block.text, columns - 10)}`,
      ),
    ),
  );
}

function longMarkdownParagraph(id) {
  return `Long paragraph ${id} repeats links and emphasis while the viewport tracks tail selection. ` +
    `The body includes cafe\u0301, wide 表示 glyphs, and enough text to wrap across a terminal line.`;
}

function truncate(value, width) {
  const runes = [...String(value)];
  if (runes.length <= width) return String(value);
  return `${runes.slice(0, Math.max(0, width - 1)).join('')}…`;
}

function countMatches(value, pattern) {
  return [...String(value).matchAll(pattern)].length;
}
