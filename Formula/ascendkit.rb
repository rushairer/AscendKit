class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.30.0/ascendkit-0.30.0-macos-arm64.tar.gz"
  sha256 "4620ab9b03f01be07c5184f5bb5d8f40095e5996071b23301218df58ca7af3f8"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
