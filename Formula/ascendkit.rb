class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.26.0/ascendkit-0.26.0-macos-arm64.tar.gz"
  sha256 "4647f88c0182a314e79ef65d0784a69e978aed828330b56db736afdd080df44b"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
