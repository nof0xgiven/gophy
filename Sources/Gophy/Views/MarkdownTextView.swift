import SwiftUI

/// A view that renders markdown text with proper block-level formatting
/// (headings, bullet lists, numbered lists, paragraphs, code blocks).
@MainActor
struct MarkdownTextView: View {
    let text: String
    var font: Font = .callout
    var foregroundStyle: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(inlineMarkdown(content))
                .font(headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? 4 : 2)

        case .bullet(let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\u{2022}")
                    .font(font)
                    .foregroundStyle(foregroundStyle)
                Text(inlineMarkdown(content))
                    .font(font)
                    .foregroundStyle(foregroundStyle)
            }

        case .numbered(let num, let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(num).")
                    .font(font)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                Text(inlineMarkdown(content))
                    .font(font)
                    .foregroundStyle(foregroundStyle)
            }

        case .codeBlock(let code):
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(foregroundStyle)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .cornerRadius(6)

        case .paragraph(let content):
            Text(inlineMarkdown(content))
                .font(font)
                .foregroundStyle(foregroundStyle)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3
        case 2: return .headline
        case 3: return .subheadline
        default: return font
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Markdown Block Parser

private enum MarkdownBlock {
    case heading(Int, String)
    case bullet(String)
    case numbered(Int, String)
    case codeBlock(String)
    case paragraph(String)
}

private func parseBlocks(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0
    var paragraphLines: [String] = []

    func flushParagraph() {
        let joined = paragraphLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !joined.isEmpty {
            blocks.append(.paragraph(joined))
        }
        paragraphLines.removeAll()
    }

    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Empty line — flush paragraph
        if trimmed.isEmpty {
            flushParagraph()
            i += 1
            continue
        }

        // Code block
        if trimmed.hasPrefix("```") {
            flushParagraph()
            var codeLines: [String] = []
            i += 1
            while i < lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    i += 1
                    break
                }
                codeLines.append(lines[i])
                i += 1
            }
            blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
            continue
        }

        // Heading
        if let match = trimmed.firstMatch(of: /^(#{1,4})\s+(.+)/) {
            flushParagraph()
            let level = match.1.count
            let content = String(match.2)
            blocks.append(.heading(level, content))
            i += 1
            continue
        }

        // Bullet list
        if let match = trimmed.firstMatch(of: /^[-*+]\s+(.+)/) {
            flushParagraph()
            blocks.append(.bullet(String(match.1)))
            i += 1
            continue
        }

        // Numbered list
        if let match = trimmed.firstMatch(of: /^(\d+)[.)]\s+(.+)/) {
            flushParagraph()
            let num = Int(match.1) ?? 1
            blocks.append(.numbered(num, String(match.2)))
            i += 1
            continue
        }

        // Regular text — accumulate for paragraph
        paragraphLines.append(trimmed)
        i += 1
    }

    flushParagraph()
    return blocks
}
