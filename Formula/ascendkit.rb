class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.15.0/ascendkit-0.15.0-macos-arm64.tar.gz"
  sha256 "a516837ee7ba754e9be7fdf9541358dd0d5030aea46f5b94243516f25c78e9f0"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
