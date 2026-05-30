class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.6.1/ascendkit-1.6.1-macos-universal.tar.gz"
  sha256 "73b09c686278bd76b865df32de1f60ee7dff20e260d8d07b8453dbd0496fce0f"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
