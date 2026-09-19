#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require "uri"

ROOT = Pathname.new(__dir__).parent.realpath
tracked_markdown = IO.popen(
  ["git", "-C", ROOT.to_s, "ls-files", "-z", "--", "*.md"],
  &:read
).split("\0").reject(&:empty?).map { |path| ROOT.join(path) }
MARKDOWN_FILES = (tracked_markdown + [ROOT.join("README.md")] + ROOT.join("docs").glob("**/*.md")).uniq.sort.freeze

def github_anchor(text)
  text
    .gsub(/<[^>]*>/, "")
    .gsub(/[`*_~]/, "")
    .downcase
    .gsub(/[^\p{L}\p{N}\s-]/, "")
    .tr(" ", "-")
end

def anchors_for(path)
  anchors = []
  duplicates = Hash.new(0)
  fenced = false
  details_depth = 0

  path.each_line do |line|
    if line.match?(/^\s*(```|~~~)/)
      fenced = !fenced
      next
    end
    next if fenced

    details_depth += line.scan(/<details(?:\s[^>]*)?>/i).length
    details_depth -= line.scan(%r{</details>}i).length
    next unless details_depth.zero?

    match = line.match(/^\s{0,3}\#{1,6}\s+(.+?)\s*\#*\s*$/)
    next unless match

    base = github_anchor(match[1])
    suffix = duplicates[base].zero? ? "" : "-#{duplicates[base]}"
    anchors << "#{base}#{suffix}"
    duplicates[base] += 1
  end

  anchors
end

anchor_cache = MARKDOWN_FILES.to_h { |path| [path, anchors_for(path)] }
errors = []

MARKDOWN_FILES.each do |source|
  fenced = false
  source.each_line.with_index(1) do |line, line_number|
    if line.match?(/^\s*(```|~~~)/)
      fenced = !fenced
      next
    end
    next if fenced

    line.scan(/(?<!!)\[[^\]]+\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/) do |match|
      destination = match.first
      next if destination.match?(%r{\A(?:https?|mailto):}i)

      raw_path, raw_fragment = destination.split("#", 2)
      decoded_path = URI.decode_www_form_component(raw_path || "")
      target = decoded_path.empty? ? source : source.dirname.join(decoded_path).cleanpath

      unless target.file?
        errors << "#{source.relative_path_from(ROOT)}:#{line_number}: missing file: #{destination}"
        next
      end
      next if raw_fragment.nil? || raw_fragment.empty?
      next unless target.extname.downcase == ".md"

      fragment = URI.decode_www_form_component(raw_fragment)
      anchors = anchor_cache[target] ||= anchors_for(target)
      next if anchors.include?(fragment)

      errors << "#{source.relative_path_from(ROOT)}:#{line_number}: missing GitHub heading anchor ##{fragment} in #{target.relative_path_from(ROOT)}"
    rescue ArgumentError => error
      errors << "#{source.relative_path_from(ROOT)}:#{line_number}: invalid link #{destination.inspect}: #{error.message}"
    end
  end
end

if errors.empty?
  puts "Markdown links OK (#{MARKDOWN_FILES.length} files checked)."
  exit 0
end

warn errors.join("\n")
exit 1
