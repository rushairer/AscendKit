class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.12.0/ascendkit-1.12.0-macos-universal.tar.gz"
  sha256 "42e9725d6ee1a17310b618244936e4b40d7861ca9539e23ef66e9535c47eeddc"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
