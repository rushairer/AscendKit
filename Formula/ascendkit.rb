class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.20.0/ascendkit-0.20.0-macos-arm64.tar.gz"
  sha256 "8071db73de4703d004a8804a98bd0cfa1a493843e73a3e350b548b7dc17fbe8f"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
