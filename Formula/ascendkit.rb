class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.0.0/ascendkit-1.0.0-macos-arm64.tar.gz"
  sha256 "f8bcd2b35d3ef138dd2a3460084eaab35deb76a06ed98d93a2aecb2bb909d06f"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
